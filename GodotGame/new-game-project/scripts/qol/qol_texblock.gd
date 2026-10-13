extends RefCounted
## The port's own 4 KiB of battle texture VRAM (part 36; moved out of qol_bombs.gd, where part 26 built it). Shared by
## BOMB RAIN (frames + shadow at 0..0xD00) and GREEN DEMON (frame + shadow at 0xD00..0x1000): one block, one key, so
## both can be on at once. Owned by QoLGame (`_tex_block()`, `# ---- GREEN DEMON (part 36)`); no class_name (like
## qol_bombs.gd). Each user `put()`s its texels once; `ok()` (once per battle frame) reserves the block in the game's
## texture VRAM manager when needed and rewrites the texels when the bank no longer holds them.
## Layout of the block: direct-colour texels (bit 15 = opaque), texture offset TEX_OFS + ofs.

const TEX_MGR := 0x020DE380              ## u32 -> the game's texture VRAM manager (DATA_NOTES part 18)
const TEX_KEY := 0x7B0B0B26              ## our block's key (the game's keys: -1, 0x2000000x, small ids)
const TEX_END := 0x60000                 ## the manager's tail sentinel: texture slots 0-2 (A|B|C)
const TEX_BLOCK := 0x1000                ## reserved block: TEX_END - TEX_BLOCK .. TEX_END
const TEX_OFS := TEX_END - TEX_BLOCK     ## texture VRAM offset of the block (slot 2 + 0x1F000)

var g = null                             ## the QoLGame
var bytes := PackedByteArray()           ## the whole block as it must be in VRAM (unused parts 0)
var _seen: Array = [-1, -1, -1]          ## [bank, its write counter, VRAM map counter] when the texels were last checked
var _dbg := Game.args.has("bombdbg") or Game.args.has("gddbg")


func _init(game) -> void:
	g = game
	bytes.resize(TEX_BLOCK)


## a user's texels at block offset `ofs` (written to VRAM by the next ok())
func put(ofs: int, data: PackedByteArray) -> void:
	if data.is_empty() or ofs + data.size() > TEX_BLOCK:
		return
	DSHardware.blit(bytes, ofs, data, 0, data.size())
	_seen = [-1, -1, -1]


## a new battle (the manager is rebuilt with every scene): check everything again
func reset() -> void:
	_seen = [-1, -1, -1]


## Our texture block in the game's texture VRAM manager (blocks {+0 offset, +4 size, +8 key, +0xC refs}, pointers at
## +0x600 sorted by offset between a head and a tail sentinel (offset TEX_END), count u8 +0x7AE < 0x30, free structs
## stacked at +0x6C8; FUN_02010D28 = first-fit allocation). Reserved like FUN_02010D28 reserves, but in the LAST gap
## (TEX_OFS, against the tail sentinel): the game's own first-fit allocations land exactly where they would without
## it, and none can ever overlap it (the manager holds it with 1 reference nobody releases; the manager is rebuilt by
## every scene reset, then it is reserved again). Its texels are written straight into the bank behind texture slot 2
## (QoLButton does the same for Mode Select) and rewritten whenever that bank was written and they differ. Returns
## false (nothing may be drawn from it) when the layout is not the battle's: manager missing / full, slot 2 not one
## bank, last gap too small.
func ok() -> bool:
	var mg: int = _ld(TEX_MGR, 4)
	if mg == 0:
		return false
	var n: int = _ld(mg + 0x7AE, 1)
	var p: int = _ld(mg + 0x600 + n * 4, 4)          # the last block (ours once reserved)
	if n == 0 or _ld(p + 8, 4) != TEX_KEY or _ld(p, 4) != TEX_OFS:
		p = 0
		for i in range(1, n + 1):                       # (anywhere else: an unexpected order, not ours to move)
			var q: int = _ld(mg + 0x600 + i * 4, 4)
			if _ld(q + 8, 4) == TEX_KEY:
				p = q
				break
		if p != 0 and _ld(p, 4) != TEX_OFS:
			return false
		if p == 0:
			p = _reserve(mg, n)
			if p == 0:
				return false
	var hw = g.hw
	var sl: Array = hw.tex_slots[2]
	if sl.size() != 1:
		return false
	var b: int = sl[0][0]
	if b == _seen[0] and hw.bank_gen[b] == _seen[1] and hw.map_gen == _seen[2]:
		return true                                     # nothing written to that bank since the last check
	var o: int = sl[0][1] + (TEX_OFS - 0x40000)
	if o + TEX_BLOCK > (hw.bank[b] as PackedByteArray).size():
		return false
	if (hw.bank[b] as PackedByteArray).slice(o, o + TEX_BLOCK) != bytes:
		DSHardware.blit(hw.bank[b], o, bytes, 0, TEX_BLOCK)   # (into the bank itself, as QoLButton does)
		hw.bank_gen[b] += 1                             # the renderer re-uploads texture memory
		hw.dirty_vram = true
		if _dbg:
			print("TEXBLOCK f%d texture written: bank %d + %x (texture offset %x, manager blocks %d)" % [g._port_frame(), b, o, TEX_OFS, n])
	_seen = [b, hw.bank_gen[b], hw.map_gen]
	return true


## FUN_02010D28's insertion, at the end of the list; 0 when it does not fit
func _reserve(mg: int, n: int) -> int:
	if n >= 0x2F or n == 0:
		return 0                                        # full, or no battle textures yet (head sentinel case)
	var tail: int = _ld(mg + 0x600 + (n + 1) * 4, 4)
	var last: int = _ld(mg + 0x600 + n * 4, 4)
	if _ld(tail, 4) != TEX_END or _ld(last, 4) + _ld(last + 4, 4) >= TEX_OFS:
		return 0
	var p: int = _ld(mg + 0x6C8 + (0x2F - n) * 4, 4)  # the next free block struct
	if p == 0:
		return 0
	_st(p, 4, TEX_OFS)
	_st(p + 4, 4, TEX_BLOCK)
	_st(p + 8, 4, TEX_KEY)
	_st(p + 0xC, 4, 1)
	_st(mg + 0x600 + (n + 2) * 4, 4, tail)
	_st(mg + 0x600 + (n + 1) * 4, 4, p)
	_st(mg + 0x7AE, 1, n + 1)
	_seen = [-1, -1, -1]
	if _dbg:
		print("TEXBLOCK f%d texture block reserved at %x (+%x) in the game's texture manager, blocks %d -> %d" % [g._port_frame(),
			TEX_OFS, TEX_BLOCK, n, n + 1])
	return p


func _ld(a: int, n: int) -> int:
	return g._ld(a, n, false)


func _st(a: int, n: int, v: int) -> void:
	g._st(a, n, v)
