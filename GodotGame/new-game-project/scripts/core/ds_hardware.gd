class_name DSHardware
extends RefCounted
## ARM9-side hardware the translated game code talks to through registers: VRAM banks and their mapping
## (VRAMCNT), palette RAM, OAM, the DMA controller and the game-card ROM interface. The ARM7 side (sound, touch,
## RTC, save chip) is not emulated here; the HLE layers stand in for it.
##
## Everything is modelled at the level the CPU sees it, so the renderer can read the same VRAM/palette/OAM
## contents the original hardware would display.

const BANK_SIZE := [0x20000, 0x20000, 0x20000, 0x20000, 0x10000, 0x4000, 0x4000, 0x8000, 0x4000]
const LCDC_BASE := [0x6800000, 0x6820000, 0x6840000, 0x6860000, 0x6880000, 0x6890000, 0x6894000, 0x6898000, 0x68A0000]
const PAGE := 0x4000                       ## mapping granularity (16 KiB, the smallest bank)

var core                                   ## DSCoreBase (untyped to avoid a cyclic class reference)
var bank: Array = []                       ## 9 PackedByteArray
var vramcnt := PackedByteArray()           ## 9 bytes (0x04000240..0x04000249, skipping WRAMCNT at 0x247)
var pages: Dictionary = {}                 ## CPU page base address -> Array of [bank, offset]
var tex_slots: Array = [[], [], [], []]    ## texture image slots 0..3 -> [[bank, offset]]
var texpal_slots: Array = [[], [], [], [], [], []]   ## texture palette slots (16 KiB each)
var bgext_a: Array = [[], [], [], []]      ## engine A BG extended palette slots (8 KiB each) -> [[bank, offset]]
var objext_a: Array = []                   ## engine A OBJ extended palette (8 KiB)
var bgext_b: Array = [[], [], [], []]
var objext_b: Array = []
var pal := PackedByteArray()               ## 0x05000000 palette RAM (A BG, A OBJ, B BG, B OBJ; 512 B each)
var oam := PackedByteArray()               ## 0x07000000 OAM (A, B; 1 KiB each)
var rom := PackedByteArray()               ## game card image (for ROM reads through the card interface)
var log_card: bool = false
var bank_gen: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0, 0])   ## per-bank write counters
var dbg_dma_src: int = -1                  ## debug: source of the DMA being written (io_hook)
var map_gen: int = 0                       ## incremented by remap_vram (renderer caches key on these)
var dirty_vram: bool = true                ## set on any VRAM/palette/OAM change (renderer cache invalidation)

const CHIP_ID := 0x00003FC2               ## same value DSBoot writes to 0x027FFC00

# card interface state
var _card_buf := PackedByteArray()
var _card_pos: int = 0


func _init(c) -> void:
	core = c
	for s in BANK_SIZE:
		var b := PackedByteArray()
		b.resize(s)
		bank.append(b)
	vramcnt.resize(9)
	pal.resize(0x800)
	oam.resize(0x800)
	remap_vram()


# ------------------------------------------------------------------------------------------------ VRAM mapping
## 0x04000240 + i for banks A-G (i = 0..6), 0x04000248/9 for H/I
static func vramcnt_index(addr: int) -> int:
	var o := addr - 0x04000240
	if o >= 0 and o <= 6:
		return o
	if o == 8 or o == 9:
		return o - 1
	return -1


func set_vramcnt(i: int, v: int) -> void:
	if vramcnt[i] != (v & 0xFF):
		vramcnt[i] = v & 0xFF
		remap_vram()


func _map(base: int, b: int, off: int, size: int) -> void:
	var p := 0
	while p < size:
		var key := base + p
		if not pages.has(key):
			pages[key] = []
		(pages[key] as Array).append([b, off + p])
		p += PAGE


## Rebuild the CPU page table and the texture slot table from VRAMCNT (GBATEK "VRAM bank allocation").
func remap_vram() -> void:
	map_gen += 1
	pages.clear()
	tex_slots = [[], [], [], []]
	texpal_slots = [[], [], [], [], [], []]
	bgext_a = [[], [], [], []]
	objext_a = []
	bgext_b = [[], [], [], []]
	objext_b = []
	for i in 9:
		var cnt: int = vramcnt[i]
		var size: int = BANK_SIZE[i]
		# LCDC is always visible while the bank is enabled in MST 0; we also keep it mapped otherwise so the
		# renderer-side views stay simple (writes through LCDC only happen in MST 0 anyway).
		if (cnt & 0x80) == 0:
			continue
		var mst := cnt & 7
		var ofs := (cnt >> 3) & 3
		match i:
			0, 1, 2, 3:   # A B C D (128 KiB)
				match mst:
					0: _map(LCDC_BASE[i], i, 0, size)
					1: _map(0x6000000 + 0x20000 * ofs, i, 0, size)
					2:
						if i < 2:
							_map(0x6400000 + 0x20000 * (ofs & 1), i, 0, size)
					3: tex_slots[ofs].append([i, 0])
					4:
						if i == 2:
							_map(0x6200000, i, 0, size)
						elif i == 3:
							_map(0x6600000, i, 0, size)
			4:            # E (64 KiB)
				match mst:
					0: _map(LCDC_BASE[i], i, 0, size)
					1: _map(0x6000000, i, 0, size)
					2: _map(0x6400000, i, 0, size)
					3:
						for s in 4:
							texpal_slots[s].append([i, s * 0x4000])
					4:
						for s in 4:
							bgext_a[s].append([i, s * 0x2000])
			5, 6:         # F G (16 KiB)
				var o2 := (ofs & 1) * 0x4000 + (ofs >> 1) * 0x10000
				match mst:
					0: _map(LCDC_BASE[i], i, 0, size)
					1: _map(0x6000000 + o2, i, 0, size)
					2: _map(0x6400000 + o2, i, 0, size)
					3: texpal_slots[(ofs & 1) + (ofs >> 1) * 4].append([i, 0])
					4:
						bgext_a[(ofs & 1) * 2].append([i, 0])
						bgext_a[(ofs & 1) * 2 + 1].append([i, 0x2000])
					5: objext_a.append([i, 0])
			7:            # H (32 KiB)
				if mst == 0:
					_map(LCDC_BASE[i], i, 0, size)
				elif mst == 1:
					_map(0x6200000, i, 0, size)
				elif mst == 2:
					for s in 4:
						bgext_b[s].append([i, s * 0x2000])
			8:            # I (16 KiB)
				match mst:
					0: _map(LCDC_BASE[i], i, 0, size)
					1: _map(0x6208000, i, 0, size)
					2: _map(0x6600000, i, 0, size)
					3: objext_b.append([i, 0])
	dirty_vram = true


## CPU address in 0x06000000-0x06FFFFFF -> page key (folding the engine mirrors)
static func _vram_page(addr: int) -> int:
	var a := addr & 0xFFFFFF
	var region := a & 0xE00000
	var key: int
	match region:
		0x000000: key = 0x6000000 + (a & 0x7FFFF)          # engine A BG, 512 KiB mirrored
		0x200000: key = 0x6200000 + (a & 0x1FFFF)          # engine B BG, 128 KiB
		0x400000: key = 0x6400000 + (a & 0x3FFFF)          # engine A OBJ, 256 KiB
		0x600000: key = 0x6600000 + (a & 0x1FFFF)          # engine B OBJ, 128 KiB
		_: key = 0x6800000 + (a & 0xFFFFF)                 # LCDC
	return key


func vram_read(addr: int, size: int) -> int:
	var key := _vram_page(addr)
	var pk := key & ~(PAGE - 1)
	var lst = pages.get(pk)
	if lst == null:
		return 0
	var v := 0
	for e in lst:
		var b: PackedByteArray = bank[e[0]]
		var o: int = e[1] + (key - pk)
		match size:
			1: v |= b.decode_u8(o)
			2: v |= b.decode_u16(o)
			_: v |= b.decode_u32(o)
	return v


func vram_write(addr: int, size: int, v: int) -> void:
	var key := _vram_page(addr)
	var pk := key & ~(PAGE - 1)
	var lst = pages.get(pk)
	if lst == null:
		return
	for e in lst:   # unlike the GBA, the DS VRAM accepts 8-bit writes (palette/OAM ignore them)
		var b: PackedByteArray = bank[e[0]]
		var o: int = e[1] + (key - pk)
		if size == 1:
			b[o] = v & 0xFF
		elif size == 2:
			b.encode_u16(o, v & 0xFFFF)
		else:
			b.encode_u32(o, v & 0xFFFFFFFF)
		bank_gen[e[0]] += 1
	dirty_vram = true


## bulk copy into VRAM (DMA fast path); src_bytes are written starting at CPU address dst
func vram_write_bytes(dst: int, src_bytes: PackedByteArray) -> void:
	if core.io_hook.is_valid():
		core.io_hook.call(dst, src_bytes.size(), dbg_dma_src)
	var i := 0
	var n := src_bytes.size()
	while i < n:
		var key := _vram_page(dst + i)
		var pk := key & ~(PAGE - 1)
		var chunk := mini(n - i, PAGE - (key - pk))
		var lst = pages.get(pk)
		if lst != null:
			for e in lst:
				if not (_native and DSMemNative.blit(bank, e[0], e[1] + (key - pk), src_bytes, i, chunk)):
					blit(bank[e[0]], e[1] + (key - pk), src_bytes, i, chunk)
				bank_gen[e[0]] += 1
		i += chunk
	dirty_vram = true


## copy n bytes src[soff..] -> dst[doff..] (8 bytes per step; GDScript has no native range copy into an array)
var _native: bool = ClassDB.class_exists("DSMemNative")   ## native/ds_mem_native.cpp bulk copies


static func blit(dst: PackedByteArray, doff: int, src: PackedByteArray, soff: int, n: int) -> void:
	var k := 0
	var n8 := n & ~7
	while k < n8:
		dst.encode_s64(doff + k, src.decode_s64(soff + k))
		k += 8
	while k < n:
		dst[doff + k] = src[soff + k]
		k += 1


## Fast renderer view: `size` bytes of a CPU-visible VRAM region starting at page-aligned `base`
## (bank slices concatenated natively; pages shared by several banks are OR-combined).
func region_view(base: int, size: int) -> PackedByteArray:
	if _native:
		return _region_view_native(base, size)
	var out := PackedByteArray()
	var p := 0
	var zero := PackedByteArray()
	while p < size:
		var lst = pages.get(base + p)
		if lst == null or (lst as Array).is_empty():
			if zero.is_empty():
				zero.resize(PAGE)
			out.append_array(zero)
		elif (lst as Array).size() == 1:
			var e = lst[0]
			out.append_array((bank[e[0]] as PackedByteArray).slice(e[1], e[1] + PAGE))
		else:
			var acc := PackedByteArray()
			acc.resize(PAGE)
			for e in lst:
				var b: PackedByteArray = (bank[e[0]] as PackedByteArray).slice(e[1], e[1] + PAGE)
				for k in PAGE:
					acc[k] |= b[k]
			out.append_array(acc)
		p += PAGE
	return out


## part 32 (exact speed-up): the same bytes, copied page by page straight into one zero-filled buffer by the native
## library (DSMemNative.blit) instead of a slice + append per page (the views are rebuilt for every displayed frame
## in battles: 512 + 256 KiB for engine A); pages shared by several banks are OR-combined as above.
func _region_view_native(base: int, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(size)
	var h := [out]
	var p := 0
	while p < size:
		var lst = pages.get(base + p)
		if lst != null and not (lst as Array).is_empty():
			if (lst as Array).size() == 1:
				var e = lst[0]
				DSMemNative.blit(h, 0, p, bank[e[0]], e[1], PAGE)
			else:
				var acc := PackedByteArray()
				acc.resize(PAGE)
				for e in lst:
					var b: PackedByteArray = (bank[e[0]] as PackedByteArray).slice(e[1], e[1] + PAGE)
					for k in PAGE:
						acc[k] |= b[k]
				DSMemNative.blit(h, 0, p, acc, 0, PAGE)
		p += PAGE
	return h[0]


## the same for slot lists (texture / palette slots: `merge` = banks sharing a slot are OR-ed like _slot_view;
## extended palettes: the first bank only, like slots_view): one native copy per slot
func _slots_native(slots: Array, slot_size: int, merge: bool) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(slots.size() * slot_size)
	var h := [out]
	var o := 0
	for sl in slots:
		var lst: Array = sl if sl is Array else []
		if lst.size() == 1 or (lst.size() > 1 and not merge):
			var e = lst[0]
			DSMemNative.blit(h, 0, o, bank[e[0]], e[1], slot_size)
		elif lst.size() > 1:   # several banks in one slot: contents are OR-ed
			var acc := PackedByteArray()
			acc.resize(slot_size)
			for e in lst:
				var b: PackedByteArray = bank[e[0]]
				for k in slot_size:
					acc[k] |= b[e[1] + k]
			DSMemNative.blit(h, 0, o, acc, 0, slot_size)
		o += slot_size
	return h[0]


## extended palette memory: slots (list of [[bank, offset]]) of `slot_size` bytes each
func slots_view(slots: Array, slot_size: int) -> PackedByteArray:
	if _native:
		return _slots_native(slots, slot_size, false)
	var out := PackedByteArray()
	for sl in slots:
		var lst: Array = sl if sl is Array else []
		if lst.is_empty():
			var z := PackedByteArray()
			z.resize(slot_size)
			out.append_array(z)
		else:
			var e = lst[0]
			out.append_array((bank[e[0]] as PackedByteArray).slice(e[1], e[1] + slot_size))
	return out


## Renderer view of a virtual VRAM space (engine BG/OBJ region): bytes [start, start+len) as seen by the CPU.
func vram_view(cpu_addr: int, length: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(length)
	var i := 0
	while i < length:
		var key := _vram_page(cpu_addr + i)
		var pk := key & ~(PAGE - 1)
		var chunk := mini(length - i, PAGE - (key - pk))
		var lst = pages.get(pk)
		if lst != null:
			for e in lst:
				var b: PackedByteArray = bank[e[0]]
				var o: int = e[1] + (key - pk)
				for k in chunk:
					out[i + k] |= b[o + k]
		i += chunk
	return out


## texture image memory (slot 0..3 = 128 KiB each) and texture palette memory (6 x 16 KiB)
func tex_view() -> PackedByteArray:
	return _slot_view(tex_slots, 0x20000)


func texpal_view() -> PackedByteArray:
	return _slot_view(texpal_slots, 0x4000)


## signature of the banks behind a set of slots: unchanged signature = unchanged view
func slots_sig(slots: Array) -> String:
	var parts := PackedStringArray([str(map_gen)])
	for sl in slots:
		for e in sl:
			parts.append("%d:%d" % [e[0], bank_gen[e[0]]])
	return ",".join(parts)


## signature for region_view(base, size)
func region_sig(base: int, size: int) -> String:
	var parts := PackedStringArray([str(map_gen)])
	var seen := {}
	var p := 0
	while p < size:
		var lst = pages.get(base + p)
		if lst != null:
			for e in lst:
				if not seen.has(e[0]):
					seen[e[0]] = true
					parts.append("%d:%d" % [e[0], bank_gen[e[0]]])
		p += PAGE
	return ",".join(parts)


func _slot_view(slots: Array, slot_size: int) -> PackedByteArray:
	if _native:
		return _slots_native(slots, slot_size, true)
	var out := PackedByteArray()
	var zero := PackedByteArray()
	for sl in slots:
		var lst: Array = sl
		if lst.is_empty():
			if zero.is_empty():
				zero.resize(slot_size)
			out.append_array(zero)
		elif lst.size() == 1:
			var e = lst[0]
			out.append_array((bank[e[0]] as PackedByteArray).slice(e[1], e[1] + slot_size))
		else:   # several banks in one slot: contents are OR-ed
			var acc := PackedByteArray()
			acc.resize(slot_size)
			for e in lst:
				var b: PackedByteArray = bank[e[0]]
				for k in slot_size:
					acc[k] |= b[e[1] + k]
			out.append_array(acc)
	return out


# ------------------------------------------------------------------------------------------------ bus
## Generic ARM9 bus access used by DMA and by run-time dispatched loads/stores outside main RAM.
func bus_read(addr: int, size: int) -> int:
	addr &= 0xFFFFFFFF
	var region := addr >> 24
	match region:
		0x02:
			var o := addr - 0x02000000
			if o < core.SIZE:
				match size:
					1: return core.M.decode_u8(o)
					2: return core.M.decode_u16(o)
					_: return core.M.decode_u32(o)
			return 0
		0x04:
			return core.io_read(addr, size)
		0x05:
			var o := addr & 0x7FF
			match size:
				1: return pal.decode_u8(o)
				2: return pal.decode_u16(o)
				_: return pal.decode_u32(o)
		0x06:
			return vram_read(addr, size)
		0x07:
			var o := addr & 0x7FF
			match size:
				1: return oam.decode_u8(o)
				2: return oam.decode_u16(o)
				_: return oam.decode_u32(o)
	return 0


func bus_write(addr: int, size: int, v: int) -> void:
	addr &= 0xFFFFFFFF
	var region := addr >> 24
	match region:
		0x02:
			var o := addr - 0x02000000
			if o < core.SIZE:
				match size:
					1: core.M.encode_u8(o, v & 0xFF)
					2: core.M.encode_u16(o, v & 0xFFFF)
					_: core.M.encode_u32(o, v & 0xFFFFFFFF)
		0x04:
			core.io_write(addr, size, v)
		0x05:
			if size == 1:
				return
			var o := addr & 0x7FF
			if size == 2:
				pal.encode_u16(o, v & 0xFFFF)
			else:
				pal.encode_u32(o, v & 0xFFFFFFFF)
			dirty_vram = true
		0x06:
			vram_write(addr, size, v)
		0x07:
			if size == 1:
				return
			var o := addr & 0x7FF
			if size == 2:
				oam.encode_u16(o, v & 0xFFFF)
			else:
				oam.encode_u32(o, v & 0xFFFFFFFF)
			dirty_vram = true


# ------------------------------------------------------------------------------------------------ DMA
## Called after a write to DMAxCNT (0x040000B8 + 12*ch). Immediate transfers run at once; HBlank/VBlank
## transfers are left armed and started by the main loop (start_timed). Geometry-FIFO DMA (mode 7) is handled
## by the GX layer through the HLE of the ITCM send routine, card DMA (mode 5) by the card interface.
func dma_control_written(ch: int) -> void:
	var io: PackedByteArray = core.IO
	var base := 0xB0 + 12 * ch
	var cnt := io.decode_u32(base + 8)
	if (cnt & 0x80000000) == 0:
		return
	var timing := (cnt >> 27) & 7
	if timing == 0 or timing == 7:   # immediate, or geometry FIFO (our FIFO is always ready)
		_dma_run(ch)


func dma_start_timed(timing: int) -> void:
	for ch in 4:
		var cnt: int = core.IO.decode_u32(0xB0 + 12 * ch + 8)
		if (cnt & 0x80000000) != 0 and ((cnt >> 27) & 7) == timing:
			_dma_run(ch)


## Card transfers moved by DMA finish inside the DMA loop; their "transfer ready" IRQ is raised at the next
## scanline (DSMachine), as on the hardware, where the DMA has stopped by then. Delivering it inside the loop let
## the card IRQ handler (0x020B264C -> 0x020B2724 -> 0x020AC0B8) wait for the still-running DMA forever
## (Maximum mode hung loading its battle).
var card_irq_pending := false
var _dma_depth := 0


func _dma_run(ch: int) -> void:
	_dma_depth += 1
	_dma_run_inner(ch)
	_dma_depth -= 1


func _dma_run_inner(ch: int) -> void:
	var io: PackedByteArray = core.IO
	var base := 0xB0 + 12 * ch
	var src := io.decode_u32(base) & 0x0FFFFFFE
	var dst := io.decode_u32(base + 4) & 0x0FFFFFFE
	var cnt := io.decode_u32(base + 8)
	var n := cnt & 0x1FFFFF
	if n == 0:
		n = 0x200000
	var w := 4 if (cnt & (1 << 26)) != 0 else 2
	var sctl := (cnt >> 23) & 3
	var dctl := (cnt >> 21) & 3
	var sstep := w if sctl == 0 else (-w if sctl == 1 else 0)
	var dstep := w if (dctl == 0 or dctl == 3) else (-w if dctl == 1 else 0)
	# fill from DMA fill registers when the source is the fill register block itself
	var bytes := n * w
	if w == 4 and sstep == 4 and dstep == 0 and (src >> 24) == 0x02 and dst >= 0x4000400 and dst < 0x4000440:
		# display list streamed into the geometry FIFO: the words are copied now (the 3D engine draws them a
		# frame later, by which time the game may have rewritten the buffer)
		var so := src - 0x02000000
		core.gx_cmds.append([-1, src, n, core.M.slice(so, so + n * 4).to_int32_array()])
	elif sstep == w and dstep == w and (src >> 24) == 0x02 and (dst >> 24) == 0x02:
		var so := src - 0x02000000
		var do_ := dst - 0x02000000
		if not (_native and DSMemNative.copy8([core.M], so, do_, bytes)):
			blit(core.M, do_, core.M.slice(so, so + bytes), 0, bytes)
	elif sstep == w and dstep == w and (src >> 24) == 0x02 and (dst >> 24) == 0x06:
		var so := src - 0x02000000
		dbg_dma_src = src
		vram_write_bytes(dst, core.M.slice(so, so + bytes))
	else:
		var s := src
		var d := dst
		for k in n:
			bus_write(d, w, bus_read(s, w))
			s += sstep
			d += dstep
	if sctl != 2:
		io.encode_u32(base, src + sstep * n)
	if dctl != 2 and dctl != 3:
		io.encode_u32(base + 4, dst + dstep * n)
	var timing := (cnt >> 27) & 7
	if (cnt & (1 << 25)) == 0 or timing == 0 or timing == 7:
		io.encode_u32(base + 8, cnt & 0x7FFFFFFF)
	if (cnt & (1 << 30)) != 0:
		core.raise_irq(8 + ch)


# ------------------------------------------------------------------------------------------------ game card
## ROMCTRL (0x040001A4) written with bit 31: execute the 8-byte command at 0x040001A8 (big endian).
## Only the KEY2 "read data" command (0xB7 aaaaaaaa 00 00 00) matters after boot; other commands return 0xFF.
func card_start() -> void:
	var io: PackedByteArray = core.IO
	var ctrl := io.decode_u32(0x1A4)
	var bs := (ctrl >> 24) & 7
	var length := 0 if bs == 0 else (4 if bs == 7 else (0x100 << bs))
	var cmd := io.slice(0x1A8, 0x1B0)
	_card_buf = PackedByteArray()
	_card_buf.resize(length)
	if cmd[0] == 0xB7:
		var a := (cmd[1] << 24) | (cmd[2] << 16) | (cmd[3] << 8) | cmd[4]
		if log_card:
			print("CARD read %08x len %x" % [a, length])
		if core._tracing:
			core.trace_log.append("CARD read %08x len %x" % [a, length])
		if a < 0x8000:   # secure area reads are redirected on retail hardware
			a = 0x8000 + (a & 0x1FF)
		var chunk := rom.slice(a, a + length)
		if chunk.size() < length:
			var pad := PackedByteArray()
			pad.resize(length - chunk.size())
			pad.fill(0xFF)
			chunk.append_array(pad)
		_card_buf = chunk
	elif cmd[0] == 0xB8 or cmd[0] == 0x90:
		# chip ID (the SDK polls it every frame to detect a pulled-out card): must match 0x027FFC00
		for k in length:
			_card_buf[k] = (CHIP_ID >> (8 * (k & 3))) & 0xFF
	else:
		_card_buf.fill(0xFF)
	_card_pos = 0
	if length == 0:
		io.encode_u32(0x1A4, ctrl & ~0x80800000)
		return
	io.encode_u32(0x1A4, (ctrl | 0x00800000) | 0x80000000)
	# DMA channels armed with start timing "DS cartridge slot" (5) move each word as it becomes ready
	for ch in 4:
		var guard := 0
		while _card_pos < _card_buf.size() and guard < 0x10000:
			var cnt := io.decode_u32(0xB0 + 12 * ch + 8)
			if (cnt & 0x80000000) == 0 or ((cnt >> 27) & 7) != 5:
				break
			_dma_run(ch)
			guard += 1


## all remaining data words of the current card transfer at once (same end-of-transfer effects as reading
## them one by one through 0x04100010)
func card_take_all() -> PackedByteArray:
	if _card_pos >= _card_buf.size():
		return PackedByteArray()
	var n := (_card_buf.size() - _card_pos) / 4 * 4
	var rest := _card_buf.slice(_card_pos, _card_pos + n)
	_card_pos += n
	if _card_pos >= _card_buf.size():
		var io: PackedByteArray = core.IO
		var ctrl := io.decode_u32(0x1A4)
		io.encode_u32(0x1A4, ctrl & ~0x80800000)
		if (io.decode_u16(0x1A0) & 0x4000) != 0:   # transfer-ready IRQ
			if _dma_depth > 0:
				card_irq_pending = true
			else:
				core.raise_irq(19)
	return rest


## read of 0x04100010 (card data in)
func card_read_word() -> int:
	var io: PackedByteArray = core.IO
	if _card_pos + 4 > _card_buf.size():
		return 0xFFFFFFFF
	var v := _card_buf.decode_u32(_card_pos)
	_card_pos += 4
	if _card_pos >= _card_buf.size():
		var ctrl := io.decode_u32(0x1A4)
		io.encode_u32(0x1A4, ctrl & ~0x80800000)
		if (io.decode_u16(0x1A0) & 0x4000) != 0:   # transfer-ready IRQ
			if _dma_depth > 0:
				card_irq_pending = true
			else:
				core.raise_irq(19)
	return v
