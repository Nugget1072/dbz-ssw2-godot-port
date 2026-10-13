class_name QoLInputDisplay
extends Control
## WEIRD STUFF 3 "INPUT DISPLAY" (part 25): player 1's buttons on the battle screen, like a fighting game's training
## mode. A dark strip at the bottom centre of the top screen, between the two ki gauges (x 67..188, y 171..189):
## left the D-pad (lit arms = the direction held, 8 directions) and the buttons L Y X / R B A (lit = held), right the
## last input changes, newest first, each with the frames it was held (neutral = a dot).
## Source: the game's own pad word (u16 held at 0x020DD4E0, written by FUN_0200124C from KEYINPUT + the X/Y bits;
## same bit layout as the fighter's +0x26C / +0x270 copies: 0x001 A, 0x002 B, 0x010 right, 0x020 left, 0x040 up,
## 0x080 down, 0x100 R, 0x200 L, 0x400 X, 0x800 Y). It already has the CONTROLS remapping applied; MIRROR MODE's
## LEFT / RIGHT swap is undone for the display, so the arrows point the way the player pressed and the fighter
## moves on the (flipped) screen. The fighter's own copy is not used: the game clears it while the fight is frozen
## and drops DOWN from it in some states (FUN_020273AC), so presses would go missing from the display.
## Shown while DSDisplay.battle_on_screen() (every mode, Practice included) with engine A on the top screen; frozen
## (not recorded) while the battle is paused. Drawn in the 256x384 screen_root like the FPS counter: never mirrored,
## bevelled or shaken; GAME BOY / CRT TV recolour it like the rest of the picture. Debug: `inpdbg` prints every change
## (pad word, fighter +0x26C / +0x270).

const PAD_HELD := 0x000DD4E0          ## main RAM offset of the pad's held word (0x020DD4E0)
const BATTLE_STATE := 0x000DD4C5      ## u8 battle state (9 = paused)
const TEAMS := 0x000DE3D0             ## u32 -> team blocks (debug only: the active fighter's input copy)
const MASK := 0xFF3                   ## A B (no Select / Start) directions R L X Y
const BOX := Rect2(67, 171, 122, 19)
const HIST_X := 115                   ## history area x 115..186
const HIST_END := 187
const MAX_HIST := 8

const ORANGE := Color8(255, 166, 0)   ## the game's HUD orange / white (QoLFpsCounter, menu)
const WHITE := Color8(255, 247, 239)
const OFF_FILL := Color8(96, 96, 108)    ## unlit: one GAME BOY shade above the black outlines
const OFF_TEXT := Color8(170, 170, 182)
const BACK := Color(0, 0, 0, 0.62)

## 3x5 letters / digits and 7x7 arrows (white on transparent, drawn tinted from one atlas)
const GLYPHS := {
	"A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
	"X": ["#.#", "#.#", ".#.", "#.#", "#.#"], "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
	"L": ["#..", "#..", "#..", "#..", "###"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
	"0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["##.", "..#", ".#.", "#..", "###"], "3": ["##.", "..#", ".#.", "..#", "##."],
	"4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
	"6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
	"8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "##."],
	".": ["...", "...", ".#.", "...", "..."],
}
const ARROW_R := ["...#...", "...##..", "######.", "#######", "######.", "...##..", "...#..."]
const ARROW_UR := ["..#####", "....###", "...####", "..###.#", ".###...", "###....", ".#....."]
## buttons in the 2 x 3 grid: [bit, letter]
const BUTTONS := [[0x200, "L"], [0x800, "Y"], [0x400, "X"], [0x100, "R"], [0x002, "B"], [0x001, "A"]]

var settings: QoLSettings
var display: DSDisplay
var held_override := -1               ## part 30: a LAN guest shows its own (P2) input record instead of the pad word
var _atlas: ImageTexture
var _gx := {}                         ## glyph -> Rect2 in the atlas
var _held := 0
var _hist: Array = []                 ## [[state, frames]], newest first
var _dbg: bool = Game.args.has("inpdbg")
var _dbg_last := -1


func _init() -> void:
	position = Vector2.ZERO
	size = Vector2(256, 192)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 95
	visible = false
	_build_atlas()


## after every emulated frame (QoLController.after_step). Off: one test, nothing else.
func frame(core) -> void:
	if not settings.input_display:
		if visible:
			visible = false
			_hist.clear()
		return
	var mem: PackedByteArray = core.M
	var on: bool = display.battle_on_screen() and (core.IO.decode_u16(0x304) & 0x8000) != 0
	if not on:
		if visible:
			visible = false
			_hist.clear()
		return
	var held: int = (mem.decode_u16(PAD_HELD) if held_override < 0 else held_override) & MASK
	if display.mirror_active():   # MIRROR MODE swapped LEFT / RIGHT for the game: show what was pressed
		held = (held & ~0x30) | ((held & 0x10) << 1) | ((held & 0x20) >> 1)
	if _dbg:
		_debug(core, held)
	if mem.decode_u8(BATTLE_STATE) != 9:   # paused: the history stays as it was
		if _hist.is_empty() or _hist[0][0] != held:
			_hist.push_front([held, 1])
			if _hist.size() > MAX_HIST:
				_hist.pop_back()
		elif _hist[0][1] < 99:
			_hist[0][1] += 1
	_held = held
	visible = true
	queue_redraw()


func _debug(core, held: int) -> void:
	var mem: PackedByteArray = core.M
	var teams: int = mem.decode_u32(TEAMS) - 0x02000000
	var fp := 0
	var fh := 0
	if teams > 0 and teams < 0x3F0000:
		var f := teams + mem.decode_u8(teams + 0x8C8) * 0x2D8
		fp = mem.decode_u16(f + 0x26C)
		fh = mem.decode_u16(f + 0x270)
	var k := held | (fh << 16)
	if k != _dbg_last:
		_dbg_last = k
		var tree := Engine.get_main_loop() as SceneTree
		print("INPD f%d pad %03x shown %03x fighter pressed %03x held %03x state %d" % [tree.current_scene.get("frames"),
			mem.decode_u16(PAD_HELD), held, fp, fh, mem.decode_u8(BATTLE_STATE)])


# ------------------------------------------------------------------------------------------------ drawing
func _build_atlas() -> void:
	var img := Image.create(160, 8, false, Image.FORMAT_RGBA8)
	var x := 0
	for k in GLYPHS:
		_put(img, x, GLYPHS[k], k)
		x += 4
	# arrows: index = direction 0 right, 1 up-right, 2 up, ... 7 down-right (counter-clockwise)
	for d in 8:
		var src: Array = ARROW_R if d % 2 == 0 else ARROW_UR
		var rows: Array = []
		for y in 7:
			var row := ""
			for xx in 7:
				# rotate the source by 90 degrees (d / 2) times counter-clockwise: (x, y) <- source
				var sx := xx
				var sy := y
				for _r in d / 2:
					var t := sx
					sx = 6 - sy
					sy = t
				row += src[sy][sx]
			rows.append(row)
		_put(img, x, rows, "d%d" % d)
		x += 8
	_atlas = ImageTexture.create_from_image(img)


func _put(img: Image, x0: int, rows: Array, key: String) -> void:
	for y in rows.size():
		var r: String = rows[y]
		for x in r.length():
			if r[x] == "#":
				img.set_pixel(x0 + x, y, Color.WHITE)
	_gx[key] = Rect2(x0, 0, rows[0].length(), rows.size())


func _glyph(key: String, p: Vector2, c: Color) -> void:
	var r: Rect2 = _gx[key]
	draw_texture_rect_region(_atlas, Rect2(p, r.size), r, c)


## 8-way direction index of a held word (-1 = none); right 0, counter-clockwise
static func dir_index(h: int) -> int:
	var dx := (1 if h & 0x10 else 0) - (1 if h & 0x20 else 0)
	var dy := (1 if h & 0x40 else 0) - (1 if h & 0x80 else 0)
	if dx == 0 and dy == 0:
		return -1
	return [[5, 6, 7], [4, -1, 0], [3, 2, 1]][dy + 1][dx + 1]


func _draw() -> void:
	# backing with cut corners
	var b := BOX
	draw_rect(Rect2(b.position.x + 1, b.position.y, b.size.x - 2, b.size.y), BACK)
	draw_rect(Rect2(b.position.x, b.position.y + 1, 1, b.size.y - 2), BACK)
	draw_rect(Rect2(b.end.x - 1, b.position.y + 1, 1, b.size.y - 2), BACK)
	_draw_pad(Vector2(b.position.x + 3, b.position.y + 2))
	_draw_buttons(Vector2(b.position.x + 21, b.position.y + 2))
	draw_rect(Rect2(HIST_X - 3, b.position.y + 3, 1, b.size.y - 6), Color(1, 1, 1, 0.25))
	_draw_history()


## D-pad 15x15: a cross with 5-px arms; held arms orange (a diagonal lights two)
func _draw_pad(p: Vector2) -> void:
	draw_rect(Rect2(p.x + 4, p.y - 1, 7, 17), Color.BLACK)   # 1-px outline
	draw_rect(Rect2(p.x - 1, p.y + 4, 17, 7), Color.BLACK)
	draw_rect(Rect2(p.x + 5, p.y, 5, 15), OFF_FILL)
	draw_rect(Rect2(p.x, p.y + 5, 15, 5), OFF_FILL)
	var arms := {0x40: Rect2(5, 0, 5, 5), 0x80: Rect2(5, 10, 5, 5), 0x20: Rect2(0, 5, 5, 5), 0x10: Rect2(10, 5, 5, 5)}
	for bit in arms:
		if _held & bit:
			var r: Rect2 = arms[bit]
			draw_rect(Rect2(p + r.position, r.size), ORANGE)
	draw_rect(Rect2(p.x + 6, p.y + 6, 3, 3), Color8(30, 30, 36))   # the pivot


## buttons: 7x7 chips with cut corners, L Y X over R B A
func _draw_buttons(p: Vector2) -> void:
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(25, 17)), Color.BLACK)   # outlines between the chips
	for i in BUTTONS.size():
		var bit: int = BUTTONS[i][0]
		var q := p + Vector2((i % 3) * 8, (i / 3) * 8)
		var on := (_held & bit) != 0
		var fill := ORANGE if on else OFF_FILL
		draw_rect(Rect2(q.x + 1, q.y, 5, 7), fill)
		draw_rect(Rect2(q.x, q.y + 1, 7, 5), fill)
		_glyph(BUTTONS[i][1], q + Vector2(2, 1), Color.BLACK if on else OFF_TEXT)


## newest first: icons on top (arrow white, buttons orange, neutral a dot), hold frames under them
func _draw_history() -> void:
	var x := float(HIST_X)
	var y := BOX.position.y + 2
	for e in _hist:
		var h: int = e[0]
		var parts: Array = []           # [key, width, colour]
		var d := dir_index(h)
		if d >= 0:
			parts.append(["d%d" % d, 7, WHITE])
		for bit in [0x200, 0x100, 0x800, 0x400, 0x002, 0x001]:   # L R Y X B A
			if h & bit:
				parts.append([{0x200: "L", 0x100: "R", 0x800: "Y", 0x400: "X", 0x002: "B", 0x001: "A"}[bit], 3, ORANGE])
		if parts.is_empty():
			parts.append([".", 3, OFF_TEXT])
		var w := 0
		for pt in parts:
			w += pt[1] + 1
		w -= 1
		var n := str(e[1])
		var wn := n.length() * 4 - 1
		var cw := maxi(w, wn)
		if x + cw > HIST_END:
			break
		if x > HIST_X:   # a faint line between two entries
			draw_rect(Rect2(x - 3, y + 1, 1, 13), Color(1, 1, 1, 0.14))
		var px := x
		for pt in parts:
			var tall: bool = pt[1] == 7
			_glyph(pt[0], Vector2(px, y + (0 if tall else 1)), pt[2])
			px += pt[1] + 1
		for i in n.length():
			_glyph(n[i], Vector2(x + i * 4, y + 9), WHITE if e == _hist[0] else OFF_TEXT)
		x += cw + 5
