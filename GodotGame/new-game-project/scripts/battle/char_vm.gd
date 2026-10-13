class_name CharVM
extends RefCounted
## Port of the character behaviour VM (ARM9 0x02022930; dispatch at 0x02022ACC, jump table 0x02022ADC).
##
## One call to tick() = one call of the original per frame. Register names follow the fighter
## object fields they live in on the DS (see decomp/DATA_NOTES.md, "Behaviour data"):
##   pc        = r8 while running, saved to fighter+0x104 on yield
##   anim_ptr  = fighter+0x100 (target of the last goto; op 0x01 loops to anim_ptr + 10)
##   timer     = fighter+0x10C (frame hold counter)
##   header    = fighter+0x118 (pointer to the action header's 8 parameter bytes)
## Opcode lengths are the verified table from decomp/tools/charscript.py. Ops whose semantics are not
## ported yet are skipped by length and counted in `unported` (shown by the debug overlay).

const OPLEN: PackedByteArray = [
	10, 2, 6, 8, 66, 6, 10, 10, 2, 2, 2, 2, 2, 2, 8, 4, 2, 4, 6, 6,
	2, 6, 4, 0, 2, 6, 2, 2, 6, 4, 6, 4, 4, 4, 2, 4, 6, 4, 4, 4,
	2, 2, 2, 4, 8, 2, 6, 4, 4, 4, 4, 2, 2, 2, 4, 2, 2, 2, 10, 2,
	2, 14, 14, 8, 2, 14, 2, 6, 2, 6, 8, 2, 2, 8, 8, 6, 6, 6, 6, 6,
	4, 2, 2, 2, 6, 6, 6, 4, 4, 8, 10, 4, 8, 8, 6, 6, 2, 0, 0, 6,
	4, 4, 8, 6, 6, 4, 4, 4, 6, 2, 2, 0, 4, 6, 4, 10, 4, 2, 8, 8,
	14, 14, 6, 6, 6, 2, 2, 2, 2, 2, 2, 2, 6, 14, 2, 6, 6, 2, 6, 6,
	2, 2, 6, 2, 2, 2, 6]

var data: CharData
var pc: int = 0
var anim_ptr: int = 0
var timer: int = 0
var header: int = 0
var frame_table: int = -1        ## chunk offset of the 16-entry direction frame table last shown
var frame_id: int = 0
var flip_h: bool = false
var anim_done: bool = false      ## fighter+0x0E bit 0 (set by op 0x01 mode 1 = hold last frame)
var action_ended: bool = false   ## op 0x01 mode >= 2: fighter+4 = 2 (action finished, C code picks the next)
var repeat_counter: int = 0      ## fighter+0x112 (op 0x12)
var unported: Dictionary = {}    ## opcode -> times skipped


func _init(d: CharData) -> void:
	data = d


func start_action(action_id: int) -> void:
	var off := data.action_offset(action_id)
	pc = off
	anim_ptr = off
	timer = 0
	anim_done = false
	action_ended = false


## angle = fighter facing/travel angle byte (0 = right, 128 = left); see op 0x03 handler 0x02022FF0
func tick(angle: int) -> void:
	if timer != 0:
		timer -= 1
		return
	var start_pc := pc
	var shown := false
	var guard := 0
	while guard < 256:
		guard += 1
		var op := data.u8(pc)
		match op:
			0x00:   # action header: remember parameter block, clear per-action state
				header = pc + 2
				pc += 10
			0x01:   # end / loop
				var mode := data.u8(pc + 1)
				if mode == 0:
					pc = anim_ptr + 10
				elif mode == 1:
					anim_done = true
					pc = start_pc   # hold: r8 = fighter+0x104 (pointer saved at the start of this tick)
					return
				else:
					action_ended = true
					return
			0x03:   # show frame (direction table) for `duration` extra ticks
				if shown:
					return          # a second frame in one tick = yield; resumes here next tick
				_show(data.u32(pc + 2), angle)
				timer = data.u16(pc + 6)
				pc += 8
				shown = true
			0x04:   # goto by direction (16 targets)
				var idx := _dir_index(angle)
				var t := data.u32(pc + 2 + idx[0] * 4)
				anim_ptr = t
				pc = t
			0x05:   # goto
				var t5 := data.u32(pc + 2)
				anim_ptr = t5
				pc = t5
			0x12:   # repeat: while counter != 0 { counter--; goto target }
				if repeat_counter != 0:
					repeat_counter -= 1
					var t12 := data.u32(pc + 2)
					anim_ptr = t12
					pc = t12
				else:
					pc += 6
			_:
				var n := OPLEN[op] if op < OPLEN.size() else 0
				if n == 0:
					push_warning("CharVM %s: invalid opcode %02x at %x" % [data.code, op, pc])
					return
				unported[op] = int(unported.get(op, 0)) + 1
				pc += n


func _dir_index(angle: int) -> Array:
	var r := (((angle + 0x40) & 0xFF) >> 3) & 0xFF
	if r >= 16:
		return [r - 16, true]
	return [15 - r, false]


func _show(table_off: int, angle: int) -> void:
	var di := _dir_index(angle)
	frame_table = table_off
	frame_id = data.u16(table_off + int(di[0]) * 2)
	flip_h = di[1]
