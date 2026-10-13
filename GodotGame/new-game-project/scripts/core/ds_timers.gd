class_name DSTimers
extends RefCounted
## ARM9 hardware timers TM0-TM3 (0x04000100-0x0400010F, GBATEK "DS Timers"). They count the 33.513982 MHz bus
## clock through a prescaler (1, 64, 256, 1024) or count the previous timer's overflows (count-up), reload on
## overflow and can raise IRQ 3+n. The port has no CPU cycle counter: time advances by whole scanlines
## (DSMachine, 2130 cycles per line) and a little on every counter read, so polling loops terminate.

const SHIFT := [0, 6, 8, 10]
const READ_CYCLES := 16                  ## time that passes per counter read (busy-wait progress)

var core
var counter := PackedInt32Array([0, 0, 0, 0])
var reload := PackedInt32Array([0, 0, 0, 0])
var control := PackedInt32Array([0, 0, 0, 0])
var sub := PackedInt32Array([0, 0, 0, 0])   ## prescaler remainder in bus cycles


func _init(c) -> void:
	core = c


## the CPU writes TMxCNT_L (reload) / TMxCNT_H (control); starting a timer loads the reload value
func write(o: int, size: int, v: int) -> void:
	for k in size:
		var a := o + k
		if a < 0x100 or a >= 0x110:
			continue
		var n := (a - 0x100) >> 2
		var b := (v >> (8 * k)) & 0xFF
		match (a - 0x100) & 3:
			0: reload[n] = (reload[n] & 0xFF00) | b
			1: reload[n] = (reload[n] & 0x00FF) | (b << 8)
			2:
				var was := control[n]
				control[n] = b
				if (b & 0x80) != 0 and (was & 0x80) == 0:
					counter[n] = reload[n]
					sub[n] = 0


func read(o: int, size: int) -> int:
	advance(READ_CYCLES)
	var v := 0
	for k in size:
		var a := o + k
		if a < 0x100 or a >= 0x110:
			continue
		var n := (a - 0x100) >> 2
		var b := 0
		match (a - 0x100) & 3:
			0: b = counter[n] & 0xFF
			1: b = (counter[n] >> 8) & 0xFF
			2: b = control[n]
		v |= b << (8 * k)
	return v


## advance all running timers by `cycles` bus cycles; overflows reload and may raise IRQs
func advance(cycles: int) -> void:
	var prev_over := 0
	for n in 4:
		var c := control[n]
		var over := 0
		if (c & 0x80) != 0:
			var ticks := 0
			if n > 0 and (c & 4) != 0:
				ticks = prev_over
			else:
				var s: int = SHIFT[c & 3]
				var t := sub[n] + cycles
				ticks = t >> s
				sub[n] = t & ((1 << s) - 1)
			if ticks > 0:
				var v := counter[n] + ticks
				if v >= 0x10000:
					var period := 0x10000 - reload[n]
					var excess := v - 0x10000
					over = 1 + excess / period
					v = reload[n] + excess % period
				counter[n] = v
				if over > 0 and (c & 0x40) != 0:
					core.raise_irq(3 + n)
		prev_over = over
