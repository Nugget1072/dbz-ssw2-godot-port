extends RefCounted
## HOT POTATO (part 40, cheat page 10 CHALLENGES; QoLSettings cheat "hot_potato", test flag `cheats=hot_potato`). Owned by
## QoLGame (`# ---- HOT POTATO (part 40)`), which calls tick() once per battle frame (its FUN_0202954C override), hit()
## for every fighter that loses HP inside the game's collision pass FUN_0201E5BC, draw() after the game's sprite list
## (_fx_draw) and reset() at every battle load. Nothing here runs with the cheat off.
## FIRST_WAIT running battle frames into the fight a lit bomb lands on a random side's active fighter: it sits on that
## fighter's head with a big countdown (seconds, the DAMAGE NUMBERS digits: white, yellow from 5, red and blinking from 3,
## popping bigger at each new second). Landing a hit that takes HP from the OTHER team's active fighter (a hit, a shot,
## an assist: anything of the holder's side in the collision pass) passes the bomb to that fighter (not back for
## PASS_COOL frames). At 0 it explodes on whoever holds it: the game's ki-blast explosion (common effect kind 1, size 2)
## + its big-explosion sound 0x2B, BOOM of max HP through FUN_020293A4 (the scale +0x1676 undone; guarding does not help;
## INFINITE HEALTH does), a push up and away + hit reaction 0x11 (the game's own KO follows when the HP is gone). REST
## frames later the next fuse is lit. Both teams; the fuse stops during pause / cut-ins, supers / Team Arts (camera mode
## != 0), tags, throws / grab sequences (+0x250 & 0x420), KO and outside the fight (battle state 7).
## Art: the user's walking bomb (assets_qol/bomb.png, BOMB RAIN's) in the port's shared texture block (qol_texblock.gd,
## the same bytes BOMB RAIN writes, so both can be on), drawn 1:1 as one textured quad (part 41; 1.5x before), sparks animated.
## LAN: own RNG seeded at every battle load (`hpseed`), battle RAM only: both machines agree.
## Debug: `hpdbg` (light / pass / boom lines), `hpseed=N`, `hpfuse=N` (frames), `hpwait=N`.
const SEED := 0x7A707
const FIRST_WAIT := 180                  ## running battle frames from the fight's start to the first fuse
const FUSE := 600                        ## 10 s
const REST := 240                        ## after a boom
const PASS_COOL := 40                    ## frames before the bomb can be passed again
const BOOM := 0.30                       ## of max HP
const EXPL_KIND := 1                     ## common effect kind 1: ki-blast explosion
const EXPL_ARG := 0x20008                ## FUN_0202216C: size 2 (~110 px)
const BOOM_SE := 0x2B                    ## the game's big explosion
const TEAMS := 0x020DE3D0
const CAMERA := 0x020DE3A4
const BATTLE_STATE := 0x020DD4C5
const TEX_OFS := 0x5F000                 ## qol_texblock.gd TEX_OFS (BOMB RAIN's frames at block offset 0)
const FRAMES := 6
const FR_BYTES := 0x200
const SH_OFS := FRAMES * FR_BYTES
const PID := 0x20                        ## polygon ID of the bomb
const KEY := 24                          ## its PLTT_BASE pairing key (bombs 0-12, demon 16-17)
const SCALE := 1.0                       ## part 41: 1:1 (1.5 made its pixels uneven; the user: "weirdly sized")
const HEAD := 43.0                       ## world px from the fighter's centre up to the bomb's centre

var g = null                             ## the QoLGame
var _rng := RandomNumberGenerator.new()
var _side := -1                          ## the side holding the bomb, -1 none
var _fuse := 0
var _wait := FIRST_WAIT
var _cool := 0
var _pop := 0                            ## frames of the countdown's pop (pass / new second)
var _age := 0                            ## running frames (spark animation)
var _last := -2
var _ready := false
var _w := 11
var _h := 12
var booms := 0
var passes := 0
var _dbg := Game.args.has("hpdbg")


func _init(game, img: Image) -> void:
	g = game
	_load_art(img)
	reset()


func reset() -> void:
	_rng.seed = int(Game.flag("hpseed", str(SEED)))
	_side = -1
	_fuse = 0
	_wait = int(Game.flag("hpwait", str(FIRST_WAIT)))
	_cool = 0
	_pop = 0
	_age = 0
	_last = -2
	_ready = false


## BOMB RAIN's conversion (qol_bombs.gd _load_art), byte for byte: the block holds the same texels whoever wrote them
func _load_art(img: Image) -> void:
	if img == null:
		return
	_w = img.get_width() / FRAMES
	_h = img.get_height()
	if _w > 16 or _h > 16 or img.get_width() != _w * FRAMES:
		return
	var tex := PackedByteArray()
	tex.resize(SH_OFS + 0x100)
	for f in FRAMES:
		for y in _h:
			for x in _w:
				var c := img.get_pixel(f * _w + x, y)
				if c.a >= 0.5:
					tex.encode_u16(f * FR_BYTES + (y * 16 + x) * 2, (int(c.r * 31.0 + 0.5) | (int(c.g * 31.0 + 0.5) << 5)
						| (int(c.b * 31.0 + 0.5) << 10)) | 0x8000)
	for r in [[4, 0, 8, 6], [1, 1, 14, 4], [0, 2, 16, 2]]:
		for y in range(r[1], r[1] + r[3]):
			for x in range(r[0], r[0] + r[2]):
				tex.encode_u16(SH_OFS + (y * 16 + x) * 2, 0x8000)
	g._tex_block().put(0, tex)


func _ld(a: int, n: int, s := false) -> int:
	return g._ld(a, n, s)


func _st(a: int, n: int, v: int) -> void:
	g._st(a, n, v)


## may the fuse burn this frame?
func _running() -> bool:
	if _ld(BATTLE_STATE, 1) != 7 or g.f_02012fd4() != 0:
		return false
	var cam: int = _ld(CAMERA, 4)
	if cam != 0 and _ld(cam, 2) != 0:
		return false
	var teams: int = _ld(TEAMS, 4)
	if _ld(teams + 0x11DC, 4) != 0:
		return false                                    # a tag runs
	for side in 2:
		var r: int = g.f_02027c00(side)
		if r == 0 or _ld(r + 0x24A, 2, true) <= 0 or _ld(r + 6, 1) == 0x33 or (_ld(r + 0x250, 4) & 0xC20) != 0:
			return false
	return true


func tick(pf: int) -> void:
	if pf == _last:
		return
	_last = pf
	_ready = g._tex_block().ok()
	if not _running():
		return
	_age += 1
	if _cool > 0:
		_cool -= 1
	if _pop > 0:
		_pop -= 1
	if _side < 0:
		_wait -= 1
		if _wait <= 0:
			_side = _rng.randi_range(0, 1)
			_fuse = int(Game.flag("hpfuse", str(FUSE)))
			_pop = 10
			if _dbg:
				print("HP f%d fuse lit on side %d" % [pf, _side])
		return
	_fuse -= 1
	if _fuse > 0 and _fuse % 60 == 0:
		_pop = 6                                        # a new second
	if _fuse <= 0:
		_boom(pf)


## a fighter lost HP inside the collision pass: a hit by the holder's side on the other side's active fighter passes it
func hit(v: int) -> void:
	if _side < 0 or _cool > 0:
		return
	var vs: int = _ld(v + 0x1A, 1) & 1
	if vs == _side or v != g.f_02027c00(vs):
		return
	_side = vs
	_cool = PASS_COOL
	_pop = 10
	passes += 1
	if _dbg:
		print("HP f%d passed to side %d (%d frames left)" % [g._port_frame(), vs, _fuse])


func _boom(pf: int) -> void:
	var r: int = g.f_02027c00(_side)
	var o: int = g.f_0202247c(r, EXPL_KIND)
	if o != 0:
		g.f_0202216c(o, EXPL_ARG, 0)
		_st(o + 0x3C, 4, (_ld(r + 0x3C, 4, true) - int(HEAD * 0.5 * 256.0)) & 0xFFFFFFFF)
	g.f_02029e3c(r, BOOM_SE)
	var mx: int = _ld(r + 0x24C, 2)
	var sc: int = _ld(_ld(TEAMS, 4) + 0x1676, 2)
	if sc > 0:
		var want: int = maxi(1, int(mx * BOOM))
		g.f_020293a4(r, (want * 256 + sc - 1) / sc, 0)
	var opp: int = g.f_02027bd0(_side)
	var away := 0x30 if opp == 0 or _ld(r + 0x38, 4, true) >= _ld(opp + 0x38, 4, true) else 0x50
	g.f_020213a8(r, 0x500, -0x40, 0, away)
	if _ld(r + 6, 1) != 0x33:
		_st(r + 0x250, 4, 0)
		_st(r + 0x25D, 1, _ld(r + 0x1A, 1))
		g.f_02021b4c(r, 0x11)
	_st(r + 0x25E, 2, 20)
	_st(r + 0x250, 4, _ld(r + 0x250, 4) | 2)
	booms += 1
	if _dbg:
		print("HP f%d BOOM on side %d: HP %d / %d" % [pf, _side, _ld(r + 0x24A, 2, true), mx])
	_side = -1
	_wait = REST


func any() -> bool:
	return _side >= 0


## after the game's sprite list: the bomb on the holder's head and the countdown above it
func draw(idx: Dictionary, cv: Array) -> bool:
	if _side < 0 or not _ready:
		return false
	var r: int = g.f_02027c00(_side)
	if r == 0 or not idx.has(r + 0x124) or _ld(r + 0x161, 1) == 0:
		return false
	var z: float = cv[4]
	var x := _ld(r + 0x38, 4, true) / 256.0
	var y := _ld(r + 0x3C, 4, true) / 256.0 - HEAD
	var secs := (_fuse + 59) / 60
	var ps := 2 if _pop > 0 else 1                     # part 41: one size smaller (was 2 / 3)
	var nh := 7 * ps + 2                                # the countdown's height (outline included)
	var sx := clampf(floorf(cv[2] + z * (x - cv[0])), 12.0, 244.0)
	var sy := floorf(cv[3] + z * (y - cv[1]))
	var top := sy - _h * SCALE * 0.5 - 2.0 - nh         # the group (number over bomb) stays below the HUD bars
	if top < 24.0:
		sy += 24.0 - top
	sy = minf(sy, 184.0 - _h * SCALE * 0.5)
	var blink := secs <= 3 and (_fuse / 5) % 2 == 0
	# the bomb: sparks frames 0-2 (feet still), 1:1, red-tinted while blinking
	var f := (_age / 3) % 3
	var s := 16.0 * SCALE
	var tx := floorf(sx - _w * SCALE * 0.5)            # whole pixels: crisp
	var ty := floorf(sy - _h * SCALE * 0.5)
	g.io_write(0x4000440, 4, 2)
	g.io_write(0x4000444, 4, 0)
	for v in [s, 0.0, 0.0, 0.0, s, 0.0, 0.0, 0.0, 1.0, tx, ty, 38.0]:
		g.io_write(0x4000464, 4, int(roundf(v * 4096.0)) & 0xFFFFFFFF)
	g.io_write(0x40004A8, 4, ((TEX_OFS + f * FR_BYTES) >> 3) | (1 << 20) | (1 << 23) | (7 << 26))
	g.io_write(0x40004AC, 4, KEY)
	g.io_write(0x40004A4, 4, 0x80C0 | (31 << 16) | (PID << 24))
	g.io_write(0x4000480, 4, 0x109F if blink else 0x7FFF)
	g.io_write(0x4000500, 4, 1)
	var xs := [0, 0, _w, _w]
	var ys := [0, _h, _h, 0]
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
	# the countdown (DAMAGE NUMBERS' digits): white, yellow from 5, red from 3; one size bigger as it pops
	if g._dn_glyphs.is_empty():
		g._dn_init()
	var digits := str(secs)
	var cols := [0x7FFF, 0x6718]
	if secs <= 3:
		cols = [0x191F, 0x0018]
	elif secs <= 5:
		cols = [0x23FF, 0x031F]
	var w := (digits.length() * 6 - 1) * ps
	var bst: int = _ld(BATTLE_STATE, 1)
	var mirror: bool = g.cheats.mirror_mode and _ld(0x027E0004, 4) == 0x02013030 and bst >= 4 and bst != 9
	var nx := clampf(sx, w * 0.5 + 2.0, 254.0 - w * 0.5)
	g._dn_k = 0x700 + ps * 16 + secs
	g._dn_emit(digits, ps, floorf(nx + w * 0.5) if mirror else floorf(nx - w * 0.5), floorf(ty - 2.0 - 7.0 * ps), mirror, cols[0], cols[1], 31)
	return true
