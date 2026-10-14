class_name QoLAllStarHearts
extends Node2D
# ---- ALLSTAR BATTLE (part 34)
## ALL-STAR battle (docs/ALLSTAR_DESIGN.md 1.9): three HEART buttons on the lower screen, under the game's "Team Arts"
## text (free strip x 8-122, y 175-191 of the battle panel). Each heart is a separate button with a lit sprite (the
## Touch! plate's lit colours: P1 diamond red 0x001F / 0x10DF / 0x0014, rim 0x033F) and a used sprite (the plate's dim
## colours 0x0010 / 0x0016 / 0x000A, rim 0x01B2), like the Touch! button. A tap (mouse / gamepad cursor) on a lit heart,
## or SELECT (no battle action in the game: uses the first lit heart), asks QoLGame to use it
## (QoLAllStar.heart_req, written here on the main thread); QoLGame (`# ---- ALLSTAR BATTLE`) revives every KO'd
## player-1 fighter with the game's own revive (FUN_020298D4), heals everyone to full (FUN_02029428) and marks the
## heart used (QoLAllStar.hearts[i] = false) -- or drops the request when nobody is hurt. A touch that starts on a
## heart is kept from the game (the game's Team Arts touch rect 8,144-248,184 covers the hearts' top rows).
## Drawn while an All-Star battle is on screen (also paused: then taps / SELECT go to the game); follows the lower
## engine's MASTER_BRIGHT fades (as QoLMpPanel).

const H := 192
const X0 := [37, 61, 85]                     ## left edge of each heart (17 px wide: centres 45 / 69 / 93)
const Y0 := 176                              ## top edge (15 px high)
const W := 17
const HH := 15
const HIT := Rect2i(-3, -2, 23, 17)          ## tap area around each heart (relative to its corner)
const SCENE := 0x020DD4C4
## the heart's 13 x 11 inside ('#'), outlined in black (1 px) and rimmed (1 px) in the plate colour
const SHAPE := [
	"..###...###..",
	".#####.#####.",
	"#############",
	"#############",
	"#############",
	".###########.",
	"..#########..",
	"...#######...",
	"....#####....",
	".....###.....",
	"......#......",
]
## [fill, highlight, shadow, rim] per look: lit / used (DS BGR555, as the Touch! plate / P1 diamond)
const LOOK := [[0x001F, 0x10DF, 0x0014, 0x033F], [0x0010, 0x0016, 0x000A, 0x01B2]]

var qol                                      ## QoLController
var allstar: QoLAllStar
var shown := false
var _tex := [null, null]                     ## lit / used heart textures
var _fade := 0.0
var _key := ""


func _init() -> void:
	z_index = 85
	visible = false


func setup(q) -> void:
	qol = q
	allstar = q.allstar
	for k in 2:
		_tex[k] = ImageTexture.create_from_image(_heart(k))


static func _c(v: int) -> Color:
	return Color8(((v & 31) * 255) / 31, (((v >> 5) & 31) * 255) / 31, (((v >> 10) & 31) * 255) / 31)


## the 17 x 15 sprite: rim, black outline, fill with a highlight (upper left of each lobe) and a shadow (lower right)
static func _heart(k: int) -> Image:
	var lk: Array = LOOK[k]
	var img := Image.create(W, HH, false, Image.FORMAT_RGBA8)
	var inside := func(x: int, y: int) -> bool:
		return y >= 0 and y < SHAPE.size() and x >= 0 and x < 13 and SHAPE[y][x] == "#"
	for y in HH:
		for x in W:
			var ix := x - 2
			var iy := y - 2
			if inside.call(ix, iy):
				var c: int = lk[0]
				if (iy <= 2 and (ix == 1 or ix == 2 or ix == 7 or ix == 8) and iy >= 1) or (iy == 2 and ix == 3):
					c = lk[1]                       # glint on both lobes
				elif not inside.call(ix + 1, iy + 1) or not inside.call(ix, iy + 1):
					c = lk[2]                       # lower-right edge
				img.set_pixel(x, y, _c(c))
				continue
			var near1 := false
			var near2 := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if inside.call(ix + dx, iy + dy):
						if absi(dx) <= 1 and absi(dy) <= 1:
							near1 = true
						near2 = true
			if near1:
				img.set_pixel(x, y, Color.BLACK)
			elif near2:
				img.set_pixel(x, y, _c(lk[3]))
	return img


## after every game frame (QoLController.after_step, game thread parked)
func frame(core) -> void:
	var on: bool = allstar != null and allstar.active and allstar.stage == QoLAllStar.BATTLE and core.r8(SCENE) == 0 \
		and allstar.mode != QoLAllStar.TOURNAMENT and qol.game.display.battle_on_screen()   # (part 43: no hearts there)
	if on:
		var key := str(allstar.hearts)
		var mb: int = core.IO.decode_u16(0x106C if (core.IO.decode_u16(0x304) & 0x8000) != 0 else 0x6C)
		var f := minf((mb & 31) / 16.0, 1.0)
		var mode := (mb >> 14) & 3
		var fade := f if mode == 1 else (-f if mode == 2 else 0.0)
		if key != _key or fade != _fade:
			_key = key
			_fade = fade
			queue_redraw()
	if on != shown:
		shown = on
		visible = on
		queue_redraw()


## hearts shown: part 43 BOSS RUSH has one
func _count() -> int:
	return 1 if allstar != null and allstar.mode == QoLAllStar.BOSSRUSH else 3


## main thread, before each game frame (QoLController.filter_input): [swallow touch, swallow keys mask]
func filter(newly: int, touch: Vector2i, new_touch: bool) -> Array:
	if not shown or allstar == null or qol.machine.core.r8(SCENE + 1) == 9:   # (paused: the game's input)
		return [false, 0]
	var take_touch := false
	if new_touch and touch.x >= 0:
		for i in _count():
			var r := Rect2i(HIT.position + Vector2i(X0[i], Y0), HIT.size)   # (lower-screen coordinates, as the touch)
			if r.has_point(touch):
				take_touch = true
				if allstar.hearts[i] and allstar.heart_req < 0:
					allstar.heart_req = i
					if allstar.dbg:
						print("AS f%d heart %d tapped" % [qol.game.frames, i])
	var keys := 0
	if (newly & 4) != 0 and not qol.settings.cheat("time_skip"):   # SELECT: the first lit heart (part 41: TIME SKIP's while that cheat is on; hearts by tap)
		keys = 4
		if allstar.heart_req < 0:
			for i in 3:
				if allstar.hearts[i]:
					allstar.heart_req = i
					if allstar.dbg:
						print("AS f%d heart %d by SELECT" % [qol.game.frames, i])
					break
	return [take_touch, keys]


func _draw() -> void:
	if not shown or _tex[0] == null:
		return
	var m := Color(1, 1, 1)
	if _fade < 0.0:
		m = Color(1 + _fade, 1 + _fade, 1 + _fade)
	for i in _count():
		draw_texture(_tex[0 if allstar.hearts[i] else 1], Vector2(X0[i], 192 + Y0), m)
		if _fade > 0.0:
			draw_rect(Rect2(X0[i], 192 + Y0, W, HH), Color(1, 1, 1, _fade))
