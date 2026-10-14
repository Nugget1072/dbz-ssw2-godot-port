extends RefCounted
## TIME SKIP (part 41, cheat page 9 POWERS; QoLSettings cheat "time_skip", test flag `cheats=time_skip`), after Hit's
## Time Skip (and ZA WARUDO). Owned by QoLGame (`# ---- TIME SKIP (part 41)`); nothing here runs with the cheat off.
## SELECT (unused in battle, DATA_NOTES part 41) with at least COST ki (100 %) in a free moment (neutral / moving /
## guarding / charging / attacking, not in hit stun, a throw, a super or a sequence) spends COST and stops the
## ENEMY's time for SKIP_T running battle frames: its active fighter, its support on screen and every object of its
## side that exists at that moment stand still, while the skipper moves, hits and shoots freely. Player 1 (both
## players in multiplayer); the CPU does it too (seeded chance while it has the ki and is close, `_cpu`).
## The freeze (DATA_NOTES part 41 "per-fighter freeze"):
## - the frozen fighter's FUN_0202954C is not run (QoLGame.f_0202954c -> freeze_step): only its contact flags +0xC
##   cleared, previous position = position, its hurt box registered (FUN_0201DEE0: it stays hittable) and its hit
##   handler +0x34 = the no-op 0x02020EC4: pose, action, animation, timers and input stand still. Hits land at once
##   (damage, hit stop, sparks); the reaction / push they set waits and the last one plays when time runs again;
## - its side's objects: obj +4 |= 4 (the game's own per-object freeze, as its super cut-ins do) around the effect loop
##   FUN_02021F54 every frame, for the objects listed at the start (owner kept as identity), cleared after;
## - the body push FUN_0201E224 and the camera tether FUN_02019594 cannot move it (its position restored, the other
##   fighter takes the whole displacement);
## - its support on screen (FUN_020294B8) is only drawn;
## - guarding (+0x250 & 9) is dropped at the start: the skip leaves it open.
## Time runs again after SKIP_T frames, or at once when the frozen fighter is KO'd, a grab / throw takes it (victim
## states 0x34-0x66), the skipper starts a throw / super / ultimate / Team Arts (0x2A-0x30), is hit or KO'd, a tag or
## a cut-in starts, or the fight stops (battle state 7). Then COOL frames before that side may skip again.
## Looks: the picture turns violet-grey (a translucent quad over the 3D picture) while the skipper is drawn again on
## top in its own colours (depth: the copy is nearer than the tint); a white ring bursts out of the skipper at the
## start and closes in at the end; SE START_SE / END_SE.
## LAN: battle RAM + the seeded CPU RNG (`tsseed`) only, counted in battle frames: both machines agree.
## Debug: `tsdbg` (start / end lines), `tscpu=N` (CPU chance 1 / N per frame, 0 = never), `tsauto=F` (player 1 skips once, at
## the first battle frame from F on where it may: tests).

const COST := 0x6400                     ## 100 % (team block +0x8D0; 200 % = 0xC800)
const SKIP_T := 120                      ## running battle frames (~2 s)
const COOL := 180                        ## frames before the same side may skip again
const CPU_CHANCE := 300                  ## the CPU tries with 1 / CPU_CHANCE per frame when it may
const CPU_NEAR := 150                    ## world px: the CPU only skips this close to its enemy
const SELECT := 4                        ## DS key bit
const NOOP_HIT := 0x02020EC4
const TEAMS := 0x020DE3D0
const CAMERA := 0x020DE3A4
const BATTLE_STATE := 0x020DD4C5
const START_SE := 0x05
const END_SE := 0x21
const TINT := 0x4505                     ## (5, 8, 17): violet-grey
const TINT_AL := 13
const PID_TINT := 0x2B                   ## polygon IDs (port effects 0x28-0x3F)
const PID_COPY := 0x2C                   ## the skipper's copy
const PID_STONE := 0x2D                  ## the frozen fighter's grey copy
const PID_RING := 0x3C                   ## ring dots (rim / core: different IDs, so the core draws over the rim)
const PID_RING2 := 0x3D
const PAL_RAM := 0x027C01A0              ## port-only RAM: 32 bytes (DRAGON BALL HUNT 0x160-0x19F)
const STONE := [0, 0x1084, 0x18C6, 0x2108, 0x294A, 0x2D6B, 0x318C, 0x35AD, 0x39CE, 0x3DEF, 0x4210, 0x4631, 0x4A52,
	0x4E73, 0x5294, 0x5AD6]               ## dark -> light grey (BGR555)
const FXK_TS := 0x0E80                   ## PLTT_BASE pairing keys of the ring / tint quads
const OPEN_ACTS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xA, 0xB, 0xC, 0xD, 0x18, 0x19, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21,
	0x22, 0x23, 0x24]                    ## neutral / moves / dashes / charging / guard / melee / dash attack / shots

var g = null                             ## the QoLGame
var _rng := RandomNumberGenerator.new()
var side := -1                           ## the frozen side, -1 = time runs
var skipper := 0                         ## the skipper's record
var _left := 0                           ## frames of the skip left
var _cool := [0, 0]
var _held := {}                          ## fighter -> its Select bit last frame (edge detection on +0x270)
var _objs: Array = []                    ## [object, owner] frozen at the start
var _set: Array = []                     ## objects whose +4 bit 4 this frame was set by us
var _last := -2
var _fx: Array = []                      ## [kind 1 start / 2 end, age, world x, world y]
var _tint_age := -1                      ## picture frames since the start (-1 none)
var _pal := -1                           ## the grey palette's VRAM byte offset, -2 refused
var skips := 0
var _dbg := Game.args.has("tsdbg")
var _cpu := int(Game.flag("tscpu", str(CPU_CHANCE)))
var _auto := int(Game.flag("tsauto", "-1"))


func _init(game) -> void:
	g = game
	reset()


func reset() -> void:
	_rng.seed = int(Game.flag("tsseed", "0x75C1F"))
	side = -1
	skipper = 0
	_left = 0
	_cool = [0, 0]
	_held.clear()
	_objs.clear()
	_set.clear()
	_last = -2
	_fx.clear()
	_tint_age = -1
	_pal = -1


func _ld(a: int, n: int, s := false) -> int:
	return g._ld(a, n, s)


func _st(a: int, n: int, v: int) -> void:
	g._st(a, n, v)


func active() -> bool:
	return side >= 0


## is record f frozen this frame? (the active fighter or the support on screen of the frozen side)
func frozen(f: int) -> bool:
	return side >= 0 and f != 0 and (_ld(f + 0x1A, 1) & 1) == side


## once per battle frame (from QoLGame.f_0202954c, before any fighter runs): triggers, countdown, end conditions
func tick(pf: int) -> void:
	if pf == _last:
		return
	_last = pf
	for s in 2:
		if _cool[s] > 0:
			_cool[s] -= 1
	var fight: bool = _ld(BATTLE_STATE, 1) == 7 and g.f_02012fd4() == 0
	if side >= 0:
		var why := _end_reason(fight)
		if why != "":
			_stop(pf, why)
		else:
			_left -= 1
	for s in 2:                                          # Select edges of the human sides
		var f: int = g.f_02027c00(s)
		if f == 0:
			continue
		var sel: int = _ld(f + 0x270, 2) & SELECT
		var was: int = _held.get(f, SELECT)             # (held at the first look: no edge)
		_held[f] = sel
		if not g._helped(f):
			continue
		if sel != 0 and was == 0:
			_try(f, s, pf, "select")
		elif s == 0 and _auto >= 0 and pf >= _auto and side < 0:
			_try(f, s, pf, "auto")
			if side >= 0:
				_auto = -1                              # (once)
	if side < 0 and fight and _cpu > 0 and not g._mp_on():   # the CPU side (never a human: MP / LAN have none)
		var c: int = g.f_02027c00(1)
		if c != 0 and not g._helped(c) and _ld(_ld(TEAMS, 4) + 0x8E8 + 0x8D0, 2) >= COST and _cool[1] == 0:
			var o: int = g.f_02027c00(0)
			if o != 0 and absi((_ld(c + 0x38, 4, true) - _ld(o + 0x38, 4, true)) >> 8) < CPU_NEAR \
					and absi((_ld(c + 0x3C, 4, true) - _ld(o + 0x3C, 4, true)) >> 8) < CPU_NEAR \
					and _rng.randi_range(1, _cpu) == 1:
				_try(c, 1, pf, "cpu")


func _end_reason(fight: bool) -> String:
	if _left <= 0:
		return "time"
	if not fight or _ld(BATTLE_STATE, 1) != 7:
		return "fight stopped"
	var cam: int = _ld(CAMERA, 4)
	if cam != 0 and _ld(cam, 2) != 0:
		return "camera"
	if _ld(_ld(TEAMS, 4) + 0x11DC, 4) != 0:
		return "tag"
	var v: int = g.f_02027c00(side)
	if v == 0 or _ld(v + 0x24A, 2, true) <= 0:
		return "KO"
	var va: int = _ld(v + 6, 1)
	if va >= 0x34 and va <= 0x66:
		return "grabbed"
	if skipper != g.f_02027c00(1 - side) or _ld(skipper + 0x24A, 2, true) <= 0:
		return "skipper gone"
	var a: int = _ld(skipper + 6, 1)
	if (a >= 0x2A and a <= 0x30) or a == 0x33 or (a >= 0x0E and a <= 0x12):
		return "skipper action %x" % a
	return ""


func _try(f: int, s: int, pf: int, how: String) -> void:
	if side >= 0 or _cool[s] > 0 or _ld(BATTLE_STATE, 1) != 7 or g.f_02012fd4() != 0:
		return
	var cam: int = _ld(CAMERA, 4)
	if cam == 0 or _ld(cam, 2) != 0 or _ld(_ld(TEAMS, 4) + 0x11DC, 4) != 0:
		return
	var tb: int = _ld(TEAMS, 4) + s * 0x8E8
	if _ld(tb + 0x8D0, 2) < COST or _ld(f + 0x24A, 2, true) <= 0 or not (_ld(f + 6, 1) in OPEN_ACTS) \
			or (_ld(f + 0x250, 4) & 0xC20) != 0:
		if _dbg and how != "auto":
			print("TS f%d side %d %s refused: ki %x act %x" % [pf, s, how, _ld(tb + 0x8D0, 2), _ld(f + 6, 1)])
		return
	var v: int = g.f_02027c00(1 - s)
	if v == 0 or _ld(v + 0x24A, 2, true) <= 0 or _ld(v + 6, 1) == 0x33:
		return
	g.f_02027950(f, COST, 1)                           # (INFINITE KI: free)
	side = 1 - s
	skipper = f
	_left = SKIP_T
	skips += 1
	_st(v + 0x250, 4, _ld(v + 0x250, 4) & ~9)         # no guard during the skip
	_objs.clear()
	var pool: int = _ld(0x020DE3CC, 4)
	for i in 48:
		var o := pool + i * 0x164
		if (_ld(o + 4, 1) & 1) != 0 and (_ld(o + 0x1A, 1) & 1) == side:
			_objs.append([o, _ld(o, 4)])
	g.f_02029e3c(f, START_SE)
	_fx.append([1, 0, _ld(f + 0x38, 4, true) / 256.0, _ld(f + 0x3C, 4, true) / 256.0 - 12.0])
	_tint_age = 0
	if _dbg:
		print("TS f%d side %d skips time (%s): side %d frozen, %d objects, ki left %x" % [pf, s, how, side, _objs.size(),
			_ld(tb + 0x8D0, 2)])


func _stop(pf: int, why: String) -> void:
	var s := 1 - side
	_cool[s] = COOL
	if skipper != 0:
		g.f_02029e3c(skipper, END_SE)
		_fx.append([2, 0, _ld(skipper + 0x38, 4, true) / 256.0, _ld(skipper + 0x3C, 4, true) / 256.0 - 12.0])
	if _dbg:
		var v: int = g.f_02027c00(side)
		print("TS f%d time runs again (%s, %d frames early): side %d HP %d" % [pf, why, maxi(_left, 0), side,
			_ld(v + 0x24A, 2, true) if v != 0 else 0])
	side = -1
	skipper = 0
	_left = 0
	_objs.clear()
	_tint_age = -1


## the frozen fighter's frame instead of FUN_0202954C: hittable, nothing else (DATA_NOTES part 41)
func freeze_step(f: int) -> void:
	_st(f + 0xC, 2, 0)
	_st(f + 0x288, 4, _ld(f + 0x38, 4))
	_st(f + 0x28C, 4, _ld(f + 0x3C, 4))
	if (_ld(f + 0x250, 4) & 0x40) == 0:
		g.f_0201dee0(f)
	_st(f + 0x34, 4, NOOP_HIT)


## around the effect loop FUN_02021F54: the frozen side's objects get the game's freeze bit for this frame
func objects_before() -> void:
	_set.clear()
	var keep: Array = []
	for e in _objs:
		var o: int = e[0]
		if (_ld(o + 4, 1) & 1) == 0 or _ld(o, 4) != e[1]:
			continue                                    # gone (or the slot reused)
		keep.append(e)
		if (_ld(o + 4, 1) & 4) == 0:
			_st(o + 4, 1, _ld(o + 4, 1) | 4)
			_set.append(o)
	_objs = keep


func objects_after() -> void:
	for o in _set:
		_st(o + 4, 1, _ld(o + 4, 1) & ~4)
	_set.clear()


## around a function that may move both active fighters (body push, tether): the frozen one is a wall
func hold_before() -> Array:
	var v: int = g.f_02027c00(side)
	var m: int = g.f_02027c00(1 - side)
	return [v, m, _ld(v + 0x38, 4, true), _ld(v + 0x3C, 4, true)]


func hold_after(h: Array) -> void:
	var v: int = h[0]
	var m: int = h[1]
	var dx: int = _ld(v + 0x38, 4, true) - int(h[2])
	var dy: int = _ld(v + 0x3C, 4, true) - int(h[3])
	if dx == 0 and dy == 0:
		return
	_st(v + 0x38, 4, int(h[2]) & 0xFFFFFFFF)
	_st(v + 0x3C, 4, int(h[3]) & 0xFFFFFFFF)
	if m != 0:
		_st(m + 0x38, 4, (_ld(m + 0x38, 4, true) - dx) & 0xFFFFFFFF)
		_st(m + 0x3C, 4, (_ld(m + 0x3C, 4, true) - dy) & 0xFFFFFFFF)


# ---- drawing ----------------------------------------------------------------------------------------------------------
func any_fx() -> bool:
	return side >= 0 or not _fx.is_empty()


## after the game's sprite list (QoLGame._fx_draw)
func draw(idx: Dictionary, cv: Array) -> bool:
	if not any_fx():
		return false
	var run: bool = g.f_02012fd4() == 0
	var z: float = cv[4]
	var drew := false
	if side >= 0 and skipper != 0:
		var t := _tint_age
		var al := clampi(TINT_AL * mini(t + 1, 8) / 8, 1, TINT_AL)
		if _left < 20:
			al = clampi(TINT_AL * _left / 20, 1, TINT_AL)     # fades out over the last 20 frames
		g._fx_box(0.0, 0.0, 256, 192, TINT, 0x80C0 | (al << 16) | (PID_TINT << 24), 34, FXK_TS)
		var v: int = g.f_02027c00(side)                   # the frozen fighter turns stone grey
		var q: int = v + 0x124 if v != 0 else 0
		if _pal == -1:
			for i in 16:
				_st(PAL_RAM + i * 2, 2, STONE[i])
			var s: int = g.f_02010b6c(PAL_RAM, 0x20)
			_pal = s if s != 0xFFFF else -2
		if q != 0 and _pal >= 0 and idx.has(q) and _ld(q, 4) != 0 and _ld(q + 0x3D, 1) != 0 and _ld(q + 0xC, 4, true) == 3:
			var g9: int = g._ld(g._ld(g.SPR_LIST, 4, false) + 0x184, 4, true)
			g._spr_copy(q, g9, 1.0, 1.0, 0, 0, _ld(q + 0x3C, 1) + 1, mini(al * 2 + 4, 30), PID_STONE, 0x7FFF, _pal)
		var p: int = skipper + 0x124
		if idx.has(p) and _ld(p, 4) != 0 and _ld(p + 0x3D, 1) != 0:
			var g8: int = g._ld(g._ld(g.SPR_LIST, 4, false) + 0x184, 4, true)
			g._spr_copy(p, g8, 1.0, 1.0, 0, 0, 35, 31, PID_COPY)   # the skipper in its own colours, over the tint
		if run:
			_tint_age += 1
		drew = true
	var keep: Array = []
	for e in _fx:
		var age: int = e[1]
		var u := age / 18.0
		var sx: float = cv[2] + z * (float(e[2]) - cv[0])
		var sy: float = cv[3] + z * (float(e[3]) - cv[1])
		var rr := (6.0 + 90.0 * sqrt(u)) if e[0] == 1 else (70.0 * (1.0 - u) + 4.0)
		var al := clampi(int(28.0 * (1.0 - u * u)), 1, 31)
		for i in 24:                                    # a ring of dots: violet rim, white core (seen on snow and sky)
			var ang := TAU * i / 24.0
			var px := floorf(sx + cos(ang) * rr)
			var py := floorf(sy + sin(ang) * rr * 0.85)
			g._fx_box(px - 2.0, py - 2.0, 4, 4, 0x4C49, 0x80C0 | (al << 16) | (PID_RING << 24), 37, FXK_TS + 1 + i * 2)
			g._fx_box(px - 1.0, py - 1.0, 2, 2, 0x7FFF if i % 2 == 0 else 0x7EF7, 0x80C0 | (al << 16) | (PID_RING2 << 24), 38, FXK_TS + 2 + i * 2)
		drew = true
		if run:
			age += 1
		if age < 18:
			e[1] = age
			keep.append(e)
	_fx = keep
	return drew
