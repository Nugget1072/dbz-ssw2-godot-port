class_name QoLMpPanel
extends Node2D
# ---- MULTIPLAYER (part 27)
## LOCAL MULTIPLAYER battle lower screen (docs/MULTIPLAYER_DESIGN.md 3.7, the user's mockup docs/mp_mockup.png): while
## an MP battle is on screen the port draws both teams over the whole lower screen (opaque, so the game's own
## single-player panels underneath need no hiding): per player an "A" column (active fighter in colour on top, the
## bench below, split diagonally between the two bench members), a blue-grey bar, a "B" column (support on top, the
## Touch! plate with a red (P1) / blue (P2) diamond below); a black divider between the players. Everything is read
## live from RAM every frame (QoLController.after_step → frame()); the picture is rebuilt only when what it shows
## changes. Art (nothing stored in the port): portraits SubScrNBFC/NBFS.bin member = character id (80x128, the
## game's battle panel tiles), colour palette scene/common/CharFace.bin `<abbr>_face.nbfp` for the active fighter,
## battle panel palette game/game_bg.arc #0x66 (row 0 plain, row 4 dark = KO'd / no assists left, row 5 Touch! lit,
## row 6 Touch! dim), the diamond and the "Touch !" letters cut from game/game_subbg.bin `e_pairatk` (the game's
## own Team Arts / Touch! bar), empty slots = the game's `nul1` frame art. Taps (route(), main thread, before each
## frame): a touch on P1's half (x < 128) is mapped to P1's panel coordinates and given to the DS touch screen (the
## game's own P1 path), a touch on P2's half goes to QoLMp.touch[1] / tap[1] (→ QoLGame.f_0202dce0 → MP_AI_OUT).
## Regions: bench part of member k → centre of its panel rect (rec +0x2D0..+0x2D6, = (48 + 80·slot, 76)), support box
## → the support's rect centre, Touch! plate → (128, 164) (Team Arts rect 8,144 - 248,184), active portrait → nothing.
## Part 28: two supports in a team (SAME CHARACTERS) split the support box in half, one support per half, each half
## mapped to its own support's rect (QoLGame `# ---- MP SUPPORTS` makes the game call that one); the Touch! plate is
## a new design after the game's Team Arts / Touch! button (_plate) with a pressed look while a touch is held on it.

const TEAMS := 0x020DE3D0
const SCENE := 0x020DD4C4                    ## u8 scene, u8 state at +1
const H := 192
const BAR := Color8(57, 57, 99)              ## 0x30E7, the panels' backdrop colour (palette row 0 index 0)
## per side: [A column x, A width, bar x, B column x, B width]
const COLS := [[0, 60, 60, 68, 59], [130, 59, 189, 197, 59]]
const TOP_H := 95                            ## portrait rows shown on top (row 95 is a black line)
const BOT_Y := 96
const DIAG := [62, 33]                       ## bench split line: local y at x = 0 and at x = width - 1
const LOWER_SHIFT := 34                      ## the second bench member's portrait starts this far down
const TEAM_ARTS_AT := Vector2i(128, 164)     ## a point inside the Team Arts rect (8, 144 - 248, 184)
const SUP_MIN := 26                          ## ids >= 26 are supports
const NUL := 37                              ## `nul1` frame art (empty slot)

var qol                                      ## QoLController
var mp: QoLMp
var rom := PackedByteArray()
var shown := false                           ## the panel covers the lower screen this frame
var dbg := false
var _ok := false                             ## art found in the ROM
var _nbfc := {}
var _nbfs := {}
var _face := {}
var _pal := []                               ## game_bg.arc #0x66: 16 rows of 16 Colors
var _pair := PackedByteArray()               ## e_pairatk as 256 x 192 palette indices
var _px := {}                                ## id -> PackedByteArray 80 x 128 palette indices
var _imgs := {}                              ## "id:kind" -> Image 80 x 128
var _plates := {}                            ## "side:lit" -> Image
const TOUCH_W := 45                          ## "Touch !" text width on the 59-px plate (part 28: 2 px clear of the groove)
var _masks := {}                             ## width -> [upper mask, lower mask]
var _img: Image
var _tex: ImageTexture
var _key := ""
var _side := [{}, {}]                        ## per side: live state (targets for the tap mapping)
var _fade := 0.0                             ## MASTER_BRIGHT of the lower engine: < 0 darker, > 0 whiter
var _prev_raw := [false, false]
var _press := [false, false]                 ## part 28: a touch of that player is held on its Touch! plate
const SUP_MID := 40                          ## part 28: portrait column shown in the middle of a support half


func _init() -> void:
	z_index = 80
	visible = false


func setup(q, r: PackedByteArray) -> void:
	qol = q
	mp = q.mp
	rom = r
	dbg = Game.args.has("mpdbg")
	var sub := QoLFont.nitro_file(rom, "romdata/charselect/SubScrNBFC.bin")
	var map := QoLFont.nitro_file(rom, "romdata/charselect/SubScrNBFS.bin")
	var face := QoLFont.nitro_file(rom, "romdata/scene/common/CharFace.bin")
	var bg := QoLFont.nitro_file(rom, "romdata/game/game_bg.arc")
	var pair := QoLFont.nitro_file(rom, "romdata/game/game_subbg.bin")
	if sub.x < 0 or map.x < 0 or face.x < 0 or bg.x < 0 or pair.x < 0:
		print("MP panel: art not found in the ROM")
		return
	_nbfc = _pack(sub)
	_nbfs = _pack(map)
	_face = _pack(face)
	var n := rom.decode_u32(bg.x + 8)
	var hs := rom.decode_u32(bg.x + 12)
	if n <= 0x66:
		return
	var off := rom.decode_u32(bg.x + 0x10 + 0x66 * 8)
	for row in 16:
		var cs := []
		for c in 16:
			cs.append(_col(rom.decode_u16(bg.x + hs + off + row * 32 + c * 2)))
		_pal.append(cs)
	var pk := _pack(pair)
	if not pk.has("e_pairatk.nbfc") or not pk.has("e_pairatk.nbfs"):
		return
	_pair = QoLEpicImg.bg_to_px(_member(pk, "e_pairatk.nbfc"), _member(pk, "e_pairatk.nbfs"))
	_img = Image.create(256, H, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_ok = true


# ------------------------------------------------------------------------------------------------ ROM art
## pack header (type 3 / 4): u16 count at +2, u32 data offset at +4, entries of 0x4C: name[64], unpacked size,
## packed size, offset
func _pack(f: Vector2i) -> Dictionary:
	var d := {}
	var n := rom.decode_u16(f.x + 2)
	var hs := rom.decode_u32(f.x + 4)
	for i in n:
		var e := f.x + 8 + i * 0x4C
		var nm := rom.slice(e, e + 64).get_string_from_ascii().replace("\\", "/").get_file()
		var v := [rom.decode_u32(e + 64), rom.decode_u32(e + 68), f.x + hs + rom.decode_u32(e + 72)]
		d[nm] = v
		d[i] = nm
	return d


func _member(d: Dictionary, name: String) -> PackedByteArray:
	var v: Array = d[name]
	var raw := rom.slice(v[2], v[2] + v[1])
	return raw if v[0] == v[1] else QoLEpicImg._decompress(raw, v[0])


static func _col(c: int) -> Color:
	return Color8(((c & 31) * 255) / 31, (((c >> 5) & 31) * 255) / 31, (((c >> 10) & 31) * 255) / 31)


## 80 x 128 palette indices of character `id`'s battle panel portrait (16 x 16 map, columns 0-9 used)
func _portrait_px(id: int) -> PackedByteArray:
	if _px.has(id):
		return _px[id]
	var px := PackedByteArray()
	px.resize(80 * 128)
	if _nbfc.has(id) and _nbfs.has(id):
		var ch := _member(_nbfc, _nbfc[id])
		var mp_ := _member(_nbfs, _nbfs[id])
		for ty in 16:
			for tx in 10:
				var e := mp_.decode_u16((ty * 16 + tx) * 2)
				var t := e & 0x3FF
				var hf := (e >> 10) & 1
				var vf := (e >> 11) & 1
				for y in 8:
					var Y := ty * 8 + (7 - y if vf else y)
					for x in 8:
						var o := t * 32 + y * 4 + (x >> 1)
						var v: int = (ch[o] >> ((x & 1) * 4)) & 15 if o < ch.size() else 0
						px[Y * 80 + tx * 8 + (7 - x if hf else x)] = v
	_px[id] = px
	return px


## kind: "c" colour (CharFace), "n" plain (row 0), "d" dark (row 4)
func _portrait(id: int, kind: String) -> Image:
	var k := "%d:%s" % [id, kind]
	if _imgs.has(k):
		return _imgs[k]
	var pal: Array = _pal[4 if kind == "d" else 0].duplicate()
	if kind == "c" and _nbfc.has(id):
		var nm := (_nbfc[id] as String).get_basename() + "_face.nbfp"
		if _face.has(nm):
			var p := _member(_face, nm)
			for c in mini(16, p.size() / 2):
				if c > 0:
					pal[c] = _col(p.decode_u16(c * 2))
	var px := _portrait_px(id)
	var data := PackedByteArray()
	data.resize(80 * 128 * 4)
	for i in px.size():
		var c: Color = pal[px[i]]
		data[i * 4] = c.r8
		data[i * 4 + 1] = c.g8
		data[i * 4 + 2] = c.b8
		data[i * 4 + 3] = 255
	var img := Image.create_from_data(80, 128, false, Image.FORMAT_RGBA8, data)
	_imgs[k] = img
	return img


## the Touch! plate (w x 96), part 28 design after the game's own Team Arts / Touch! button (game_subbg.bin
## `e_pairatk`, palette game_bg.arc #0x66 row 5 = Team Arts possible, row 6 = not yet): black outer line with a light
## / dark bevel, the button's inner black groove line with its steps, the chevrons of the part-27 plate behind the
## button's diamond (core in the player's colour -- red P1, blue P2 -- with a lighter upper-left and darker lower-right
## facet and a white glint, 3-px black ring, plate-colour halo, 2-px black contour as the button's nose), the game's
## "Touch !" letters (condensed, clear of the groove) and an accent bar in the player's colour. Pressed (the player
## holds a touch on it): the content moves 1 px down-right, the bevel turns over and the body takes the palette's
## darker plate shade (index 10).
enum { P_BODY, P_OUT, P_HI, P_SH, P_AA8, P_AA9, P_DIA, P_DHI, P_DSH, P_GLINT, P_CHV }
func _plate(side: int, lit: bool, pressed: bool, w: int) -> Image:
	var k := "%d:%s:%s" % [side, lit, pressed]
	if _plates.has(k):
		return _plates[k]
	var row: Array = _pal[5 if lit else 6]
	var pal := []
	pal.resize(11)
	pal[P_BODY] = row[10] if pressed else row[3]
	pal[P_OUT] = row[2]
	pal[P_HI] = _col(0x033F if lit else 0x01B2)            # (0x033F: the panels' palette row 0; 0x01B2: row 5 index 8)
	pal[P_SH] = row[8]
	pal[P_AA8] = row[8]
	pal[P_AA9] = row[9]
	pal[P_CHV] = row[8]
	pal[P_GLINT] = _col(0x7FFF if lit else 0x5EF7)
	var dia: Array = [[0x001F, 0x10DF, 0x0014], [0x0010, 0x0016, 0x000A]] if side == 0 else [[0x7C00, 0x7D86, 0x5000], [0x4000, 0x5884, 0x2800]]
	var dc: Array = dia[0 if lit else 1]
	pal[P_DIA] = _col(dc[0])
	pal[P_DHI] = _col(dc[1])
	pal[P_DSH] = _col(dc[2])
	if pressed:
		var t: Color = pal[P_HI]
		pal[P_HI] = pal[P_SH]
		pal[P_SH] = t
	var h := 96
	_pb = PackedByteArray()
	_pb.resize(w * h)
	_pb.fill(P_BODY)
	_pw = w
	_ph = h
	_po = 1 if pressed else 0
	var line := _line
	var cx := w / 2
	var cy := 27                                       # diamond centre
	for j in 3:                                        # three chevrons pointing at the diamond (as the mockup)
		var d := j * 3
		for m in 2:
			var X := func(x: int) -> int: return x if m == 0 else w - 1 - x
			line.call(X.call(5), 8 + d, X.call(21 - d), cy, P_CHV)
			line.call(X.call(21 - d), cy, X.call(5), 46 - d, P_CHV)
	# the groove (e_pairatk's inner line, with its steps), 4 px inside the outer line
	var r := w - 5
	var b := h - 5
	var gp := [Vector2i(4, 4), Vector2i(r - 18, 4), Vector2i(r - 15, 7), Vector2i(r, 7), Vector2i(r, b), Vector2i(22, b),
		Vector2i(19, b - 3), Vector2i(4, b - 3), Vector2i(4, 4)]
	for i in gp.size() - 1:
		line.call(gp[i].x, gp[i].y, gp[i + 1].x, gp[i + 1].y, P_OUT)
	# the diamond: core with facets and a glint, black ring, halo, black contour
	for y in range(cy - 19, cy + 20):
		for x in range(cx - 19, cx + 20):
			var dx := x - cx
			var dy := y - cy
			var dd := absi(dx) + absi(dy)
			if dd <= 11:
				var v := P_DIA
				if dx + dy <= -5:
					v = P_DHI
				elif dx + dy >= 6:
					v = P_DSH
				if dx < 0 and dy < 0 and dd >= 7 and dd <= 8 and absi(dx - dy) <= 4:
					v = P_GLINT
				_put(x, y, v)
			elif dd <= 14:
				_put(x, y, P_OUT)
			elif dd <= 16:
				_put(x, y, P_BODY)
			elif dd <= 18:
				_put(x, y, P_OUT)
	# "Touch !" letters (e_pairatk x 164..226, y 19..39), one column list per glyph run. The game's bar is wider than
	# this plate: the glyphs are condensed to TOUCH_W px by dropping columns whose ink equals their left neighbour's
	# (a 4-px stem becomes 3: the letters keep their shape), "!" keeps a 3-px space; 2 px clear of the groove
	var runs := []                                     # per glyph run: Array of 21-value columns
	var prev_ink := false
	for x in range(164, 227):
		var col := PackedByteArray()
		var ink := false
		for y in range(19, 40):
			var v := _pair[y * 256 + x]
			col.append(v if v in [2, 8, 9] else 0)
			ink = ink or v in [2, 8, 9]
		if ink:
			if not prev_ink:
				runs.append([])
			runs[-1].append(col)
		prev_ink = ink
	var gaps := []
	var ink_w := 0
	for i in runs.size():
		gaps.append(0 if i == 0 else (3 if i == runs.size() - 1 else 1))
		ink_w += runs[i].size()
	var room: int = TOUCH_W
	for g in gaps:
		room -= g
	if ink_w > room:
		for i in runs.size():
			var rr: Array = runs[i]
			var nk: int = rr.size() - maxi(1, roundi(rr.size() * float(room) / ink_w))
			var dups := []                             # columns whose ink equals their left neighbour's
			for j in range(1, rr.size()):
				if _ink(rr[j]) == _ink(rr[j - 1]):
					dups.append(j)
			var drop := {}
			if nk > 0:
				for n in mini(nk, dups.size()):
					drop[dups[int((n + 0.5) * dups.size() / nk)]] = true
			var r2 := []
			for j in rr.size():
				if not drop.has(j):
					r2.append(rr[j])
			runs[i] = r2
	var tw := 0
	for i in runs.size():
		tw += gaps[i] + runs[i].size()
	var tx := (w - tw) / 2
	var ty := 60
	for i in runs.size():
		tx += gaps[i]
		for col: PackedByteArray in runs[i]:
			for y in 21:
				if col[y] != 0:
					_put(tx, ty + y, P_OUT if col[y] == 2 else (P_AA8 if col[y] == 8 else P_AA9))
			tx += 1
	# accent bar in the player's colour under the letters
	for x in range(13, w - 13):
		_put(x, 83, P_DIA)
		_put(x, 84, P_DSH)
	_put(12, 83, P_DHI)
	_put(w - 13, 83, P_DHI)
	# outer line + bevel (they stay put when pressed)
	_po = 0
	for x in w:
		_pb[x] = P_OUT
		_pb[(h - 1) * w + x] = P_OUT
		if x >= 1 and x <= w - 2:
			_pb[w + x] = P_HI
			_pb[(h - 2) * w + x] = P_SH
	for y in h:
		_pb[y * w] = P_OUT
		_pb[y * w + w - 1] = P_OUT
		if y >= 1 and y <= h - 2:
			_pb[y * w + 1] = P_HI
			_pb[y * w + w - 2] = P_SH
	var px := _pb
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for i in px.size():
		var c: Color = pal[px[i]]
		data[i * 4] = c.r8
		data[i * 4 + 1] = c.g8
		data[i * 4 + 2] = c.b8
		data[i * 4 + 3] = 255
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	_plates[k] = img
	return img


static func _ink(col: PackedByteArray) -> PackedByteArray:
	var o := PackedByteArray()
	for v in col:
		o.append(1 if v != 0 else 0)
	return o


var _pb := PackedByteArray()                 ## plate being drawn (palette indices)
var _pw := 0
var _ph := 0
var _po := 0                                 ## pressed: content offset (1 px down-right), kept inside the bevel


func _put(x: int, y: int, v: int) -> void:
	x += _po
	y += _po
	if x >= 2 and x < _pw - 2 and y >= 2 and y < _ph - 2:
		_pb[y * _pw + x] = v


func _line(x0: int, y0: int, x1: int, y1: int, v: int) -> void:
	var n := maxi(absi(x1 - x0), absi(y1 - y0))
	for i in n + 1:
		_put(x0 + roundi(float(x1 - x0) * i / maxi(n, 1)), y0 + roundi(float(y1 - y0) * i / maxi(n, 1)), v)


## [upper-left mask, lower-right mask] of a bench box w x 96 (alpha 255 where the part is drawn)
func _mask(w: int) -> Array:
	if _masks.has(w):
		return _masks[w]
	var a := Image.create(w, 96, false, Image.FORMAT_RGBA8)
	var b := Image.create(w, 96, false, Image.FORMAT_RGBA8)
	for x in w:
		var ly := _diag_y(x, w)
		for y in 96:
			if y < ly:
				a.set_pixel(x, y, Color.WHITE)
			else:
				b.set_pixel(x, y, Color.WHITE)
	_masks[w] = [a, b]
	return _masks[w]


static func _diag_y(x: float, w: int) -> float:
	return DIAG[0] + (DIAG[1] - DIAG[0]) * x / float(w - 1)


# ------------------------------------------------------------------------------------------------ per frame
## after every game frame (game thread parked): read both teams, rebuild the picture when it changed
func frame(core) -> void:
	if mp == null:
		return
	var scene: int = core.r8(SCENE)
	if mp.debug_battle and mp.active and scene != 0:
		mp.stop()                                      # `mpbattle=1`: the battle is over
		mp.debug_battle = false
	# part 27 phase 7: also during the battle's VS intro (states 2-3; the game shows PLAYER 1's single-player panel
	# there): both teams from the team blocks once loaded, else from the party block
	var on: bool = _ok and mp.in_battle() and not mp.lan and qol.game.display.battle_on_screen()   # part 30: not in LAN
	var intro: bool = _ok and mp.in_battle() and not mp.lan and not on and scene == 0 and core.r8(SCENE + 1) >= 2 and core.r8(SCENE + 1) <= 3
	var teams: int = core.r32(TEAMS)
	if on and (teams < 0x02000000 or teams >= 0x02400000):
		on = false
	if intro:
		on = true
		var ok := teams >= 0x02000000 and teams < 0x02400000
		for side in 2:
			var n: int = core.r8(teams + side * 0x8E8 + 0x8C9) if ok else 0
			if n < 1 or n > 3 or core.r8(teams + side * 0x8E8 + 5) >= NUL:
				ok = false
		intro = not ok                               # the team blocks are loaded (as after FUN_02013D60): use them
		if dbg and qol.game.frames % 10 == 0:
			print("MPB f%d intro state %d teams %x %s" % [qol.game.frames, core.r8(SCENE + 1), teams, "party block" if intro else "team blocks"])
	if on:
		var key := ""
		for side in 2:
			var st := _read_party(core, side) if intro else _read_side(core, teams + side * 0x8E8)
			_side[side] = st
			key += str(st["key"]) + "|"
		key += str(_press)
		if key != _key:
			_key = key
			_compose()
		# fades: MASTER_BRIGHT of the engine on the lower screen (POWCNT1 bit 15 set: engine A on top)
		var mb: int = core.IO.decode_u16(0x106C if (core.IO.decode_u16(0x304) & 0x8000) != 0 else 0x6C)
		var f := minf((mb & 31) / 16.0, 1.0)
		var mode := (mb >> 14) & 3
		var fade := f if mode == 1 else (-f if mode == 2 else 0.0)
		if fade != _fade:
			_fade = fade
			queue_redraw()
		if (dbg or Game.args.has("cheatdbg")) and not intro and qol.game.frames % 10 == 0:   # (QA: no team blocks yet in the intro)
			var s: Array = []
			for side in 2:
				var tb := teams + side * 0x8E8
				var r: int = tb + core.r8(tb + 0x8C8) * 0x2D8
				s.append("p%d act idx %d id %d act %x hp %d ki %d assists %d" % [side + 1, core.r8(tb + 0x8C8), core.r8(r + 5),
					core.r8(r + 6), core.r16(r + 0x24A), core.r16(tb + 0x8D0), core.r8(tb + 0x8CA)])
			print("MPB f%d %s | %s | touch %s %s" % [qol.game.frames, s[0], s[1], str(mp.touch[0]), str(mp.touch[1])])
	if on != shown:
		shown = on
		visible = on
		queue_redraw()
		if not on:
			_key = ""


## the VS intro: a side's members from the party block (s32[3] 0x020DD524 + side·0xC, count u8 0x020DD548 + side;
## the support is the member with an id >= 26), first member active, nothing KO'd, Touch! dim; no tap targets
func _read_party(core, side: int) -> Dictionary:
	var cnt: int = clampi(core.r8(0x020DD548 + side), 0, 3)
	var active := {}
	var bench := []
	var sups := []
	for k in cnt:
		var id: int = core.r32(0x020DD524 + side * 0xC + k * 4)
		if id < 0 or id >= NUL:
			continue
		var e := {"k": k, "rec": -1, "id": id, "ko": false, "dark": false, "sup": id >= SUP_MIN, "at": Vector2i(-1, -1), "ta": false}
		if e["sup"]:
			sups.append(e)
		elif active.is_empty():
			active = e
		else:
			bench.append(e)
	var key := ["intro", active.get("id", -1)]
	for e in bench:
		key.append(e["id"])
	for e in sups:
		key.append(e["id"])
	return {"active": active, "bench": bench, "sups": sups, "lit": false, "sup_ok": true, "key": key}


func _read_side(core, tb: int) -> Dictionary:
	var cnt: int = clampi(core.r8(tb + 0x8C9), 0, 3)
	var act: int = core.r8(tb + 0x8C8)
	var assists: int = core.r8(tb + 0x8CA)
	var ki: int = core.r16(tb + 0x8D0)
	var recs := []
	var alive := 0
	for k in cnt:
		var r := tb + k * 0x2D8
		var hp: int = core.r16(r + 0x24A)
		if hp >= 0x8000:
			hp -= 0x10000
		var id: int = core.r8(r + 5)
		var x0: int = core.r16(r + 0x2D0)
		var y0: int = core.r16(r + 0x2D2)
		var x1: int = core.r16(r + 0x2D4)
		var y1: int = core.r16(r + 0x2D6)
		recs.append({"k": k, "rec": r, "id": id, "ko": hp <= 0, "sup": id >= SUP_MIN and id < NUL, "at": Vector2i((x0 + x1) / 2, (y0 + y1) / 2),
			"ta": (core.r32(r + 0x274) & 0x100) != 0})
		if hp > 0 and id < SUP_MIN:
			alive += 1
	var active: Dictionary = recs[act] if act < recs.size() else {}
	var bench := []
	var sups := []                               # party order (part 28: two with SAME CHARACTERS)
	for e in recs:
		if e["sup"]:
			sups.append(e)
	for i in cnt:
		var e: Dictionary = recs[(act + 1 + i) % cnt]
		if not e["sup"] and e["k"] != act:
			bench.append(e)
	# as the game's own panel: Touch! lit (palette row 5, FUN_0201C8F4(1)) at 200 % ki when the active fighter has a
	# Team Arts partner (rec +0x274 & 0x100, set by FUN_02026548); bench faces dark (row 7, FUN_0201C7A8(0)) below 20 %
	# ki (no tag possible) and when KO'd
	var lit: bool = ki >= 0xC800 and cnt > 1 and active.get("ta", false)
	var tag_ok := ki >= 0x1400
	for e in bench:
		e["dark"] = e["ko"] or not tag_ok
	var sup_ok := not sups.is_empty() and assists > 0
	var key := [active.get("id", -1), active.get("ko", false)]
	for e in bench:
		key.append_array([e["id"], e["dark"]])
	for e in sups:
		key.append(e["id"])
	key.append_array([sup_ok, lit])
	return {"active": active, "bench": bench, "sups": sups, "lit": lit, "sup_ok": sup_ok, "key": key}


func _compose() -> void:
	_img.fill(Color.BLACK)
	for side in 2:
		var c: Array = COLS[side]
		var st: Dictionary = _side[side]
		var ax: int = c[0]
		var aw: int = c[1]
		var bx: int = c[3]
		var bw: int = c[4]
		# A top: the active fighter in colour (dark when KO'd)
		var act: Dictionary = st["active"]
		if not act.is_empty():
			_img.blit_rect(_portrait(act["id"], "d" if act["ko"] else "c"), Rect2i(10, 0, aw, TOP_H), Vector2i(ax, 0))
		# A bottom: the bench
		var bench: Array = st["bench"]
		if bench.is_empty():
			_img.blit_rect(_portrait(NUL, "n"), Rect2i(10, 0, aw, 96), Vector2i(ax, BOT_Y))
		elif bench.size() == 1:
			_img.blit_rect(_portrait(bench[0]["id"], "d" if bench[0]["dark"] else "n"), Rect2i(10, 0, aw, 96), Vector2i(ax, BOT_Y))
		else:
			var m := _mask(aw)
			var up := Image.create(aw, 96, false, Image.FORMAT_RGBA8)
			up.blit_rect(_portrait(bench[0]["id"], "d" if bench[0]["dark"] else "n"), Rect2i(10, 0, aw, 96), Vector2i.ZERO)
			_img.blit_rect_mask(up, m[0], Rect2i(0, 0, aw, 96), Vector2i(ax, BOT_Y))
			var lo := Image.create(aw, 96, false, Image.FORMAT_RGBA8)
			lo.blit_rect(_portrait(bench[1]["id"], "d" if bench[1]["dark"] else "n"), Rect2i(10, 0, aw, 96 - LOWER_SHIFT), Vector2i(0, LOWER_SHIFT))
			_img.blit_rect_mask(lo, m[1], Rect2i(0, 0, aw, 96), Vector2i(ax, BOT_Y))
			for x in aw:                               # the split line, 2 px
				var y := roundi(_diag_y(x, aw))
				for d in [-1, 0]:
					if y + d >= 0 and y + d < 96:
						_img.set_pixel(ax + x, BOT_Y + y + d, Color.BLACK)
		# bar
		_img.fill_rect(Rect2i(c[2] + 1, 0, 6, H), BAR)
		# B top: the support (dark when no assists are left), or an empty frame; part 28: two supports (SAME
		# CHARACTERS) split the box in half, one portrait (its middle) per half, a 1-px black line between them
		var sups: Array = st["sups"]
		var kind := "n" if st["sup_ok"] else "d"
		if sups.is_empty():
			_img.blit_rect(_portrait(NUL, "n"), Rect2i(10, 0, bw, TOP_H), Vector2i(bx, 0))
		elif sups.size() == 1:
			_img.blit_rect(_portrait(sups[0]["id"], kind), Rect2i(10, 0, bw, TOP_H), Vector2i(bx, 0))
		else:
			var hw := _half_w(bw)
			_img.blit_rect(_portrait(sups[0]["id"], kind), Rect2i(SUP_MID - hw / 2, 0, hw, TOP_H), Vector2i(bx, 0))
			_img.blit_rect(_portrait(sups[1]["id"], kind), Rect2i(SUP_MID - (bw - hw - 1) / 2, 0, bw - hw - 1, TOP_H), Vector2i(bx + hw + 1, 0))
			_img.fill_rect(Rect2i(bx + hw, 0, 1, TOP_H), Color.BLACK)
		# B bottom: Touch!
		_img.blit_rect(_plate(side, st["lit"], _press[side], bw), Rect2i(0, 0, bw, 96), Vector2i(bx, BOT_Y))
	_tex.update(_img)
	queue_redraw()


## part 28: width of the left support half (the right one is bw - this - 1, after a 1-px line)
static func _half_w(bw: int) -> int:
	return (bw - 1) / 2


func _draw() -> void:
	if not shown or _tex == null:
		return
	var m := Color(1, 1, 1)
	if _fade < 0.0:
		m = Color(1 + _fade, 1 + _fade, 1 + _fade)
	draw_texture(_tex, Vector2(0, 192), m)
	if _fade > 0.0:
		draw_rect(Rect2(0, 192, 256, H), Color(1, 1, 1, _fade))


## BOSS CHARACTERS (part 27 phase 7): where the skull of fighter record `rec` goes on this panel (top-left corner in
## the 256x384 space) -- the box that shows it (active / bench part / support); (-1, -1) when not shown
func mark_at(rec: int, side: int) -> Vector2:
	if not shown or side < 0 or side > 1 or _side[side].is_empty():
		return Vector2(-1, -1)
	var c: Array = COLS[side]
	var st: Dictionary = _side[side]
	var k := -1
	for e in [st["active"]] + st["sups"] + st["bench"]:
		if not (e as Dictionary).is_empty() and e.has("rec") and e["rec"] == rec:
			k = e["k"]
	if k < 0:
		return Vector2(-1, -1)
	if not st["active"].is_empty() and st["active"]["k"] == k:
		return Vector2(c[0] + 3, 192 + 3)
	var sups: Array = st["sups"]
	for i in sups.size():
		if sups[i]["k"] == k:
			return Vector2(c[3] + 3 + (_half_w(c[4]) + 1) * i, 192 + 3)
	var bench: Array = st["bench"]
	if bench.size() >= 1 and bench[0]["k"] == k:
		return Vector2(c[0] + 3, 192 + BOT_Y + 3)
	return Vector2(c[0] + c[1] - 13, 192 + H - 13)


# ------------------------------------------------------------------------------------------------ taps
## main thread, before each game frame of an MP battle (QoLController.mp_frame): routes the frame's touch sources
## per half and returns the touch the DS touch screen gets (P1's mapped point; the plain touch when the panel is
## not on screen). Also latches the frame's presses for the game's per-call input edges (QoLGame.f_0202dce0).
func route(m: QoLMp) -> Vector2i:
	for p in 2:
		m.latch[p] = int(m.latch[p]) | int(m.pressed[p])
	var raw := [Vector2i(-1, -1), Vector2i(-1, -1)]
	for t: Vector2i in [m.mtouch, m.ptouch, m.ctouch[0], m.ctouch[1]]:
		if t.x >= 0:
			var p := 0 if t.x < 128 else 1
			if raw[p].x < 0:
				raw[p] = t
	for p in 2:                                    # part 28: the Touch! plate shows "pressed" while held on it
		var on_plate: bool = shown and raw[p].x >= 0 and _map(p, raw[p]) == TEAM_ARTS_AT
		if on_plate != _press[p]:
			_press[p] = on_plate
	if not shown:
		m.touch[1] = Vector2i(-1, -1)
		m.touch[0] = Vector2i(-1, -1)
		_prev_raw = [false, false]
		for t: Vector2i in [m.mtouch, m.ctouch[0], m.ctouch[1]]:
			if t.x >= 0:
				return t
		return Vector2i(-1, -1)
	var out := Vector2i(-1, -1)
	for p in 2:
		var t: Vector2i = raw[p]
		var mapped := _map(p, t) if t.x >= 0 else Vector2i(-1, -1)
		var was: bool = _prev_raw[p]
		_prev_raw[p] = t.x >= 0
		if p == 0:
			m.touch[0] = mapped
			out = mapped
		else:
			if mapped.x >= 0 and not was:
				m.tap[1] = mapped                      # a new touch: the game's input call sees it even if short
			m.touch[1] = mapped
		if dbg and t.x >= 0 and not was:
			print("MP f%d tap p%d at %s -> panel %s" % [qol.game.frames + 1, p + 1, str(t), str(mapped)])
	return out


## a point on player p's half of the lower screen -> that side's panel coordinates ((-1, -1): nothing there)
func _map(p: int, t: Vector2i) -> Vector2i:
	var c: Array = COLS[p]
	var st: Dictionary = _side[p]
	if st.is_empty():
		return Vector2i(-1, -1)
	if t.x >= c[3] and t.x < c[3] + c[4]:             # B column
		if t.y < TOP_H:
			var sups: Array = st["sups"]
			if sups.is_empty():
				return Vector2i(-1, -1)
			if sups.size() == 1:
				return sups[0]["at"]
			return sups[0]["at"] if t.x - c[3] <= _half_w(c[4]) else sups[1]["at"]   # part 28: one half each
		if t.y >= BOT_Y:
			return TEAM_ARTS_AT
		return Vector2i(-1, -1)
	if t.x >= c[0] and t.x < c[0] + c[1] and t.y >= BOT_Y:   # A column, bench
		var bench: Array = st["bench"]
		if bench.is_empty():
			return Vector2i(-1, -1)
		if bench.size() == 1:
			return bench[0]["at"]
		var lx: int = t.x - c[0]
		return bench[0]["at"] if t.y - BOT_Y < _diag_y(lx, c[1]) else bench[1]["at"]
	return Vector2i(-1, -1)
