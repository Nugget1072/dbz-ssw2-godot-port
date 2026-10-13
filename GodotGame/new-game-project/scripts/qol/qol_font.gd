class_name QoLFont
extends RefCounted
## Text for the QoL menu in the game's own font: `romdata/scene/font_eu.bin` (the European text font, 9x15 cells,
## glyphs 5 px wide and 10 px tall; the Option screen's descriptions use it), read from the player's ROM at startup
## (nothing is stored in the port). Styles: REGULAR (the game's text, 6 px per character), BOLD (strokes widened by
## 1 px without closing gaps, 7 px), LABEL (bold + italic) and BIG (bold + italic, 13 px tall like the Option
## screen's row labels). If the ROM font cannot be found a built-in 5x7 font is used in the same cells.

enum { REGULAR, BOLD, LABEL, BIG, HEAVY }
const CELL_W := 9
const CELL_H := 15
const CAP_TOP := 3          ## first row of a capital letter in the font's cell
const CAP := [10, 10, 10, 13, 10]   ## capital height per style
const FIRST := 0x21         ## the font starts at '!'; 28 glyphs per row of its 256x256 2bpp texture
const PER_ROW := 28
const GW := 13              ## atlas cell (glyph + bold + italic shear)
const GH := 18
const ADV := [6, 7, 7, 7, 8]
const _STRETCH := [0, 1, 2, 2, 3, 4, 5, 5, 6, 7, 8, 8, 9]   ## BIG: cap row -> source cap row (10 -> 13 rows)

## HEAVY: hand-drawn bold capitals in the style of the game's own screen titles ("STORY MODE", "GAME RANK"),
## 10 rows, strokes 3 px wide and 2 px tall, proportional (advance = width + 1)
const HEAVY_GLYPHS := {
	"A": ["..####..", ".######.", "###..###", "###..###", "###..###", "########", "########", "###..###", "###..###", "###..###"],
	"B": ["#######.", "########", "###..###", "###..###", "#######.", "########", "###..###", "###..###", "########", "#######."],
	"C": [".######.", "########", "###..###", "###.....", "###.....", "###.....", "###.....", "###..###", "########", ".######."],
	"D": ["#######.", "########", "###..###", "###..###", "###..###", "###..###", "###..###", "###..###", "########", "#######."],
	"E": ["########", "########", "###.....", "###.....", "#######.", "#######.", "###.....", "###.....", "########", "########"],
	"F": ["########", "########", "###.....", "###.....", "#######.", "#######.", "###.....", "###.....", "###.....", "###....."],
	"G": [".######.", "########", "###..###", "###.....", "###.####", "###.####", "###..###", "###..###", "########", ".######."],
	"H": ["###..###", "###..###", "###..###", "###..###", "########", "########", "###..###", "###..###", "###..###", "###..###"],
	"I": ["####", "####", "####", "####", "####", "####", "####", "####", "####", "####"],
	"J": [".....###", ".....###", ".....###", ".....###", ".....###", ".....###", "###..###", "###..###", "########", ".######."],
	"K": ["###..###", "###..###", "###.###.", "######..", "#####...", "######..", "###.###.", "###..###", "###..###", "###..###"],
	"L": ["###.....", "###.....", "###.....", "###.....", "###.....", "###.....", "###.....", "###.....", "########", "########"],
	"M": ["###...###", "####.####", "#########", "#########", "###.#.###", "###.#.###", "###...###", "###...###", "###...###", "###...###"],
	"N": ["###..###", "####.###", "####.###", "########", "########", "########", "###.####", "###.####", "###..###", "###..###"],
	"O": [".######.", "########", "###..###", "###..###", "###..###", "###..###", "###..###", "###..###", "########", ".######."],
	"P": ["#######.", "########", "###..###", "###..###", "########", "#######.", "###.....", "###.....", "###.....", "###....."],
	"Q": [".######.", "########", "###..###", "###..###", "###..###", "###..###", "###..###", "###.####", "########", ".#######"],
	"R": ["#######.", "########", "###..###", "###..###", "########", "#######.", "###.###.", "###..###", "###..###", "###..###"],
	"S": [".######.", "########", "###..###", "###.....", "#######.", ".#######", ".....###", "###..###", "########", ".######."],
	"T": ["########", "########", "..####..", "..####..", "..####..", "..####..", "..####..", "..####..", "..####..", "..####.."],
	"U": ["###..###", "###..###", "###..###", "###..###", "###..###", "###..###", "###..###", "###..###", "########", ".######."],
	"V": ["###..###", "###..###", "###..###", "###..###", "###..###", "###..###", ".######.", ".######.", "..####..", "..####.."],
	"W": ["###....###", "###....###", "###....###", "###.##.###", "###.##.###", "###.##.###", "##########", "##########", ".###..###.", ".###..###."],
	"X": ["###..###", "###..###", ".######.", ".######.", "..####..", "..####..", ".######.", ".######.", "###..###", "###..###"],
	"Y": ["###..###", "###..###", "###..###", ".######.", ".######.", "..####..", "..####..", "..####..", "..####..", "..####.."],
	"Z": ["########", "########", "....####", "...####.", "..####..", ".####...", "####....", "###.....", "########", "########"],
	"0": [".######.", "########", "###..###", "###.####", "###.####", "####.###", "####.###", "###..###", "########", ".######."],
	"1": ["...###..", "..####..", ".#####..", "...###..", "...###..", "...###..", "...###..", "...###..", ".#######", ".#######"],
	"2": [".######.", "########", "###..###", ".....###", "...#####", ".#####..", "####....", "###.....", "########", "########"],
	"3": ["#######.", "########", ".....###", ".....###", ".######.", ".######.", ".....###", ".....###", "########", "#######."],
	"4": ["###..###", "###..###", "###..###", "###..###", "########", "########", ".....###", ".....###", ".....###", ".....###"],
	"5": ["########", "########", "###.....", "#######.", "########", ".....###", ".....###", "###..###", "########", ".######."],
	"6": [".######.", "########", "###.....", "#######.", "########", "###..###", "###..###", "###..###", "########", ".######."],
	"7": ["########", "########", ".....###", "....###.", "...###..", "..###...", "..###...", "..###...", "..###...", "..###..."],
	"8": [".######.", "########", "###..###", "###..###", ".######.", "########", "###..###", "###..###", "########", ".######."],
	"9": [".######.", "########", "###..###", "###..###", "########", ".#######", ".....###", ".....###", "########", ".######."],
	"-": [".....", ".....", ".....", ".....", "#####", "#####", ".....", ".....", ".....", "....."],
	"/": ["....###", "....###", "...###.", "...###.", "..###..", "..###..", ".###...", ".###...", "###....", "###...."],
	".": ["...", "...", "...", "...", "...", "...", "...", "...", "###", "###"],
	"!": ["###", "###", "###", "###", "###", "###", "###", "...", "###", "###"],
	"'": ["###", "###", ".##", "##.", "...", "...", "...", "...", "...", "..."],
	"%": ["##...##", "##..###", "...###.", "..###..", "..###..", ".###...", "###....", "##..##.", "##..##.", "......."],
}
const HEAVY_SPACE := 4
var _heavy_x := {}                 ## char -> [atlas x, width]

var tex: Array[ImageTexture] = []
var from_rom := false
var _count := 0


func _init(rom: PackedByteArray = PackedByteArray()) -> void:
	var cells := _rom_cells(rom)
	from_rom = not cells.is_empty()
	if not from_rom:
		cells = _builtin_cells()
	_count = cells.size()
	for style in 5:
		var img := Image.create(_count * GW, GH, false, Image.FORMAT_RGBA8)
		var h: int = CAP[style]
		for k in _count:
			var g: PackedByteArray = cells[k]
			if style == HEAVY:   # the game's header titles: horizontal strokes 2 px tall, all strokes 2 px wide
				g = _bold(_bold_down(g))
			elif style != REGULAR:
				g = _bold(g)
			# output rows: 0 .. h-1 = capitals, then the font's descender rows (13, 14) below them
			for oy in h + 2:
				var src: int = (_STRETCH[oy] if style == BIG else oy) if oy < h else (11 if style == HEAVY else 10) + oy - h
				var sy: int = CAP_TOP + src
				var sh := maxi(0, (h - 1 - oy + 1) / 4) if style == LABEL or style == BIG else 0   # italic: 1 px per 4 rows
				for x in CELL_W:
					if sy < CELL_H and g[sy * CELL_W + x]:
						img.set_pixel(k * GW + x + sh, oy + 1, Color.WHITE)
				if oy == 0:   # rows above the capitals (accents, quotes) are not needed: tall glyphs keep row 2
					for x in CELL_W:
						if g[(CAP_TOP - 1) * CELL_W + x]:
							img.set_pixel(k * GW + x + sh, 0, Color.WHITE)
		tex.append(ImageTexture.create_from_image(img))
	tex[HEAVY] = _heavy_atlas()


func _heavy_atlas() -> ImageTexture:
	var total := 0
	for k in HEAVY_GLYPHS:
		total += (HEAVY_GLYPHS[k][0] as String).length() + 1
	var img := Image.create(total, GH, false, Image.FORMAT_RGBA8)
	var x := 0
	for k in HEAVY_GLYPHS:
		var rows: Array = HEAVY_GLYPHS[k]
		var w: int = (rows[0] as String).length()
		_heavy_x[k] = [x, w]
		for y in rows.size():
			for i in w:
				if (rows[y] as String)[i] == "#":
					img.set_pixel(x + i, y + 1, Color.WHITE)
		x += w + 1
	return ImageTexture.create_from_image(img)


## 1-px taller horizontal strokes (pixels with a horizontal neighbour spread down unless that would touch the
## next stroke; diagonals and vertical strokes stay as they are)
static func _bold_down(g: PackedByteArray) -> PackedByteArray:
	var o := g.duplicate()
	for y in CELL_H - 1:
		for x in CELL_W:
			var horiz: bool = (x > 0 and g[y * CELL_W + x - 1]) or (x + 1 < CELL_W and g[y * CELL_W + x + 1])
			if g[y * CELL_W + x] and horiz and not (y + 2 < CELL_H and g[(y + 2) * CELL_W + x]):
				o[(y + 1) * CELL_W + x] = 1
	return o


## 1-px wider strokes: a pixel spreads right unless that would touch the next stroke (keeps W, M, m open)
static func _bold(g: PackedByteArray) -> PackedByteArray:
	var o := g.duplicate()
	for y in CELL_H:
		for x in CELL_W - 1:
			if g[y * CELL_W + x] and not (x + 2 < CELL_W and g[y * CELL_W + x + 2]):
				o[y * CELL_W + x + 1] = 1
	return o


## the font file in the ROM's file system: an archive with one texture ("font_eu.ntft"), RLE-compressed (type 0x30)
static func _rom_cells(rom: PackedByteArray) -> Array:
	var f := nitro_file(rom, "romdata/scene/font_eu.bin")
	if f.x < 0 or f.y - f.x < 0xA4:
		return []
	var data := f.x + rom.decode_u32(f.x + 4)
	if data + 4 > f.y or rom[data] != 0x30 or (rom.decode_u32(data) >> 8) != 16384:
		return []
	var n := 16384
	var out := PackedByteArray()
	out.resize(n)
	var o := 0
	var i := data + 4
	while o < n and i < f.y:
		var flag := rom[i]
		i += 1
		var cnt := (flag & 0x7F) + (3 if flag & 0x80 else 1)
		for k in cnt:
			if o < n:
				out[o] = rom[i] if flag & 0x80 else rom[i + k]
				o += 1
		i += 1 if flag & 0x80 else cnt
	var cells := []
	for k in 0x7F - FIRST:                  # '!' .. '~'
		var r := k / PER_ROW
		var c := k % PER_ROW
		var g := PackedByteArray()
		g.resize(CELL_W * CELL_H)
		for y in CELL_H:
			for x in CELL_W:
				var px := c * CELL_W + x
				var py := r * CELL_H + y
				var b := out[(py * 256 + px) >> 2]
				g[y * CELL_W + x] = 1 if ((b >> ((px & 3) * 2)) & 3) != 0 else 0
		cells.append(g)
	return cells


## NitroFS lookup: [start, end) of the file at `path` in the ROM image, or (-1, -1)
static func nitro_file(rom: PackedByteArray, path: String) -> Vector2i:
	if rom.size() < 0x200:
		return Vector2i(-1, -1)
	var fnt := rom.decode_u32(0x40)
	var fat := rom.decode_u32(0x48)
	var dir := 0
	var parts := path.split("/")
	for pi in parts.size():
		var want: String = parts[pi]
		var e := fnt + dir * 8
		var p := fnt + rom.decode_u32(e)
		var file_id := rom.decode_u16(e + 4)
		var found := false
		while p < rom.size():
			var lt := rom[p]
			if lt == 0:
				break
			var ln := lt & 0x7F
			var nm := rom.slice(p + 1, p + 1 + ln).get_string_from_ascii()
			p += 1 + ln
			if lt & 0x80:
				var sub := rom.decode_u16(p) & 0xFFF
				p += 2
				if nm == want and pi < parts.size() - 1:
					dir = sub
					found = true
					break
			else:
				if nm == want and pi == parts.size() - 1:
					var a := rom.decode_u32(fat + file_id * 8)
					var b := rom.decode_u32(fat + file_id * 8 + 4)
					return Vector2i(a, b) if b <= rom.size() and a < b else Vector2i(-1, -1)
				file_id += 1
		if not found:
			return Vector2i(-1, -1)
	return Vector2i(-1, -1)


func width(text: String, style: int = REGULAR) -> int:
	if style == HEAVY:
		var w := 0
		for ch in text.to_upper():
			w += (_heavy_x[ch][1] + 1) if _heavy_x.has(ch) else HEAVY_SPACE
		return maxi(0, w - 1)
	return maxi(0, text.length() * ADV[style] - 1) + (2 if style == LABEL or style == BIG else 0) + (1 if style == HEAVY else 0)


## draws `text` with its cap box at `pos` (top-left of the capitals); `outline` adds a 1-px border like the game's
## labels
func draw(ci: CanvasItem, pos: Vector2, text: String, color: Color, style: int = REGULAR, outline: Color = Color(0, 0, 0, 0)) -> void:
	var p := Vector2(floorf(pos.x) - 2, floorf(pos.y) - 1)
	if outline.a > 0.0:
		for d in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]:
			_run(ci, p + d, text, outline, style)
	_run(ci, p, text, color, style)


func _run(ci: CanvasItem, p: Vector2, text: String, color: Color, style: int) -> void:
	var x := p.x
	if style == HEAVY:
		x += 2                      # hand-drawn glyphs start at their first column (no cell margin)
		for ch in text.to_upper():
			if _heavy_x.has(ch):
				var hx: Array = _heavy_x[ch]
				ci.draw_texture_rect_region(tex[HEAVY], Rect2(x, p.y, hx[1], GH), Rect2(hx[0], 0, hx[1], GH), color)
				x += hx[1] + 1
			else:
				x += HEAVY_SPACE
		return
	for ch in text:
		var k := ch.unicode_at(0) - FIRST
		if k >= 0 and k < _count:
			ci.draw_texture_rect_region(tex[style], Rect2(x, p.y, GW, GH), Rect2(k * GW, 0, GW, GH), color)
		x += ADV[style]


## centred in `rect` (by the capitals' box)
func draw_centered(ci: CanvasItem, rect: Rect2, text: String, color: Color, style: int = REGULAR, outline: Color = Color(0, 0, 0, 0)) -> void:
	var p := rect.position + Vector2(floorf((rect.size.x - width(text, style)) / 2.0), floorf((rect.size.y - CAP[style]) / 2.0))
	draw(ci, p, text, color, style, outline)


# ------------------------------------------------------------------------------------------------ fallback
const _B := {
	"A": ".###.#...##...######...##...##...#", "B": "####.#...##...#####.#...##...#####.", "C": ".###.#...##....#....#....#...#.###.",
	"D": "####.#...##...##...##...##...#####.", "E": "######....#....####.#....#....#####", "F": "######....#....####.#....#....#....",
	"G": ".###.#...##....#.####...##...#.####", "H": "#...##...##...#######...##...##...#", "I": ".###...#....#....#....#....#...###.",
	"J": "..###...#....#....#....#.#..#..##..", "K": "#...##..#.#.#..##...#.#..#..#.#...#", "L": "#....#....#....#....#....#....#####",
	"M": "#...###.###.#.##.#.##...##...##...#", "N": "#...##...###..##.#.##..###...##...#", "O": ".###.#...##...##...##...##...#.###.",
	"P": "####.#...##...#####.#....#....#....", "Q": ".###.#...##...##...##.#.##..#..##.#", "R": "####.#...##...#####.#.#..#..#.#...#",
	"S": ".#####....#.....###.....#....#####.", "T": "#####..#....#....#....#....#....#..", "U": "#...##...##...##...##...##...#.###.",
	"V": "#...##...##...##...##...#.#.#...#..", "W": "#...##...##...##.#.##.#.##.#.#.#.#.", "X": "#...##...#.#.#...#...#.#.#...##...#",
	"Y": "#...##...#.#.#...#....#....#....#..", "Z": "#####....#...#...#...#...#....#####",
	"0": ".###.#...##..###.#.###..##...#.###.", "1": "..#...##....#....#....#....#...###.", "2": ".###.#...#....#...#...#...#...#####",
	"3": "####.....#....#.###.....#....#####.", "4": "...#...##..#.#.#..#.#####...#....#.", "5": "######....####.....#....##...#.###.",
	"6": "..##..#...#....####.#...##...#.###.", "7": "#####....#...#...#...#....#....#...", "8": ".###.#...##...#.###.#...##...#.###.",
	"9": ".###.#...##...#.####....#...#..##..", "-": "...............###...............", ".": ".........................##...##..",
	":": ".....##...##..........##...##.....", "/": "....#....#...#...#...#...#....#....", "%": "##..###..#...#...#...#...#..###..##",
	"(": "...#...#...#....#....#.....#.....#.", ")": ".#.....#.....#....#....#...#...#...", "'": "..#....#...#......................",
	"?": ".###.#...#....#...#...#.........#..", "!": "..#....#....#....#....#.........#..", ",": "....................##....#...#....",
	"<": "...#...#...#...#.....#.....#.....#.", ">": ".#.....#.....#.....#...#...#...#...", "+": ".......#....#..#####..#....#.......",
}


static func _builtin_cells() -> Array:
	var cells := []
	for k in 0x7F - FIRST:
		var g := PackedByteArray()
		g.resize(CELL_W * CELL_H)
		var ch := String.chr(FIRST + k).to_upper()
		if _B.has(ch):
			var s: String = _B[ch]
			for y in 7:
				for x in 5:
					if s[y * 5 + x] == "#":
						# 5x7 stretched to the ROM font's 10-row capitals (rows 0,1,3,4,6,7,9 doubled)
						for yy in [[0], [1, 2], [3], [4, 5], [6, 7], [8], [9]][y]:
							g[(CAP_TOP + yy) * CELL_W + 2 + x] = 1
		cells.append(g)
	return cells
