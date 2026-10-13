class_name DSCore7Base
extends RefCounted
## Runtime for the ARM7 code translated by decomp/tools/transpile/run7.sh (scripts/gen/ds_game7.gd, DSGame7):
## the NitroSDK sound driver. Every memory access goes through _ld/_st, which implement the ARM7 memory map:
##   0x02000000-0x02FFFFFF main RAM (4 MiB, mirrored), shared with the ARM9 (DSCoreBase.M). The ARM7's own part
##                        at 0x027E0000 is the physical 0x023E0000; the shared area 0x027FF000 is kept where
##                        the ARM9 port has it (M offset 0x7FF000).
##   0x037F8000-0x0380FFFF shared WRAM (as mapped to the ARM7) + ARM7 WRAM: W7
##   0x04000000-          ARM7 IO: sound registers (DSSound), IPC FIFO (to the ARM9), the rest stored as written.
## The ARM7 OS services the driver uses (alarms, ticks) and its thread loop are provided by DSArm7.

const W7_BASE := 0x037F8000
const W7_SIZE := 0x18000

var core9                         ## DSCoreBase of the ARM9 (main RAM, IPC)
var sound: DSSound
var W7 := PackedByteArray()
var IO7: Dictionary = {}
var _sp: int = 0x0380C000         ## port stack frames grow upwards (an ARM7 WRAM area the original stacks use)
var _fn: Dictionary = {}
var hle: Dictionary = {}
var _tracing: bool = false
var _break_on: bool = false
var _missing_seen: Dictionary = {}


func _init(c9, snd: DSSound) -> void:
	core9 = c9
	sound = snd
	W7.resize(W7_SIZE)


## main-RAM offset in DSCoreBase.M for an ARM7 address in 0x02xxxxxx
static func _mram(a: int) -> int:
	var p := a & 0x3FFFFF
	return 0x7FF000 + (p & 0xFFF) if p >= 0x3FF000 else p


func _ld(a: int, size: int, signed: bool) -> int:
	a &= 0xFFFFFFFF
	var v := 0
	if a >= 0x02000000 and a < 0x03000000:
		var o := _mram(a)
		match size:
			1: v = core9.M.decode_u8(o)
			2: v = core9.M.decode_u16(o)
			4: v = core9.M.decode_u32(o)
			_: return core9.M.decode_s64(o)
	elif a >= 0x03000000 and a < 0x04000000:
		var o := a - W7_BASE if (a >= W7_BASE and a < W7_BASE + W7_SIZE) else 0x8000 + (a & 0xFFFF)
		match size:
			1: v = W7.decode_u8(o)
			2: v = W7.decode_u16(o)
			4: v = W7.decode_u32(o)
			_: return W7.decode_s64(o)
	else:
		v = io_read(a, size)
	if signed and size < 8:
		var h := 1 << (8 * size - 1)
		v = ((v + h) & ((h << 1) - 1)) - h
	return v


func _st(a: int, size: int, v: int) -> void:
	a &= 0xFFFFFFFF
	if a >= 0x02000000 and a < 0x03000000:
		var o := _mram(a)
		match size:
			1: core9.M.encode_u8(o, v & 0xFF)
			2: core9.M.encode_u16(o, v & 0xFFFF)
			4: core9.M.encode_u32(o, v & 0xFFFFFFFF)
			_: core9.M.encode_s64(o, v)
	elif a >= 0x03000000 and a < 0x04000000:
		var o := a - W7_BASE if (a >= W7_BASE and a < W7_BASE + W7_SIZE) else 0x8000 + (a & 0xFFFF)
		match size:
			1: W7.encode_u8(o, v & 0xFF)
			2: W7.encode_u16(o, v & 0xFFFF)
			4: W7.encode_u32(o, v & 0xFFFFFFFF)
			_: W7.encode_s64(o, v)
	else:
		io_write(a, size, v)


func io_read(a: int, size: int) -> int:
	if a >= 0x04000400 and a < 0x04000520:
		return sound.read(a - 0x04000400, size)
	if a == 0x04000184:   # IPCFIFOCNT: send FIFO never full, receive FIFO empty
		return 0x0101
	return int(IO7.get(a, 0)) & ((1 << (8 * size)) - 1 if size < 8 else -1)


func io_write(a: int, size: int, v: int) -> void:
	if a >= 0x04000400 and a < 0x04000520:
		sound.write(a - 0x04000400, size, v)
		return
	if a == 0x04000188:   # IPCFIFOSEND: ARM7 -> ARM9
		core9.ipc_push(v & 0xFFFFFFFF)
		return
	IO7[a] = v


func load_image(crt0: PackedByteArray, wram: PackedByteArray, wram_bss: int, mram: PackedByteArray, mram_bss: int) -> void:
	for i in wram.size():
		W7[i] = wram[i]
	for i in range(wram.size(), mini(wram.size() + wram_bss, W7_SIZE)):
		W7[i] = 0
	var o := _mram(0x027E0000)
	for i in mram.size():
		core9.M[o + i] = mram[i]
	for i in mram_bss:
		core9.M[o + mram.size() + i] = 0


func _icall(addr: int, a0: int = 0, a1: int = 0, a2: int = 0, a3: int = 0, a4: int = 0, a5: int = 0, a6: int = 0, a7: int = 0) -> int:
	addr &= 0xFFFFFFFE
	if hle.has(addr):
		return int((hle[addr] as Callable).call(a0, a1, a2, a3, a4, a5, a6, a7))
	if _fn.has(addr):
		return int((_fn[addr] as Callable).call(a0, a1, a2, a3, a4, a5, a6, a7))
	return _missing(addr)


func _hle(addr: int, a0: int = 0, a1: int = 0, a2: int = 0, a3: int = 0, a4: int = 0, a5: int = 0, a6: int = 0, a7: int = 0) -> int:
	if hle.has(addr):
		return int((hle[addr] as Callable).call(a0, a1, a2, a3, a4, a5, a6, a7))
	return 0


func _missing(addr: int) -> int:
	if not _missing_seen.has(addr):
		_missing_seen[addr] = true
		push_warning("DSCore7: function %08x not translated/HLE'd" % addr)
	return 0


func _trace(_addr: int, _params: Array) -> void:
	pass


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
	var r := ((a + b) + 0x80000000 & 0xFFFFFFFF) - 0x80000000
	return 1 if r != a + b else 0
func SBORROW4(a: int, b: int) -> int:
	var r := ((a - b) + 0x80000000 & 0xFFFFFFFF) - 0x80000000
	return 1 if r != a - b else 0
func LZCOUNT(a: int) -> int:
	a &= 0xFFFFFFFF
	var n := 32
	while a != 0:
		a >>= 1
		n -= 1
	return n
func software_interrupt(_n: int = 0) -> int: return 0
func coprocessor_moveto(_a: int = 0, _b: int = 0, _c: int = 0, _d: int = 0, _e: int = 0, _f: int = 0) -> int: return 0
func coprocessor_movefrom(_a: int = 0, _b: int = 0, _c: int = 0, _d: int = 0, _e: int = 0) -> int: return 0
