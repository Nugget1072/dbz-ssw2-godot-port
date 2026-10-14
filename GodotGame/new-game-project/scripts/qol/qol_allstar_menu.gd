class_name QoLAllStarMenu
extends RefCounted
# ---- ALLSTAR MENU (part 34)
## NEW GAMEMODES labels, written into the game's own textures (like QoLButton), so the game's cursor frames, fades and
## 3D drawing stay in charge (docs/ALLSTAR_DESIGN.md 1.1 / 1.2; DATA_NOTES "part 34 findings (All-Star menus)"):
## - Mode Select tile 5 (FREE BATTLE; 128x64 4-bit texture at texture slot 0 + 0x5000, palette 0): its label (rows
##   32-41, white capitals on the black plate, right-aligned) becomes GAMEMODE. Letters A / M / E / O / D are copied at
##   run time from the other tiles' labels in texture memory (MAXIMUM tile 3, STORY MODE tile 1); the G (no label has
##   one) is the port's own, drawn in the same style.
## - Scene 0xB (MAXIMUM's COURSE SELECT) as the Gamemode menu: the bar textures (256x64 4-bit, +0x2000 Novice, +0x4000
##   Hard, +0x6000 Mania; palette 1): +0x2000 = a copy of the Hard bar labelled ALL-STAR, +0x4000 = the Hard bar
##   labelled EMPTY (QoLGame f_0205495c draws it for slots 2-3), +0x6000 = the Hard bar labelled ENDLESS (part 38;
##   slot 1). Letters: the bars' heavy 15-row font; M and R are copied from the Mania bar's "Mania Rank" (read before
##   that texture is relabelled), the others are the port's own in the same style (stems 4 px).
##   Part 43: +0x4000 is labelled BOSS RUSH (slot 2) and a 4th bar, TOURNAMENT (slot 3), is written to the free texture
##   memory at +BAR_TOUR (QoLGame f_0205495c points the second bar object's texture handle there for its slot-3 draw).
##   A label wider than the field is set with the game's own 1-column letter gap.
## Runs on the main thread after each game frame (QoLController `# ---- ALLSTAR`), like QoLButton: the texture is
## checked whenever its VRAM bank was written or remapped, and rewritten when it differs.

const MS_VBLANK_CB := 0x020DE374     ## scene VBlank slot: 0x020738E0 while Mode Select runs
const MS_VBLANK_FN := 0x020738E0
const TILE := 0x5000                 ## Mode Select tile 5 (FREE BATTLE)
const TROW := 64                     ## bytes per tile texture row (128 texels)
const LROW0 := 32                    ## label rows 32..41
const LROWS := 10
const LRIGHT := 74                   ## last column of the label text (STORY MODE's E ends there)
const BAR_ALL := 0x2000
const BAR_EMPTY := 0x4000
const BAR_MANIA := 0x6000
const BAR_TOUR := 0x8000             ## part 43: the 4th bar (TOURNAMENT), free texture memory after the Mania bar
const BROW := 128                   ## bytes per bar texture row (256 texels)
const BTOP := 27                     ## bar text rows 27..41 (capitals 15 rows)
const BH := 15

## Mode Select label glyphs: [tile, first column, width] in the game's own labels (texture memory)
const TILE_SRC := {"A": [3, 37, 5], "M": [3, 29, 7], "E": [1, 71, 4], "O": [1, 57, 6], "D": [1, 64, 6]}
## the port's own G for the tile labels (2 = plate black, 3 = white, 5 / 9 / e = the labels' edge shades)
const TILE_G := ["5e33e5", "e3ee3e", "332233", "332222", "332333", "332333", "332233", "332233", "e3ee33", "5e33e3"]
const TILE_TEXT := "GAMEMODE"

## the port's own bar capitals (15 rows; 5 = ink, 3 / c = the font's edge shades, . = bar yellow 1)
const BAR_GLYPHS := {
	"A": [".3555553.", "c5555555c", "555555555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "555555555",
		"555555555", "555555555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555"],
	"L": ["5555....", "5555....", "5555....", "5555....", "5555....", "5555....", "5555....", "5555....", "5555....",
		"5555....", "5555....", "5555....", "55555555", "55555555", "55555555"],
	"-": ["......", "......", "......", "......", "......", "......", "......", "555555", "555555", "555555", "......",
		"......", "......", "......", "......"],
	"S": [".3555553.", "c5555555c", "555555555", "5555.5555", "5555.....", "5555.....", "55555553.", "c5555555c",
		".35555555", ".....5555", ".....5555", "5555.5555", "555555555", "c5555555c", ".3555553."],
	"T": ["55555555", "55555555", "55555555", "..5555..", "..5555..", "..5555..", "..5555..", "..5555..", "..5555..",
		"..5555..", "..5555..", "..5555..", "..5555..", "..5555..", "..5555.."],
	"E": ["55555555", "55555555", "55555555", "5555....", "5555....", "5555....", "5555555.", "5555555.", "5555555.",
		"5555....", "5555....", "5555....", "55555555", "55555555", "55555555"],
	"P": ["55555553.", "55555555c", "555555555", "5555.5555", "5555.5555", "5555.5555", "555555555", "55555555c",
		"55555553.", "5555.....", "5555.....", "5555.....", "5555.....", "5555.....", "5555....."],
	"Y": ["5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "555555555", "c5555555c", ".3555553.",
		"..55555..", "..55555..", "..55555..", "..55555..", "..55555..", "..55555..", "..55555.."],
	## part 38 (ENDLESS)
	"N": ["5555...5555", "55553..5555", "555555.5555", "555555.5555", "555555c5555", "5555c555555", "5555.555555",
		"5555.555555", "5555.555555", "5555.c55555", "5555..55555", "5555..55555", "5555..35555", "5555...5555",
		"5555...5555"],
	"D": ["55555553.", "55555555c", "555555555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555",
		"5555.5555", "5555.5555", "5555.5555", "5555.5555", "555555555", "55555555c", "55555553."],
	## fallbacks when the Mania bar cannot be read
	"M": ["5555....5555", "55553..35555", "55555..55555", "555553355555", "555555555555", "555555555555",
		"555555555555", "555555555555", "555535535555", "5555.55.5555", "5555....5555", "5555....5555",
		"5555....5555", "5555....5555", "5555....5555"],
	"R": ["55555553.", "55555555c", "555555555", "5555.5555", "5555.5555", "5555.555c", "55555553.", "55555555.",
		"555555553", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555"],
	## part 43 (BOSS RUSH, TOURNAMENT)
	"B": ["55555553.", "55555555c", "555555555", "5555.5555", "5555.5555", "5555.555c", "55555553.", "55555555.",
		"555555553", "5555.5555", "5555.5555", "5555.5555", "555555555", "55555555c", "55555553."],
	"O": [".3555553.", "c5555555c", "555555555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555",
		"5555.5555", "5555.5555", "5555.5555", "5555.5555", "555555555", "c5555555c", ".3555553."],
	"U": ["5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555",
		"5555.5555", "5555.5555", "5555.5555", "5555.5555", "555555555", "c5555555c", ".3555553."],
	"H": ["5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "555555555", "555555555",
		"555555555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555", "5555.5555"],
	" ": [".....", ".....", ".....", ".....", ".....", ".....", ".....", ".....", ".....", ".....", ".....", ".....",
		".....", ".....", "....."],
}
const BAR_GAP := 2                   ## columns between capitals (1, the game's own gap, when a label would not fit)

var dbg := false
var _tile_seen: Array = [-1, -1, -1]
var _tile_out := PackedByteArray()   ## label rows 32..41 of tile 5 as they should be (40 bytes per row: columns 0..79)
var _bar_seen: Array = [-1, -1, -1]
var _bar_all := PackedByteArray()    ## the two bar textures as they should be (0x2000 bytes each)
var _bar_empty := PackedByteArray()
var _bar_endless := PackedByteArray()  ## part 38: the Mania bar's texture (+0x6000) = the Hard bar labelled ENDLESS
var _bar_tour := PackedByteArray()   ## part 43: the Hard bar labelled TOURNAMENT (at +BAR_TOUR); _bar_empty = BOSS RUSH
var tour_free := -1                  ## part 43: +BAR_TOUR was empty (1) / in use (0) before the first write (-1 unknown)
## part 34 phase 4: the header plate (texture +0x1000, 256x32 4-bit, palette 0 = black 3 .. white 0xF greys): its
## "COURSE SELECT" re-lettered (QoLAllStarRecords.retitle, the same heavy italic capitals as the records page title)
const HDR := 0x1000
const HDR_TEXT := ["GAMEMODE SELECT", "MODE SELECT"]   ## the first that fits the plate
const HDR_LEVELS := [3, 5, 8, 0xB, 0xF]
var _hdr := PackedByteArray()        ## the header texture as it should be (0x1000 bytes)


func _init() -> void:
	dbg = Game.args.has("asdbg")


## after every game frame: the GAMEMODE label while Mode Select runs (`on` = NEW GAMEMODES)
func tile_frame(core, on: bool) -> void:
	if not on or core.r32(MS_VBLANK_CB) != MS_VBLANK_FN:
		return
	var hw: DSHardware = core.hw
	var sl: Array = hw.tex_slots[0]
	if sl.size() != 1:
		return
	var b: int = sl[0][0]
	var o: int = sl[0][1]
	if b == _tile_seen[0] and hw.bank_gen[b] == _tile_seen[1] and hw.map_gen == _tile_seen[2]:
		return
	var bank: PackedByteArray = hw.bank[b]
	var want := _tile_label(bank, o)
	if want.is_empty():
		return                           # the other tiles' labels are not there (not loaded yet)
	var t := o + TILE + LROW0 * TROW
	var same := true
	for y in LROWS:
		if bank.slice(t + y * TROW, t + y * TROW + 40) != want.slice(y * 40, y * 40 + 40):
			same = false
			break
	if not same:
		for y in LROWS:
			DSHardware.blit(bank, t + y * TROW, want, y * 40, 40)
		hw.bank_gen[b] += 1
		hw.dirty_vram = true
		if dbg:
			print("AS tile 5 labelled GAMEMODE (texture bank %d + %x)" % [b, o + TILE])
	_tile_seen = [b, hw.bank_gen[b], hw.map_gen]


static func _nib(bank: PackedByteArray, base: int, row: int, x: int, y: int) -> int:
	return (bank[base + y * row + (x >> 1)] >> (4 * (x & 1))) & 15


static func _set_nib(buf: PackedByteArray, base: int, row: int, x: int, y: int, v: int) -> void:
	var i := base + y * row + (x >> 1)
	var s := 4 * (x & 1)
	buf[i] = (buf[i] & ~(15 << s) & 0xFF) | (v << s)


## tile 5's label rows (columns 0..79) with GAMEMODE, built from the current tile 5 and the source letters
func _tile_label(bank: PackedByteArray, o: int) -> PackedByteArray:
	var glyphs := {}
	for ch in TILE_SRC:
		var src: Array = TILE_SRC[ch]
		var rows: Array = []
		var ink := false
		for y in LROWS:
			var r := ""
			for x in src[2]:
				var v := _nib(bank, o + src[0] * 0x1000 + LROW0 * TROW, TROW, src[1] + x, y)
				ink = ink or v == 3
				r += "%x" % v
			rows.append(r)
		if not ink:
			return PackedByteArray()
		glyphs[ch] = rows
	glyphs["G"] = TILE_G
	var out := PackedByteArray()
	out.resize(LROWS * 40)
	for y in LROWS:                      # the tile's own plate (edges included) first
		for x in 40:
			out[y * 40 + x] = bank[o + TILE + (LROW0 + y) * TROW + x]
	for y in LROWS:
		for x in range(4, 77):
			_set_nib(out, 0, 40, x, y, 2)
	var w := -1
	for ch in TILE_TEXT:
		w += (glyphs[ch][0] as String).length() + 1
	var cx := LRIGHT - w + 1
	for ch in TILE_TEXT:
		var g: Array = glyphs[ch]
		for y in LROWS:
			var line: String = g[y]
			for x in line.length():
				_set_nib(out, 0, 40, cx + x, y, line.substr(x, 1).hex_to_int())
		cx += (g[0] as String).length() + 1
	return out


## after every game frame: the Gamemode menu's bar labels (`on` = the Gamemode menu runs: scene 0xB, QoLAllStar.MENU)
func bars_frame(core, on: bool) -> void:
	if not on:
		return
	var hw: DSHardware = core.hw
	var sl: Array = hw.tex_slots[0]
	if sl.size() != 1:
		return
	var b: int = sl[0][0]
	var o: int = sl[0][1]
	if b == _bar_seen[0] and hw.bank_gen[b] == _bar_seen[1] and hw.map_gen == _bar_seen[2]:
		return
	var bank: PackedByteArray = hw.bank[b]
	if _bar_empty.is_empty():
		var hard := bank.slice(o + BAR_EMPTY, o + BAR_EMPTY + 0x2000)
		if not _bar_ok(hard):
			return                       # not loaded (yet)
		var font := BAR_GLYPHS.duplicate()
		_mania_letters(bank.slice(o + BAR_MANIA, o + BAR_MANIA + 0x2000), font)   # (before the Mania bar is relabelled)
		_bar_all = _bar_label(hard, "ALL-STAR", font)
		_bar_empty = _bar_label(hard, "BOSS RUSH", font)   # part 43 (was EMPTY)
		_bar_endless = _bar_label(hard, "ENDLESS", font)
		_bar_tour = _bar_label(hard, "TOURNAMENT", font)   # part 43
	if tour_free < 0:                    # part 43: the 4th bar's memory: nothing of the scene's there (checked once)
		var z := bank.slice(o + BAR_TOUR, o + BAR_TOUR + 0x2000)
		tour_free = 1 if z.count(0) == z.size() or z == _bar_tour else 0
		if dbg:
			print("AS Gamemode menu: texture +%x %s" % [BAR_TOUR, "free" if tour_free == 1 else "IN USE (no 4th bar)"])
	if _hdr.is_empty():                  # part 34 phase 4: header relabel (built once from the game's own plate)
		var h := bank.slice(o + HDR, o + HDR + 0x1000)
		if _hdr_ok(h):
			for txt in HDR_TEXT:
				var t := h.duplicate()
				if QoLAllStarRecords.retitle(t, 256, 8, 3, HDR_LEVELS, txt):
					_hdr = t
					if dbg:
						print("AS Gamemode menu header: %s" % txt)
					break
	var wrote := false
	for k in (4 if tour_free == 1 else 3):
		var at: int = o + [BAR_ALL, BAR_EMPTY, BAR_MANIA, BAR_TOUR][k]
		var want: PackedByteArray = [_bar_all, _bar_empty, _bar_endless, _bar_tour][k]
		if bank.slice(at, at + 0x2000) != want:
			DSHardware.blit(bank, at, want, 0, 0x2000)
			wrote = true
	if not _hdr.is_empty() and bank.slice(o + HDR, o + HDR + 0x1000) != _hdr:   # part 34 phase 4: header
		DSHardware.blit(bank, o + HDR, _hdr, 0, 0x1000)
		wrote = true
	if wrote:
		hw.bank_gen[b] += 1
		hw.dirty_vram = true
		if dbg:
			print("AS Gamemode menu bars labelled (texture bank %d + %x / %x / %x)" % [b, o + BAR_ALL, o + BAR_EMPTY, o + BAR_MANIA])
	_bar_seen = [b, hw.bank_gen[b], hw.map_gen]


## part 34 phase 4: the COURSE SELECT header plate as the game loads it: white square block (rows 8-24) and the white
## underline (row 24) on the black plate
static func _hdr_ok(t: PackedByteArray) -> bool:
	var white := 0
	for x in range(30, 160):
		if _nib(t, 0, 128, x, 24) == 0xF:
			white += 1
	var block := 0
	for x in range(16, 34):
		if _nib(t, 0, 128, x, 15) == 0xF:
			block += 1
	return white > 100 and block >= 8


## a bar texture as the game loads it: yellow (1) top row of the label field, black (5) ink in the text rows
static func _bar_ok(t: PackedByteArray) -> bool:
	for x in range(80, 160, 8):
		if _nib(t, 0, BROW, x, 25) != 1:
			return false
	var ink := 0
	for y in range(BTOP, BTOP + BH):
		for x in range(60, 160):
			if _nib(t, 0, BROW, x, y) == 5:
				ink += 1
	return ink > 100


## first column of a bar's text (after the black triangle at the left of its label field) and the field's last column
static func _bar_field(t: PackedByteArray) -> Vector2i:
	var x := 0
	while x < 200 and _nib(t, 0, BROW, x, BTOP + BH - 1) != 1:   # border
		x += 1
	while x < 200 and _nib(t, 0, BROW, x, BTOP + BH - 1) == 1:   # yellow before the triangle
		x += 1
	while x < 200 and _nib(t, 0, BROW, x, BTOP + BH - 1) != 1:   # triangle
		x += 1
	var e := 200
	while e > x and _nib(t, 0, BROW, e, BTOP + 3) != 1:          # the field's yellow ends before the plate
		e -= 1
	return Vector2i(x + 2, e)


## M and R of the Mania bar ("Mania Rank": letters 0 and 5) in the bars' own font, when they read as expected
static func _mania_letters(t: PackedByteArray, font: Dictionary) -> void:
	if not _bar_ok(t):
		return
	var f := _bar_field(t)
	var segs: Array = []
	var start := -1
	for x in range(f.x - 1, f.y + 1):
		var ink := false
		for y in range(BTOP - 1, BTOP + BH):
			var v := _nib(t, 0, BROW, x, y)
			if v != 1:
				ink = true
				break
		if ink and start < 0:
			start = x
		elif not ink and start >= 0:
			segs.append(Vector2i(start, x - 1))
			start = -1
	if segs.size() < 9 or segs[0].y - segs[0].x + 1 != 12 or segs[5].y - segs[5].x + 1 != 9:
		return
	for pair in [["M", segs[0]], ["R", segs[5]]]:
		var s: Vector2i = pair[1]
		var rows: Array = []
		for y in range(BTOP, BTOP + BH):
			var r := ""
			for x in range(s.x, s.y + 1):
				var v := _nib(t, 0, BROW, x, y)
				r += "." if v == 1 else "%x" % v
			rows.append(r)
		font[pair[0]] = rows


## the Hard bar with `text` instead of "Hard Rank"
static func _bar_label(src: PackedByteArray, text: String, font: Dictionary) -> PackedByteArray:
	var t := src.duplicate()
	var f := _bar_field(src)
	for y in range(BTOP - 1, BTOP + BH):             # the old label (its tall letters start one row higher)
		for x in range(f.x - 1, f.y + 1):
			if _nib(t, 0, BROW, x, y) != 1:
				_set_nib(t, 0, BROW, x, y, 1)
	var cx := f.x                                    # 2 yellow columns after the triangle, as the game's labels
	var gap := BAR_GAP
	var w := -gap
	for ch in text:
		w += (font[ch][0] as String).length() + gap
	if cx + w > f.y + 1:                             # part 43: too wide -> the game's own 1-column gap
		gap = 1
	for ch in text:
		var g: Array = font[ch]
		for y in BH:
			var line: String = g[y]
			for x in line.length():
				var c := line.substr(x, 1)
				if c != ".":
					_set_nib(t, 0, BROW, cx + x, BTOP + y, c.hex_to_int())
		cx += (g[0] as String).length() + gap
	if Game.args.has("asdbg"):
		print("AS bar label '%s': columns %d..%d (field %d..%d, gap %d)" % [text, f.x, cx - gap - 1, f.x, f.y, gap])
	return t
