class_name QoLButton
extends RefCounted
## Mode Select's centre tile (the unused Dragon Ball tile that opens the port's settings menu) shows the port's
## own picture, `assets_qol/port_button.png` (the user's art: gears + a "PORT" label like the other tiles' labels).
##
## Mode Select draws its nine tiles as textured 3D quads (engine A BG0 = 3D, lower screen): each tile is an 80x44
## corner of its own 128x64 4-bit texture in texture slot 0 (tile k at texture offset k * 0x1000; the centre tile =
## 0x4000, used by nothing else), all with texture palette 0. The game's own cursor frame, the screen fades
## (MASTER_BRIGHT) and transitions are drawn on top of / applied to that texture, so writing the picture into the
## texture keeps all of them. Each time the game (re)loads Mode Select's textures the tile is written again: while
## Mode Select's scene runs, the texture is compared with the picture whenever its VRAM bank was written to or
## remapped, and rewritten when it differs (the game loads the textures in the frame it sets the scene slot). The picture is mapped once to texture palette 0's colours 1..15 (transparent pixels -> 0): the
## nearest colour in CIELAB, each palette colour taken as Mode Select shows it (MASTER_BRIGHT_A 0x8001 = 15/16; the
## picture's colours are screen colours), so the game's palette and its fades stay in charge.
## DATA_NOTES "part 22 findings (mode select tile)".

const MS_VBLANK_CB := 0x020DE374     ## the scene's VBlank callback slot: 0x020738E0 while Mode Select runs
const MS_VBLANK_FN := 0x020738E0
const TEX_OFS := 0x4000              ## the centre tile's texture in texture slot 0
const W := 80                        ## the part of the 128x64 texture the tile's quad shows
const H := 44
const ROW := 64                      ## bytes per texture row (128 texels at 4 bits)
const PICTURE := "res://assets_qol/port_button.png"
const SHOWN := 15.0 / 16.0           ## Mode Select's MASTER_BRIGHT_A 0x8001 (down 1/16): the colours as seen

var _img: Image                      ## the picture (RGBA8, 80x44); null = not available (nothing is changed)
var _ours := PackedByteArray()       ## the picture as 4-bit texels, 40 bytes per row
var _dbg := false
var _seen: Array = [-1, -1, -1]      ## [bank, its write counter, VRAM map counter] when the tile was last checked


func _init() -> void:
	_dbg = Game.args.has("btndbg")
	if Game.args.has("nobutton"):        # debug / A-B tests: the game's own Dragon Ball tile
		return
	var tex = load(PICTURE) if ResourceLoader.exists(PICTURE) else null
	if tex is Texture2D:
		_img = (tex as Texture2D).get_image()
	if _img != null:
		if _img.is_compressed():
			_img.decompress()
		_img.convert(Image.FORMAT_RGBA8)
		if _img.get_width() != W or _img.get_height() != H:
			push_warning("QoLButton: %s is %dx%d, expected %dx%d" % [PICTURE, _img.get_width(), _img.get_height(), W, H])
			_img = null


## after every emulated frame (QoLController.after_step)
func frame(core, f: int = 0) -> void:
	if _dbg:
		_debug(core, f)
	if _img == null or core.r32(MS_VBLANK_CB) != MS_VBLANK_FN:
		return
	var hw: DSHardware = core.hw
	var sl: Array = hw.tex_slots[0]
	var pl: Array = hw.texpal_slots[0]
	if sl.size() != 1 or pl.size() != 1:   # banks not (or not simply) mapped as texture memory right now
		return
	var b: int = sl[0][0]
	var o: int = sl[0][1] + TEX_OFS
	if b == _seen[0] and hw.bank_gen[b] == _seen[1] and hw.map_gen == _seen[2]:   # nothing written to that bank since the last check
		return
	if _ours.is_empty():
		_quantize(hw.bank[pl[0][0]], pl[0][1])
	var same := true
	for y in H:
		var r: int = o + y * ROW
		if hw.bank[b].slice(r, r + W / 2) != _ours.slice(y * W / 2, (y + 1) * W / 2):
			same = false
			break
	if not same:
		for y in H:
			DSHardware.blit(hw.bank[b], o + y * ROW, _ours, y * W / 2, W / 2)
		hw.bank_gen[b] += 1          # the renderer re-uploads texture memory when a bank's counter changes
		hw.dirty_vram = true
	_seen = [b, hw.bank_gen[b], hw.map_gen]
	if not same and _dbg:
		print("BTN f%d centre tile written (texture bank %d + %x)" % [f, b, o])


var _dbg_last := ""


## btndbg: a line whenever the scene slot, Mode Select step, MASTER_BRIGHT_A, the texture slot 0 mapping, the
## centre tile's texels or texture palette 0 change
func _debug(core, f: int) -> void:
	var hw: DSHardware = core.hw
	var sl: Array = hw.tex_slots[0]
	var pl: Array = hw.texpal_slots[0]
	var t := "-"
	var p := "-"
	if sl.size() == 1:
		var o: int = sl[0][1] + TEX_OFS
		t = hw.bank[sl[0][0]].slice(o, o + H * ROW).hex_encode().md5_text().left(8)
	if pl.size() == 1:
		p = hw.bank[pl[0][0]].slice(pl[0][1], pl[0][1] + 32).hex_encode().md5_text().left(8)
	var s := "cb %x st %d mb %x slot0 %s tile %s pal0 %s" % [core.r32(MS_VBLANK_CB), core.r8(0x020DEBD8),
		core.IO.decode_u32(0x6C), str(sl), t, p]
	if s != _dbg_last:
		_dbg_last = s
		print("BTN f%d %s" % [f, s])


## the picture -> texels of palette 0 (index 0 = transparent)
func _quantize(pbank: PackedByteArray, po: int) -> void:
	var labs: Array = []   # [index, Lab] for each colour as Mode Select shows it
	for i in range(1, 16):
		var v := pbank.decode_u16(po + i * 2)
		var c := Color8(((v & 31) * 255) / 31, (((v >> 5) & 31) * 255) / 31, (((v >> 10) & 31) * 255) / 31)
		labs.append([i, _lab(Color(c.r * SHOWN, c.g * SHOWN, c.b * SHOWN))])
	var memo := {}
	_ours.resize(W * H / 2)
	_ours.fill(0)
	for y in H:
		for x in W:
			var c := _img.get_pixel(x, y)
			var idx := 0
			if c.a >= 0.5:
				var key := c.to_rgba32() | 0xFF
				if memo.has(key):
					idx = memo[key]
				else:
					var l := _lab(c)
					var best := INF
					for e in labs:
						var d: float = l.distance_squared_to(e[1])
						if d < best:
							best = d
							idx = e[0]
					memo[key] = idx
					if _dbg:
						print("BTN colour %s -> index %d (%04x) dE %.2f" % [c.to_html(false), idx, pbank.decode_u16(po + idx * 2), sqrt(best)])
			_ours[y * W / 2 + x / 2] |= idx << (4 * (x & 1))


static func _lab(c: Color) -> Vector3:
	var r := _lin(c.r)
	var g := _lin(c.g)
	var bl := _lin(c.b)
	var fx := _f((0.4124 * r + 0.3576 * g + 0.1805 * bl) / 0.95047)
	var fy := _f(0.2126 * r + 0.7152 * g + 0.0722 * bl)
	var fz := _f((0.0193 * r + 0.1192 * g + 0.9505 * bl) / 1.08883)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
