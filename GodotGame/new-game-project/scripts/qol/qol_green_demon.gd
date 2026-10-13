extends RefCounted
## GREEN DEMON (part 36, cheat page 9 CHALLENGES; QoLSettings cheat "green_demon", test flag `cheats=green_demon`),
## after the fan-made Super Mario 64 challenge. Owned by QoLGame (`# ---- GREEN DEMON (part 36)`), which calls tick()
## once per battle frame (its FUN_0202954C override), draw() after the game's sprite list (_fx_draw), shift() when the
## game moves every effect object (FUN_02021DD4: stage wrap-around, STAGE SHUFFLE) and reset() at every battle load.
## Nothing here runs with the cheat off.
## A green 1-UP mushroom (the user's art, assets_qol/greendemon.png, 16x16, edited from greendemon_src.png) appears far
## off the picture once the fight runs and creeps toward the player's active fighter at a constant speed (SPEED world
## px / frame, slower than normal flight: it can be outrun, but not ignored; when a knock-back left it more than FAR
## px behind, it catches up faster, at most SPEED_MAX, until it is FAR px away again). Touching that fighter's hurt box KOs it
## at once (guarding, INFINITE HEALTH do not help): the game's own explosion (common effect kind 1) + SE 0x2B (the
## game's big-explosion sound) at the 1-UP, HP to 0 through the game's damage function, knock-back + hit reaction
## like a heavy blast; then the 1-UP warps off the picture, at least TELE_D world px from every player, and rests
## REST running battle frames (the KO / tag-in sequence itself freezes it too). It ignores the CPU side (passes
## through enemy fighters, supports and shots). Local / LAN multiplayer: both players are prey; it hunts a random one
## and switches to the other every SWITCH frames (10 s), except while it is within CLOSE_IN px of its target's hurt
## box (locked on); once that target gets CLOSE_OUT px away it picks a random target again (timer restarted).
## Frozen like BOMB RAIN: pause, events 8 / 0xA-0xE, cut-ins, tag changes, super / Team Arts camera, KO; hidden during
## throws / clashes (action 0x34).
## LAN: everything that changes the game (position, target, kill) uses only battle RAM, this file's own RNG (seeded at
## every battle load), + - * / sqrt and the game's unzoomed camera, so both machines agree (LAN_DESIGN 1.2); the
## drawn camera (CAMERA ZOOM) is used only outside LAN battles and for drawing.
## Drawing: one textured GX quad + a floor shadow in the port's shared texture block (qol_texblock.gd, offsets
## FR_OFS / SH_OFS), like BOMB RAIN, so zoom / shake / mirror / smooth motion move it as one piece.
## Debug: `gddbg` (spawn / target / lock / kill / warp lines + a status line every 60 frames), `gdpos` (position every
## frame), `gdspeed=F` (world px / frame), `gdseed=N`, `gdse=N` (kill sound), `gdwait=N` (frames to the first spawn).
## DATA_NOTES "part 36 findings (green demon)".

const PNG := "res://assets_qol/greendemon.png"
const SEED := 0x1F00D
const FIRST_WAIT := 90                   ## running battle frames from the fight's start to the spawn
const SPEED := 0.9                       ## world px / frame (54 px/s; fighters fly ~2, dash ~12: DATA_NOTES part 36)
const FAR := 300.0                       ## farther than this (off the picture): catch up, SPEED + (d - FAR) * CATCH ...
const CATCH := 0.01
const SPEED_MAX := 3.0                   ## ... up to this (knock-backs throw fighters 1000+ px away)
const TELE_D := 320.0                    ## spawn / warp: at least this far from every player (world px) ...
const VIEW_PAD := 24.0                   ## ... and this far outside the picture
const REST := 120                        ## running battle frames it waits after a kill
const SWITCH := 600                      ## MP: frames between target switches (10 s)
const CLOSE_IN := 24.0                   ## MP: locked on within this distance to the target's hurt box (world px)
const CLOSE_OUT := 40.0                  ## MP: ... until the target is this far away
const BOX_INSET := 2.0                   ## the touch box: the 16x16 picture minus 2 px on each side
const KILL_SE := 0x2B                    ## FUN_02029E3C sound: the game's big explosion (with effect size 4 there)
const EXPL_KIND := 1                     ## common effect kind 1: ki-blast explosion
const EXPL_ARG := 0x10008                ## FUN_0202216C: size 1 (~70 px)
const BOX := 0x027C0010                  ## port-only RAM: 8 bytes, FUN_0201DF20's box output (bombs: 0x027C0000)
const TEAMS := 0x020DE3D0
const CAMERA := 0x020DE3A4
const BATTLE_STATE := 0x020DD4C5
const POOL := 0x020DE3CC                 ## effect pool block: +0x4DE7 bounded flag, +0x4DE8 x0, +0x4DEC x1 (s16 px)
const Z_DEMON := 12
const Z_SHADOW := 1
const PID_DEMON := 0x24
const PID_SHADOW := 0x25
const KEY_DEMON := 16                    ## PLTT_BASE keys (bombs use 0-4 and 8-12): smooth motion pairs only these
const KEY_SHADOW := 17
const ATTR := 0x00C0 | (31 << 16)        ## POLYGON_ATTR: both faces, opaque, NO fog (stage fog bleached it: readability)
const TEX_OFS := 0x5F000                 ## qol_texblock.gd TEX_OFS
const FR_OFS := 0xD00                    ## block offset of the 16x16 frame (BOMB RAIN uses 0..0xD00)
const SH_OFS := 0xF00                    ## block offset of the 16x8 shadow
const SH_W := 16
const SH_H := 6

var g = null                             ## the QoLGame
var _rng := RandomNumberGenerator.new()
var _on := false                         ## spawned (this battle)
var _x := 0.0                            ## centre, world px
var _y := 0.0
var _wait := FIRST_WAIT
var _rest := 0
var _target := 0                         ## side it hunts
var _switch := SWITCH
var _locked := false
var _kills := 0
var _t := 0                              ## running battle frames
var _last := -2                          ## port frame of the last tick
var _hidden := false
var _ready := false                      ## the texture block holds our texels: drawable
var _cv_draw: Array = []                 ## camera of the last drawn battle frame (see draw)
var _w := 16
var _h := 16
var _qd: Array = []                      ## the 1-UP quad's GX commands (built once)
var _qs: Array = []                      ## the shadow quad's
var _art := false
var _dbg := Game.args.has("gddbg")
var _pdbg := Game.args.has("gdpos")
var _speed := maxf(0.05, float(Game.flag("gdspeed", str(SPEED))))
var _se := int(Game.flag("gdse", str(KILL_SE)))
var _tprev := Vector2(INF, INF)          ## debug: the target's centre last frame (speed log)
var _tvmax := 0.0


func _init(game, img: Image) -> void:
	g = game
	_load_art(img)
	_qd = _quad(FR_OFS, 1, PID_DEMON, KEY_DEMON, _w, _h)
	_qs = _quad(SH_OFS, 0, PID_SHADOW, KEY_SHADOW, SH_W, SH_H)
	reset()


## the picture (main thread, when QoLGame is created; see qol_bombs.gd load_image); null when it is missing
static func load_image() -> Image:
	var tex = load(PNG) if ResourceLoader.exists(PNG) else null
	if not tex is Texture2D:
		push_warning("GREEN DEMON: %s missing" % PNG)
		return null
	var img: Image = (tex as Texture2D).get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	return img


func reset() -> void:
	_rng.seed = int(Game.flag("gdseed", str(SEED)))
	_on = false
	_wait = int(Game.flag("gdwait", str(FIRST_WAIT)))
	_rest = 0
	_target = 0
	_switch = SWITCH
	_locked = false
	_kills = 0
	_t = 0
	_hidden = false
	_ready = false
	_cv_draw = []
	_tprev = Vector2(INF, INF)


## the picture (at most 16x16) -> direct-colour texels in the shared block: frame at FR_OFS (16x16, picture in its
## top-left corner), shadow at SH_OFS (16x8: the same 16x6 black ellipse as BOMB RAIN's)
func _load_art(img: Image) -> void:
	if img == null or img.get_width() > 16 or img.get_height() > 16:
		if img != null:
			push_warning("GREEN DEMON: %s must be at most 16x16 px" % PNG)
		return
	_w = img.get_width()
	_h = img.get_height()
	var fr := PackedByteArray()
	fr.resize(0x200)
	for y in _h:
		for x in _w:
			var c := img.get_pixel(x, y)
			if c.a >= 0.5:
				fr.encode_u16((y * 16 + x) * 2, _c15(c) | 0x8000)
	var sh := PackedByteArray()
	sh.resize(0x100)
	for r in [[4, 0, 8, 6], [1, 1, 14, 4], [0, 2, 16, 2]]:
		for y in range(r[1], r[1] + r[3]):
			for x in range(r[0], r[0] + r[2]):
				sh.encode_u16((y * 16 + x) * 2, 0x8000)
	var tb = g._tex_block()
	tb.put(FR_OFS, fr)
	tb.put(SH_OFS, sh)
	_art = true


func _c15(c: Color) -> int:
	return int(c.r * 31.0 + 0.5) | (int(c.g * 31.0 + 0.5) << 5) | (int(c.b * 31.0 + 0.5) << 10)


func _ld(a: int, n: int, s: bool = false) -> int:
	return g._ld(a, n, s)


func _st(a: int, n: int, v: int) -> void:
	g._st(a, n, v)


## the active fighter record of each side
func _active() -> Array:
	var teams: int = _ld(TEAMS, 4)
	var r: Array = []
	for side in 2:
		var tb := teams + side * 0x8E8
		r.append(tb + _ld(tb + 0x8C8, 1) * 0x2D8)
	return r


## the sides it hunts: player 1, and player 2 in a local / LAN multiplayer battle
func _players() -> Array:
	return [0, 1] if g._mp_on() else [0]


func _floor_y() -> float:
	return float(_ld(_ld(_ld(0x0201B49C, 4), 4) + 0xCC2, 2) + 64)   # where fighters' feet stand (BLOOD's BL_FEET)


## camera: [x at screen x cam30, y at screen y cam34, cam30, cam34, zoom (1.0 = 256)]
func _cam() -> Array:
	var cam: int = _ld(CAMERA, 4)
	return [_ld(cam + 0xC, 4, true), _ld(cam + 0x10, 4, true), _ld(cam + 0x30, 4, true), _ld(cam + 0x34, 4, true),
		maxf(_ld(cam + 6, 2) / 256.0, 0.05)]


## hurt box (type 2, first) as FUN_0201EE60 reads it: [x0, y0, x1, y1] world px
func _hurtbox(r: int) -> Array:
	g.f_0201df20(BOX, r, 2, 0)
	return [float(_ld(BOX, 2, true)), float(_ld(BOX + 2, 2, true)), float(_ld(BOX + 4, 2, true)), float(_ld(BOX + 6, 2, true))]


func _centre(hb: Array) -> Vector2:
	return Vector2((hb[0] + hb[2]) * 0.5, (hb[1] + hb[3]) * 0.5)


## distance from the 1-UP's centre to a hurt box (0 inside)
func _box_dist(hb: Array) -> float:
	var dx := maxf(maxf(hb[0] - _x, _x - hb[2]), 0.0)
	var dy := maxf(maxf(hb[1] - _y, _y - hb[3]), 0.0)
	return sqrt(dx * dx + dy * dy)


func _hittable(r: int) -> bool:
	if _ld(r + 0x24A, 2, true) <= 0 or (_ld(r + 0x12, 2) & 8) != 0:
		return false
	if (_ld(r + 0x250, 4) & 0x800) != 0:
		return false                                 # frozen (game-controlled sequence)
	var a: int = _ld(r + 6, 1)
	return not (a in [0x13, 0x14, 0x15, 0x33])       # intro / win poses, KO


## once per battle frame (QoLGame's FUN_0202954C override, before the first fighter of the frame runs)
func tick(port_frame: int) -> void:
	if port_frame == _last:
		return
	_last = port_frame
	_tick(port_frame)


func _tick(pf: int) -> void:
	var st: int = _ld(BATTLE_STATE, 1)
	if st != 7:
		return                                       # not fighting (intro, pause 9, events, KO, result): frozen
	var act := _active()
	for r in act:
		if _ld(r + 0x24A, 2, true) <= 0:
			return                                   # a KO is running: frozen
	if g.f_02012fd4() != 0 or _ld(_ld(TEAMS, 4) + 0x11DC, 4) != 0:
		return                                       # pause / cut-in, tag change: frozen
	var cam: int = _ld(CAMERA, 4)
	if cam != 0 and _ld(cam, 2) != 0:
		return                                       # super / team arts camera: frozen
	_hidden = false
	for r in act:
		if _ld(r + 6, 1) == 0x34:
			_hidden = true                           # throw / clash sequence: frozen and not drawn
			return
	_t += 1
	_ready = _art and g._tex_block().ok()
	# (part 30 rule) a LAN battle uses the game's own camera; elsewhere the drawn one (includes CAMERA ZOOM)
	var cv: Array = _cv_draw if not _cv_draw.is_empty() and not g.lan_battle() else _cam()
	var sides := _players()
	if not _on:
		_wait -= 1
		if _wait <= 0:
			_target = 0 if sides.size() == 1 else _rng.randi_range(0, 1)
			_switch = SWITCH
			_locked = false
			_place(act, sides, cv)
			_on = true
			if _dbg:
				print("GD f%d spawn at %.0f,%.0f hunting side %d (players %s, speed %.2f)" % [pf, _x, _y, _target, str(sides), _speed])
		return
	if _rest > 0:
		_rest -= 1
		if _dbg and _rest == 0:
			print("GD f%d rest over at %.0f,%.0f, hunting side %d" % [pf, _x, _y, _target])
		return
	if _target >= act.size() or not (_target in sides):
		_target = 0
	var tr: int = act[_target]
	var hb := _hurtbox(tr)
	var tc := _centre(hb)
	# multiplayer target rules (decided before moving, on this frame's positions)
	if sides.size() > 1:
		var d := _box_dist(hb)
		if _locked:
			if d > CLOSE_OUT:
				_locked = false
				_target = _rng.randi_range(0, 1)
				_switch = SWITCH
				if _dbg:
					print("GD f%d lock lost (%.0f px): random target side %d, next switch in %d" % [pf, d, _target, _switch])
		elif d <= CLOSE_IN:
			_locked = true
			if _dbg:
				print("GD f%d locked on side %d (%.0f px)" % [pf, _target, d])
		else:
			_switch -= 1
			if _switch <= 0:
				_target = 1 - _target
				_switch = SWITCH
				if _dbg:
					print("GD f%d switch: now hunting side %d" % [pf, _target])
		if act[_target] != tr:
			tr = act[_target]
			hb = _hurtbox(tr)
			tc = _centre(hb)
	# creep toward the target's hurt-box centre
	var dx := tc.x - _x
	var dy := tc.y - _y
	var dist := sqrt(dx * dx + dy * dy)
	if dist > 0.0001:
		var v := _speed
		if dist > FAR:
			v = minf(_speed + (dist - FAR) * CATCH, maxf(SPEED_MAX, _speed))   # far off the picture: catch up
		var step := minf(v, dist)
		_x += dx / dist * step
		_y += dy / dist * step
	if _dbg:
		var tp := Vector2(_ld(tr + 0x38, 4, true) / 256.0, _ld(tr + 0x3C, 4, true) / 256.0)   # the fighter's position
		if _tprev.x != INF and (tp - _tprev).length() < 40.0:   # (not a warp / teleport)
			_tvmax = maxf(_tvmax, (tp - _tprev).length())
		_tprev = tp
		if pf % 60 == 0:
			print("GD f%d at %.0f,%.0f -> side %d %.0f px away (target %.0f,%.0f, its top speed last 60 f %.2f px/f) switch %d locked %s kills %d" % [pf,
				_x, _y, _target, dist, tc.x, tc.y, _tvmax, _switch, _locked, _kills])
			_tvmax = 0.0
	if _pdbg:
		print("GDPOS f%d %.2f %.2f" % [pf, _x, _y])
	# touch: any hunted side's active fighter (the CPU side is never touched)
	var hw := _w * 0.5 - BOX_INSET
	var hh := _h * 0.5 - BOX_INSET
	for s in sides:
		var r: int = act[s]
		if absf(_ld(r + 0x38, 4, true) / 256.0 - _x) > 96.0 or absf(_ld(r + 0x3C, 4, true) / 256.0 - _y) > 112.0:
			continue                                 # far away: skip the hurt box
		if not _hittable(r):
			continue
		var b := _hurtbox(r)
		if _x + hw >= b[0] and _x - hw <= b[2] and _y + hh >= b[1] and _y - hh <= b[3]:
			_kill(r, act, sides, cv, pf)
			return


## KO the fighter it touched, then warp away and rest
func _kill(r: int, act: Array, sides: Array, cv: Array, pf: int) -> void:
	var hp: int = _ld(r + 0x24A, 2, true)
	var o: int = g.f_0202247c(r, EXPL_KIND)          # the game's ki-blast explosion at the 1-UP
	if o != 0:
		g.f_0202216c(o, EXPL_ARG, 0)
		_st(o + 0x38, 4, int(_x * 256.0) & 0xFFFFFFFF)
		_st(o + 0x3C, 4, int(_y * 256.0) & 0xFFFFFFFF)
	if _se >= 0:
		g.f_02029e3c(r, _se)                         # (gdse=-1: none, for sound tests)
	g._gd_kill(r, _x)
	_kills += 1
	var ox := _x
	var oy := _y
	_place(act, sides, cv)
	_rest = REST
	if sides.size() > 1:
		_target = _rng.randi_range(0, 1)
		_switch = SWITCH
		_locked = false
	if _dbg:
		print("GD f%d KILL side %d rec %x at %.0f,%.0f (HP %d -> %d, action %x) -> warped to %.0f,%.0f, rest %d, hunting side %d" % [pf,
			_ld(r + 0x1A, 1), r, ox, oy, hp, _ld(r + 0x24A, 2, true), _ld(r + 6, 1), _x, _y, REST, _target])


## spawn / warp: off the picture and at least TELE_D world px from every hunted fighter, on the side with room (both:
## random); y near the players' height, kept between the stage top and the floor
func _place(act: Array, sides: Array, cv: Array) -> void:
	var xs: Array = []
	var ysum := 0.0
	for s in sides:
		var c := _centre(_hurtbox(act[s]))
		xs.append(c.x)
		ysum += c.y
	var lo: float = xs.min()
	var hi: float = xs.max()
	var z: float = maxf(cv[4], 0.05)
	var vleft: float = cv[0] + (0.0 - cv[2]) / z
	var vright: float = cv[0] + (256.0 - cv[2]) / z
	var right := maxf(hi + TELE_D, vright + VIEW_PAD + _w)
	var left := minf(lo - TELE_D, vleft - VIEW_PAD - _w)
	var pool: int = _ld(POOL, 4)
	var ok_r := true
	var ok_l := true
	if pool != 0 and _ld(pool + 0x4DE7, 1) != 0:     # bounded stage: fighters (and the 1-UP) stay in x0..x1
		var x0 := float(_ld(pool + 0x4DE8, 2, true)) + 16.0
		var x1 := float(_ld(pool + 0x4DEC, 2, true)) - 16.0
		ok_r = right <= x1
		ok_l = left >= x0
		if not ok_r and not ok_l:                    # no room on either side: the farther end of the stage
			_x = x0 if lo - x0 > x1 - hi else x1
		right = minf(right, x1)
		left = maxf(left, x0)
	if ok_r and ok_l:
		_x = right if _rng.randi_range(0, 1) == 1 else left
	elif ok_r:
		_x = right
	elif ok_l:
		_x = left
	var top := -INF
	if pool != 0:
		top = float(_ld(pool + 0x4DEA, 2, true)) + 24.0   # the stage's top bound (y0)
	_y = clampf(ysum / sides.size() + _rng.randf_range(-48.0, 48.0), top, _floor_y() - 24.0)


## the game moved every effect object by (dx, dy) (24.8 fixed): stage wrap-around / STAGE SHUFFLE
func shift(dx: int, dy: int) -> void:
	_x += dx / 256.0
	_y += dy / 256.0
	if _dbg and _on:
		print("GD f%d shifted by %.0f,%.0f with the stage -> %.0f,%.0f" % [g._port_frame(), dx / 256.0, dy / 256.0, _x, _y])


## after the game's sprite list (QoLGame._fx_draw); cv = [cam x, cam y, cam30, cam34, zoom]
func draw(cv: Array) -> bool:
	_cv_draw = cv                                   # the view as drawn (CAMERA ZOOM applies only while drawing)
	if not _on or not _ready or _hidden:
		return false
	var z: float = cv[4]
	if absf(z - 1.0) < 0.02:
		z = 1.0
	var out: Array = g.gx_cmds
	var floor_y := _floor_y()
	# shadow on the floor (smaller while the 1-UP is high), like the game's own fighter shadows
	var hgt := floor_y - (_y + _h * 0.5)
	var sc := maxf(0.25, clampf(1.0 - hgt / 240.0, 0.4, 1.0) * z)
	var sx: float = cv[2] + z * (_x - cv[0])
	var sy: float = cv[3] + z * (floor_y - cv[1])
	_mtx(out, 16.0 * sc, floorf(sx - SH_W * 0.5 * sc), floorf(sy - SH_H * 0.5 * sc), float(Z_SHADOW))
	out.append_array(_qs)
	# the 1-UP, bobbing 1 px every 16 running frames (drawing only)
	var bob := float((_t / 16) % 2)
	var tx := floorf(cv[2] + z * (_x - cv[0]) - _w * z * 0.5)
	var ty := floorf(cv[3] + z * (_y - bob - cv[1]) - _h * z * 0.5)
	_mtx(out, 16.0 * z, tx, ty, float(Z_DEMON))
	out.append_array(_qd)
	return true


## MTX_MODE position, MTX_PUSH, MTX_MULT_4x3 (scale s in x / y: a vertex unit of 1/16 = 1 px at s 16)
func _mtx(out: Array, s: float, tx: float, ty: float, tz: float) -> void:
	out.append([0x4000440, 2])
	out.append([0x4000444, 0])
	for v in [s, 0.0, 0.0, 0.0, s, 0.0, 0.0, 0.0, 1.0, tx, ty, tz]:
		out.append([0x4000464, int(roundf(v * 4096.0)) & 0xFFFFFFFF])


## one textured quad w x h px of the 16 x (8 << th) direct-colour texture at block offset `ofs`, then MTX_POP (same
## commands as qol_bombs.gd `_quad`; PLTT_BASE = `key` so smooth motion pairs it only with itself)
func _quad(ofs: int, th: int, pid: int, key: int, w: int, h: int) -> Array:
	var out: Array = []
	out.append([0x40004A8, ((TEX_OFS + ofs) >> 3) | (1 << 20) | (th << 23) | (7 << 26)])   # TEXIMAGE_PARAM: 16 x (8 << th), direct colour
	out.append([0x40004AC, key])                        # PLTT_BASE
	out.append([0x40004A4, ATTR | (pid << 24)])         # POLYGON_ATTR (applies at BEGIN)
	out.append([0x4000480, 0x7FFF])                     # COLOR white: modulation keeps the texels exact
	out.append([0x4000500, 1])                          # BEGIN quads
	var xs := [0, 0, w, w]
	var ys := [0, h, h, 0]
	for k in 4:
		out.append([0x4000488, (xs[k] * 16) | ((ys[k] * 16) << 16)])   # TEXCOORD (12.4 texels)
		var xy: int = ((xs[k] * 256) & 0xFFFF) | (((ys[k] * 256) & 0xFFFF) << 16)
		if k == 0:
			out.append([0x400048C, xy])                 # VTX_16 (z 0)
			out.append([0x400048C, 0])
		else:
			out.append([0x4000494, xy])                 # VTX_XY
	out.append([0x4000504, 0])                          # END
	out.append([0x4000448, 1])                          # MTX_POP
	for e in out:
		(e as Array).make_read_only()
	out.make_read_only()
	return out
