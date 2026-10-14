extends RefCounted
## DRAGON BALL HUNT (part 41, cheat page 9 CHALLENGES; QoLSettings cheat "dragon_balls", test flag
## `cheats=dragon_balls`). Owned by QoLGame (`# ---- DRAGON BALL HUNT (part 41)`), which calls tick() once per battle
## frame (its FUN_0202954C override), hit() for every fighter that loses HP inside the game's collision pass
## FUN_0201E5BC, draw() after the game's sprite list (_fx_draw) and reset() at every battle load. Nothing here runs
## with the cheat off.
## The seven Dragon Balls appear one at a time (a random one of those nobody holds) at a random spot of the battle
## picture, floating. An active fighter that touches one (PICK_R world px from its body) takes it for its TEAM (the
## balls stay with the side through tags). A hit that takes at least DROP_MIN HP (or KOs) makes the victim's team drop
## its last ball: it flies out away from the attacker and can be grabbed again after a moment (by anyone). A team with
## all seven gets the WISH: its active fighter's HP and the team's ki go full (200 %), the balls circle it and fly away
## (back to nobody), and the hunt starts over REST frames later. Paused during cut-ins, supers / Team Arts (camera mode
## != 0), tags, KOs and outside the fight (battle state 7).
## HUD: each team's seven slots above its ki gauge (bottom corners), a ball in the slot of every star it holds; a ball
## off the picture gets a small marker at the screen edge.
## Art: the game's own Dragon Balls (the clear-event screen's texture, `romdata/scene/common/clearevent.bin` members
## db_normal.ntft / db_normal.ntfp / db_bright.ntfp, DATA_NOTES part 41), read from the player's ROM at runtime,
## box-filtered to 24 px (stage) and 12 px (HUD) and kept as 16-colour textures in the port's texture block
## (qol_texblock.gd, 0x5D000..) with the game's own palettes (a slot of the game's palette manager FUN_02010B6C).
## LAN: own RNG seeded at every battle load (`dbseed`), battle RAM only: both machines agree.
## Debug: `dbdbg` (spawn / grab / drop / wish lines), `dbseed=N`, `dbwait=N` (frames to the first ball), `dbgive=N`
## (player 1's team starts the fight with N balls), `dbhere=DX` (balls appear DX px right of player 1).

const SEED := 0xDB707
const FIRST_WAIT := 240                  ## running battle frames from the fight's start to the first ball
const NEXT_WAIT := 150                   ## from a grab to the next ball
const REST := 420                        ## after a wish
const PICK_R := 26                       ## world px from the fighter's body centre
const BODY_UP := 12                      ## world px from the record's y up to the body centre
const DROP_MIN := 400                    ## HP lost in one hit that makes the team drop a ball
const DROP_COOL := 60                    ## frames between two drops of one team
const GRAB_COOL := 36                    ## a dropped ball can be grabbed by the other team after this many frames, by its old one after 2 x
const WISH_T := 90                       ## frames of the wish effect
const TEAMS := 0x020DE3D0
const CAMERA := 0x020DE3A4
const BATTLE_STATE := 0x020DD4C5
const KI_FULL := 0xC800
const TEX_STAGE := 0x5D000               ## 7 x 32x32 4-bit (0x200 each): 24 px balls
const TEX_HUD := 0x5DE00                 ## 7 x 16x16 4-bit (0x80 each): 12 px balls
const S_STAGE := 24
const S_HUD := 12
const PAL_RAM := 0x027C0160              ## port-only RAM: 2 x 32 bytes (normal, bright)
const PID_BALL := 0x28                   ## polygon IDs (port effects 0x28-0x3F)
const PID_HUD := 0x29
const PID_FX := 0x2A
const FXK_DB := 0x0D00                   ## PLTT_BASE pairing keys of the untextured flash / sparkle quads
const PICK_SE := 0x31                    ## FUN_02029E3C sound of a grab (a short tonal one, DATA_NOTES part 39 table)
const WISH_SE := 0x20                    ## the fighter's power-up voice (as the ultimates')

var g = null                             ## the QoLGame
var _rng := RandomNumberGenerator.new()
var _held: Array = [[], []]              ## per side: ball indices 0-6 (= stars - 1) in the order they were taken
var _free: Array = []                    ## balls on the stage: {"k", "x", "y" (24.8 world px), "vx", "vy", "cool", "from"}
var _wait := FIRST_WAIT
var _dcool := [0, 0]
var _age := 0                            ## running frames (bobbing)
var _last := -2
var _ready := false                      ## the texture block holds our texels
var _art := false                        ## the balls were read from the ROM
var _pal := -1                           ## palette VRAM byte offset (bright = + 0x20), -2 refused
var _pnorm := PackedByteArray()
var _pbright := PackedByteArray()
var _fx: Array = []                      ## [kind, age, world x, world y, side / k]: 1 appear, 2 grab, 3 wish, 4 scatter ball
var _pop := {}                           ## side * 8 + k -> frames of a HUD slot's flash
var grabs := 0
var drops := 0
var wishes := 0
var _dbg := Game.args.has("dbdbg")
var _here := Game.args.has("dbhere")


func _init(game) -> void:
	g = game
	_load_art()
	reset()


func reset() -> void:
	_rng.seed = int(Game.flag("dbseed", str(SEED)))
	_held = [[], []]
	_free.clear()
	_wait = int(Game.flag("dbwait", str(FIRST_WAIT)))
	_dcool = [0, 0]
	_age = 0
	_last = -2
	_ready = false
	_pal = -1
	_fx.clear()
	_pop.clear()
	var give := int(Game.flag("dbgive", "0"))
	for k in clampi(give, 0, 7):
		_held[0].append(k)


func _ld(a: int, n: int, s := false) -> int:
	return g._ld(a, n, s)


func _st(a: int, n: int, v: int) -> void:
	g._st(a, n, v)


# ---- art ------------------------------------------------------------------------------------------------------------
## the clear-event pack's texture + palettes from the player's ROM -> 16-colour textures in the port's block
func _load_art() -> void:
	var rom: PackedByteArray = g.hw.rom
	var f := QoLFont.nitro_file(rom, "romdata/scene/common/clearevent.bin")
	if f.x < 0 or f.y - f.x < 0x100:
		return
	var want := {"db_normal.ntft": PackedByteArray(), "db_normal.ntfp": PackedByteArray(), "db_bright.ntfp": PackedByteArray()}
	var hs := rom.decode_u32(f.x + 4)
	var cnt := rom.decode_u16(f.x + 2)
	for i in cnt:
		var e := f.x + 8 + i * 0x4C
		if e + 0x4C > f.y:
			break
		var nm := rom.slice(e, e + 64).get_string_from_ascii().replace("\\", "/").get_file()
		if want.has(nm) and (want[nm] as PackedByteArray).is_empty():
			var us := rom.decode_u32(e + 64)
			var ss := rom.decode_u32(e + 68)
			var a := f.x + hs + rom.decode_u32(e + 72)
			if a + ss > f.y or us > 0x10000:
				return
			var raw := rom.slice(a, a + ss)
			want[nm] = raw if us == ss else QoLEpicImg._decompress(raw, us)
	var tex: PackedByteArray = want["db_normal.ntft"]
	_pnorm = want["db_normal.ntfp"]
	_pbright = want["db_bright.ntfp"]
	if tex.size() != 16384 or _pnorm.size() != 32 or _pbright.size() != 32:
		return
	var rgb: Array = []                                 # palette colours 0..15 as Vector3 (0..31)
	for i in 16:
		var c := _pnorm.decode_u16(i * 2)
		rgb.append(Vector3(c & 31, (c >> 5) & 31, (c >> 10) & 31))
	var tb = g._tex_block()
	for k in 7:
		var cx := (k % 4) * 64
		var cy := (k / 4) * 64
		var x0 := 64
		var y0 := 64
		var x1 := -1
		var y1 := -1
		for y in 64:
			for x in 64:
				if _ix(tex, cx + x, cy + y) != 0:
					x0 = mini(x0, x)
					y0 = mini(y0, y)
					x1 = maxi(x1, x)
					y1 = maxi(y1, y)
		if x1 < 0:
			return
		var side := maxi(x1 - x0, y1 - y0) + 1
		tb.put_abs(TEX_STAGE + k * 0x200, _shrink(tex, rgb, cx + x0, cy + y0, side, S_STAGE, 32))
		tb.put_abs(TEX_HUD + k * 0x80, _shrink(tex, rgb, cx + x0, cy + y0, side, S_HUD, 16))
	_art = true


static func _ix(tex: PackedByteArray, x: int, y: int) -> int:
	var i := y * 256 + x
	return (tex[i >> 1] >> (4 * (i & 1))) & 15


## the n x n source square at (sx, sy) box-filtered to s x s px (4 x 4 samples per px, opaque where at least half
## the samples are), each px the nearest palette colour; centred in a tw x tw 4-bit texture (low nibble = left px)
static func _shrink(tex: PackedByteArray, rgb: Array, sx: int, sy: int, n: int, s: int, tw: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(tw * tw / 2)
	var o := (tw - s) / 2
	for y in s:
		for x in s:
			var acc := Vector3.ZERO
			var hits := 0
			for j in 4:
				for i in 4:
					var u := sx + int((x + (i + 0.5) / 4.0) * n / s)
					var v := sy + int((y + (j + 0.5) / 4.0) * n / s)
					var c := _ix(tex, u, v)
					if c != 0:
						acc += rgb[c]
						hits += 1
			if hits < 8:
				continue
			acc /= hits
			var best := 1
			var bd := 1e9
			for c in range(1, 16):
				var d: float = (acc - (rgb[c] as Vector3)).length_squared()
				if d < bd:
					bd = d
					best = c
			var p := (y + o) * tw + x + o
			out[p >> 1] = out[p >> 1] | (best << (4 * (p & 1)))
	return out


## the two palettes into a slot of the game's texture-palette manager (once per battle)
func _alloc_pal() -> void:
	if _pal != -1 or not _art:
		return
	for i in 32:
		_st(PAL_RAM + i, 1, _pnorm[i])
		_st(PAL_RAM + 0x20 + i, 1, _pbright[i])
	var s: int = g.f_02010b6c(PAL_RAM, 0x40)
	_pal = s if s != 0xFFFF else -2
	if _dbg:
		print("DB f%d palettes at %x" % [g._port_frame(), _pal])


# ---- the hunt ---------------------------------------------------------------------------------------------------------
## may the hunt go on this frame?
func _running() -> bool:
	if _ld(BATTLE_STATE, 1) != 7 or g.f_02012fd4() != 0:
		return false
	var cam: int = _ld(CAMERA, 4)
	if cam == 0 or _ld(cam, 2) != 0:
		return false
	if _ld(_ld(TEAMS, 4) + 0x11DC, 4) != 0:
		return false                                    # a tag runs
	return true


func tick(pf: int) -> void:
	if pf == _last:
		return
	_last = pf
	if not _art:
		return
	_ready = g._tex_block().ok()
	_alloc_pal()
	if not _running():
		return
	_age += 1
	for s in 2:
		if _dcool[s] > 0:
			_dcool[s] -= 1
	# the balls on the stage: dropped ones glide out and slow down, then float
	var floor_y: int = _ld(_ld(0x020DE3CC, 4) + 0x4DEE, 2, true)
	for b in _free:
		if b["cool"] > 0:
			b["cool"] -= 1
		if b["vx"] != 0 or b["vy"] != 0:
			b["x"] += b["vx"]
			b["y"] += b["vy"]
			b["vx"] = b["vx"] * 7 / 8
			b["vy"] = b["vy"] * 7 / 8
			if absi(b["vx"]) < 0x20 and absi(b["vy"]) < 0x20:
				b["vx"] = 0
				b["vy"] = 0
		var low: int = (floor_y + 8) << 8                # never under the floor line (the fighters' feet reach it)
		if b["y"] > low:
			b["y"] = low
			b["vy"] = 0
	# grabs
	for side in 2:
		var r: int = g.f_02027c00(side)
		if r == 0 or _ld(r + 0x24A, 2, true) <= 0 or _ld(r + 6, 1) == 0x33:
			continue
		var fx: int = _ld(r + 0x38, 4, true) >> 8
		var fy: int = (_ld(r + 0x3C, 4, true) >> 8) - BODY_UP
		for b in _free.duplicate():
			if b["cool"] > (0 if b["from"] == side else GRAB_COOL):
				continue                                # just dropped: the other team first, the old one later
			var dx: int = (b["x"] >> 8) - fx
			var dy: int = (b["y"] >> 8) - fy
			if dx * dx + dy * dy <= PICK_R * PICK_R:
				_grab(side, r, b, pf)
	if _held[0].size() >= 7 or _held[1].size() >= 7:
		_wish(0 if _held[0].size() >= 7 else 1, pf)
		return
	# the next ball
	if _free.is_empty() and _held[0].size() + _held[1].size() < 7:
		_wait -= 1
		if _wait <= 0:
			_spawn(pf)


func _grab(side: int, r: int, b: Dictionary, pf: int) -> void:
	_free.erase(b)
	var k: int = b["k"]
	_held[side].append(k)
	_pop[side * 8 + k] = 20
	_fx.append([2, 0, b["x"] / 256.0, b["y"] / 256.0, k])
	g.f_02029e3c(r, PICK_SE)
	grabs += 1
	_wait = NEXT_WAIT
	if _dbg:
		print("DB f%d side %d grabs the %d-star ball (holds %d)" % [pf, side, k + 1, _held[side].size()])


## a random ball nobody holds, at a random spot of the picture (away from the HUD), floating
func _spawn(pf: int) -> void:
	var left: Array = []
	for k in 7:
		if not k in _held[0] and not k in _held[1]:
			left.append(k)
	if left.is_empty():
		return
	var k: int = left[_rng.randi_range(0, left.size() - 1)]
	var cam: int = _ld(CAMERA, 4)
	var z: int = maxi(_ld(cam + 6, 2), 0x40)
	var sx: int = _rng.randi_range(36, 220)
	var sy: int = _rng.randi_range(56, 136)
	var wx: int = _ld(cam + 0xC, 4, true) + (sx - _ld(cam + 0x30, 4, true)) * 256 / z
	var wy: int = _ld(cam + 0x10, 4, true) + (sy - _ld(cam + 0x34, 4, true)) * 256 / z
	var floor_y: int = _ld(_ld(0x020DE3CC, 4) + 0x4DEE, 2, true)
	wy = mini(wy, floor_y - 24)
	if _here:                                           # debug `dbhere`: on player 1 (tests a grab)
		var p1: int = g.f_02027c00(0)
		wx = (_ld(p1 + 0x38, 4, true) >> 8) + int(Game.flag("dbhere", "0"))
		wy = (_ld(p1 + 0x3C, 4, true) >> 8) - BODY_UP
	_free.append({"k": k, "x": wx << 8, "y": wy << 8, "vx": 0, "vy": 0, "cool": 0, "from": -1})
	_fx.append([1, 0, float(wx), float(wy), k])
	if _dbg:
		print("DB f%d the %d-star ball appears at %d,%d" % [pf, k + 1, wx, wy])


## a fighter lost HP inside the collision pass: a big enough hit makes its team drop its last ball
func hit(v: int, lost: int) -> void:
	if not _art:
		return
	var side: int = _ld(v + 0x1A, 1) & 1
	if v != g.f_02027c00(side) or _held[side].is_empty() or _dcool[side] > 0:
		return
	if lost < DROP_MIN and _ld(v + 0x24A, 2, true) > 0:
		return
	var k: int = _held[side].pop_back()
	_dcool[side] = DROP_COOL
	var a: int = g.f_02027c00(1 - side)
	var x: int = _ld(v + 0x38, 4, true)
	var dir := 1
	if a != 0 and _ld(a + 0x38, 4, true) > x:
		dir = -1
	_free.append({"k": k, "x": x, "y": _ld(v + 0x3C, 4, true) - (BODY_UP << 8), "vx": dir * 0x600, "vy": -0x400,
		"cool": GRAB_COOL * 2, "from": side})
	_pop.erase(side * 8 + k)
	drops += 1
	if _dbg:
		print("DB f%d side %d drops the %d-star ball (lost %d HP, holds %d)" % [g._port_frame(), side, k + 1, lost, _held[side].size()])


func _wish(side: int, pf: int) -> void:
	var r: int = g.f_02027c00(side)
	if r != 0:
		_st(r + 0x24A, 2, _ld(r + 0x24C, 2))
		g.f_02029e3c(r, WISH_SE)
		_fx.append([3, 0, _ld(r + 0x38, 4, true) / 256.0, (_ld(r + 0x3C, 4, true) >> 8) - BODY_UP, side])
	_st(_ld(TEAMS, 4) + side * 0x8E8 + 0x8D0, 2, KI_FULL)
	wishes += 1
	if _dbg:
		print("DB f%d side %d has all seven: WISH (HP %d / %d, ki full)" % [pf, side, _ld(r + 0x24A, 2, true) if r != 0 else 0,
			_ld(r + 0x24C, 2) if r != 0 else 0])
	_held = [[], []]
	_free.clear()
	_pop.clear()
	_wait = REST


# ---- drawing ----------------------------------------------------------------------------------------------------------
## one textured quad of 16-colour texture `tex` (tw x tw texels, size code sc) drawn dw x dw px with its top left at
## (x, y); colour `col` modulates (0 = black silhouette)
func _quad(tex: int, tw: int, sc: int, x: float, y: float, dw: float, z: int, al: int, pid: int, col: int, bright := false) -> void:
	var s := 16.0 * dw / tw
	g.io_write(0x4000440, 4, 2)
	g.io_write(0x4000444, 4, 0)
	for v in [s, 0.0, 0.0, 0.0, s, 0.0, 0.0, 0.0, 1.0, x, y, float(z)]:
		g.io_write(0x4000464, 4, int(roundf(v * 4096.0)) & 0xFFFFFFFF)
	g.io_write(0x40004A8, 4, (tex >> 3) | (sc << 20) | (sc << 23) | (3 << 26) | (1 << 29))
	g.io_write(0x40004AC, 4, (_pal + (0x20 if bright else 0)) >> 4)
	g.io_write(0x40004A4, 4, 0x80C0 | (al << 16) | (pid << 24))
	g.io_write(0x4000480, 4, col)
	g.io_write(0x4000500, 4, 1)
	var xs := [0, 0, tw, tw]
	var ys := [0, tw, tw, 0]
	for k in 4:
		g.io_write(0x4000488, 4, (xs[k] * 16) | ((ys[k] * 16) << 16))
		var xy: int = ((xs[k] * 256) & 0xFFFF) | (((ys[k] * 256) & 0xFFFF) << 16)
		if k == 0:
			g.io_write(0x400048C, 4, xy)
			g.io_write(0x400048C, 4, 0)
		else:
			g.io_write(0x4000494, 4, xy)
	g.io_write(0x4000504, 4, 0)
	g.io_write(0x4000448, 4, 1)


## a stage ball (24 px in its 32x32 texture) centred on screen point (sx, sy)
func _ball(k: int, sx: float, sy: float, z: int, al: int, bright := false, col := 0x7FFF) -> void:
	_quad(TEX_STAGE + k * 0x200, 32, 2, floorf(sx) - 16.0, floorf(sy) - 16.0, 32.0, z, al, PID_BALL, col, bright)


## a HUD ball (12 px in its 16x16 texture) centred on (sx, sy)
func _hball(k: int, sx: float, sy: float, al: int, bright := false, col := 0x7FFF) -> void:
	_quad(TEX_HUD + k * 0x80, 16, 1, floorf(sx) - 8.0, floorf(sy) - 8.0, 16.0, 44, al, PID_HUD, col, bright)


func any_fx() -> bool:
	return _art


## after the game's sprite list (QoLGame._fx_draw): idx = sprites drawn this frame, cv = camera
func draw(idx: Dictionary, cv: Array) -> bool:
	if not _art or not _ready or _pal < 0:
		return false
	var teams: int = _ld(TEAMS, 4)
	var on := false
	for side in 2:
		var tb := teams + side * 0x8E8
		if idx.has(tb + _ld(tb + 0x8C8, 1) * 0x2D8 + 0x124):
			on = true
	if not on:
		return false
	var run: bool = g.f_02012fd4() == 0
	var cam: int = _ld(CAMERA, 4)
	var hud: bool = cam != 0 and _ld(cam, 2) == 0           # (supers / Team Arts: their own picture, no HUD)
	var z: float = cv[4]
	var drew := false
	# the balls on the stage (bobbing), or a marker at the edge while off the picture
	for b in _free:
		var wx: float = b["x"] / 256.0
		var wy: float = b["y"] / 256.0 + (sin((_age + int(b["k"]) * 9) * 0.09) * 2.5 if b["vx"] == 0 and b["vy"] == 0 else 0.0)
		var sx: float = cv[2] + z * (wx - cv[0])
		var sy: float = cv[3] + z * (wy - cv[1])
		var blink: bool = b["cool"] > 0 and (b["cool"] / 3) % 2 == 0
		if sx > -12.0 and sx < 268.0 and sy > -12.0 and sy < 204.0:
			_ball(b["k"], sx, sy, 36, 31, (_age / 8) % 6 == 0 or blink)
		elif hud:
			var mx := clampf(sx, 10.0, 246.0)
			var my := clampf(sy, 64.0, 150.0)
			_hball(b["k"], mx, my, 26)
			var d := (Vector2(sx, sy) - Vector2(mx, my)).normalized()
			for j in 2:
				var c := Vector2(mx, my) + d * (9.0 + j * 3.0)
				var w := 3 - j * 2
				g._fx_box(floorf(c.x - w * 0.5), floorf(c.y - w * 0.5), w, w, 0x029F, 0x80C0 | (31 << 16) | (PID_FX << 24), 45, FXK_DB + 0x40 + j)
		drew = true
	# effects
	var keep: Array = []
	for e in _fx:
		var age: int = e[1]
		var sx: float = cv[2] + z * (float(e[2]) - cv[0])
		var sy: float = cv[3] + z * (float(e[3]) - cv[1])
		match int(e[0]):
			1, 2:                                       # appear / grab: a ring of gold sparks
				var u := age / 16.0
				for i in 8:
					var ang := TAU * i / 8.0 + (0.0 if e[0] == 1 else 0.4)
					var rr := (18.0 * (1.0 - u) if e[0] == 1 else 4.0 + 20.0 * u)
					var px := floorf(sx + cos(ang) * rr)
					var py := floorf(sy + sin(ang) * rr)
					var al := clampi(int(31.0 * (1.0 - u * u)), 1, 31)
					g._fx_box(px, py, 2, 2, 0x3BFF if i % 2 == 0 else 0x7FFF, 0x80C0 | (al << 16) | (PID_FX << 24), 37, FXK_DB + int(e[0]) * 16 + i)
				if e[0] == 2 and age < 10:              # the grabbed ball shrinks into the fighter
					var s := 1.0 - age / 10.0
					_quad(TEX_STAGE + int(e[4]) * 0x200, 32, 2, floorf(sx - 16.0 * s), floorf(sy - 16.0 * s), 32.0 * s, 36, 31, PID_BALL, 0x7FFF, true)
				if age >= 16:
					age = 999
			3:                                          # wish: the seven balls circle the fighter and fly away, gold flash
				var u := age / float(WISH_T)
				var spin := age * 0.12
				for k in 7:
					var ang := TAU * k / 7.0 + spin
					var rr := 34.0 - 14.0 * minf(u * 3.0, 1.0) + maxf(u - 0.55, 0.0) * 400.0
					var al := 31 if u < 0.7 else clampi(int(31.0 * (1.0 - u) / 0.3), 1, 31)
					_ball(k, sx + cos(ang) * rr, sy + sin(ang) * rr * 0.8, 36, al, age < 48 and (age / 8) % 2 == 0)
				if age < 24:                            # the screen flashes gold, fading
					var fa := clampi(int(18.0 * (1.0 - age / 24.0)), 1, 18)
					g._fx_box(0.0, 0.0, 256, 192, 0x3BFF, 0x80C0 | (fa << 16) | (PID_FX << 24), 46, FXK_DB + 0x50)
				for i in 12:                            # a rising column of light sparks
					var t := fposmod(age * 0.04 + i / 12.0, 1.0)
					var px := floorf(sx + sin(i * 2.4 + age * 0.2) * 10.0)
					var py := floorf(sy + 20.0 - t * 80.0)
					g._fx_box(px, py, 1, 3, 0x7FFF if i % 3 == 0 else 0x3BFF, 0x80C0 | (clampi(int(28.0 * (1.0 - t)), 1, 31) << 16) | (PID_FX << 24), 37, FXK_DB + 0x60 + i)
				if age >= WISH_T:
					age = 999
		drew = true
		if run:
			age += 1
		if age < 999:
			e[1] = age
			keep.append(e)
	_fx = keep
	# the HUD: seven slots per team above its ki gauge
	if hud:
		for side in 2:
			for k in 7:
				var x := 9.0 + k * 13.0 if side == 0 else 247.0 - (6 - k) * 13.0
				var y := 163.0
				var pk: int = side * 8 + k
				if k in _held[side]:
					var p: int = _pop.get(pk, 0)
					_hball(k, x, y - (2.0 if p > 14 else 0.0), 31, p > 0 and (p / 3) % 2 == 0)
				else:
					_hball(k, x, y, 16, false, 0)      # an empty slot: a dark disc
				drew = true
		if run:
			for pk in _pop.keys():
				_pop[pk] -= 1
				if _pop[pk] <= 0:
					_pop.erase(pk)
	return drew
