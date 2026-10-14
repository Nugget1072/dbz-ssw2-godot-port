extends RefCounted
## Z-VANISH (part 42, cheat page 9 POWERS; QoLSettings cheat "z_vanish", test flag `cheats=z_vanish`): the DBZ
## afterimage dodge. Owned by QoLGame (`# ---- Z-VANISH (part 42)`), which calls tick() for every active fighter once per
## battle frame (its FUN_0202954C override, before the fighter runs), draw() after the game's sprite list (_fx_draw)
## and reset() at every battle load. Nothing here runs with the cheat off. Research: DATA_NOTES part 42.
## A fighter in a hit stun (reactions 0xF-0x12; not the guard stagger 0xE, a knock-down 0x16, a KO 0x33 or a throw /
## grab 0x34-0x66) that presses B (a new press of the held bit +0x270, so presses during hit stop count) with at least
## COST ki (50 %) vanishes: the game's step-dash burst (common effect 6) and whoosh (SE 0x0C) where it was, it reappears
## DIST px behind its attacker (inside the stage walls, on the floor when the attacker stands, at its height when it
## flies), motion stopped (FUN_02021340), stun 0, neutral (5 / 0 through FUN_02021B4C), the attacker's combo window
## closed (+0x257: its RUSH starts over), and for IMM frames (until it acts) nothing can touch it (+0x250 |= 0x40: not
## registered for collision). A pale afterimage stays behind and fades. Not while the attacker runs a super / ultimate
## / Team Arts / throw / sequence, during supers' camera, pause or a cut-in.
## Player 1 (both players in multiplayer); the CPU vanishes too: CPU_PCT % of its hit stuns, 3-8 frames in (seeded).
## LAN: battle RAM, the synced held bits and the seeded RNG only.
## Debug: `zvdbg` (vanish / refused / immunity lines), `zvcpu=N` (CPU %), `zvauto` (player 1 vanishes whenever it may).

const STUN_ACTS := [0x0F, 0x10, 0x11, 0x12]
const FREE_ACTS := [0, 1, 2, 3, 4, 5, 6, 0x18]
const COST := 0x3200                     ## 50 %
const DIST := 40                         ## px behind the attacker
const IMM := 20                          ## frames untouchable (ends when the fighter acts)
const CPU_PCT := 30
const SE := 0x0C                         ## step-dash whoosh
const BURST := 6                         ## step-dash burst effect
const GHOST_T := 18                      ## picture frames of the afterimage
const TEAMS := 0x020DE3D0
const POOL := 0x020DE3CC
const CAM := 0x020DE3A4
const PID_GHOST := 0x3B                  ## polygon ID of the afterimage (AFTERIMAGES' range, rarely all in use)

var g = null                             ## the QoLGame
var _rng := RandomNumberGenerator.new()
var _prev := {}                          ## fighter -> held at its last tick
var _pact := {}                          ## fighter -> action at its last tick
var _imm := {}                           ## fighter -> frames left
var _cpu_at := {}                        ## fighter -> battle frames until the CPU vanishes
var _ghosts: Array = []                  ## [fighter, world x, world y, age]
var vanishes := 0
var _dbg := Game.args.has("zvdbg")
var _auto := Game.args.has("zvauto")
var _cpu := int(Game.flag("zvcpu", str(CPU_PCT)))


func _init(game) -> void:
	g = game
	reset()


func reset() -> void:
	_rng.seed = int(Game.flag("zvseed", "0x2A715"))
	_prev.clear()
	_pact.clear()
	_imm.clear()
	_cpu_at.clear()
	_ghosts.clear()


func _ld(a: int, n: int, s := false) -> int:
	return g._ld(a, n, s)


func _st(a: int, n: int, v: int) -> void:
	g._st(a, n, v)


## once per battle frame for an active fighter, before its FUN_0202954C
func tick(f: int) -> void:
	var side: int = _ld(f + 0x1A, 1) & 1
	if f != g.f_02027c00(side):
		return
	var held: int = _ld(f + 0x270, 2)
	var prev: int = _prev.get(f, 0xFFFF)
	_prev[f] = held
	var act: int = _ld(f + 6, 1)
	var pact: int = _pact.get(f, -1)
	_pact[f] = act
	var human: bool = g._helped(f)
	if not human and _cpu > 0 and act in STUN_ACTS and not (pact in STUN_ACTS) and _rng.randi_range(1, 100) <= _cpu:
		_cpu_at[f] = _rng.randi_range(3, 8)             # a CPU hit stun it will vanish from
	if _imm.has(f):                                     # the untouchable frames (the game clears +0x250 on most changes)
		_imm[f] -= 1
		var v: int = _ld(f + 0x250, 4)
		if _imm[f] <= 0 or not act in FREE_ACTS:
			_st(f + 0x250, 4, v & ~0x40)
			_imm.erase(f)
			if _dbg:
				print("ZV f%d fighter %x touchable again (act %x)" % [g._port_frame(), f, act])
		else:
			_st(f + 0x250, 4, v | 0x40)
	var want := false
	if human:
		want = (held & 2) != 0 and (prev & 2) == 0
		if _auto and side == 0:
			want = true
	if _cpu_at.has(f):
		if not (act in STUN_ACTS):
			_cpu_at.erase(f)
		else:
			_cpu_at[f] -= 1
			if _cpu_at[f] <= 0:
				_cpu_at.erase(f)
				want = true
	if not want or not (act in STUN_ACTS):
		return
	var why := _blocked(f, side)
	if why != "":
		if _dbg and not _auto:
			print("ZV f%d fighter %x refused: %s" % [g._port_frame(), f, why])
		return
	_vanish(f, side)


func _blocked(f: int, side: int) -> String:
	if _ld(f + 0x24A, 2, true) <= 0:
		return "no HP"
	if g.f_02012fd4() != 0:
		return "pause / cut-in"
	if (_ld(f + 0x250, 4) & 0xC00) != 0:
		return "sequence / frozen"
	var cam: int = _ld(CAM, 4)
	if cam == 0 or _ld(cam, 2) != 0:
		return "camera"
	if _ld(_ld(TEAMS, 4) + side * 0x8E8 + 0x8D0, 2) < COST:
		return "ki"
	var a: int = g.f_02027bd0(side)
	if a == 0 or _ld(a + 0x24A, 2, true) <= 0:
		return "no attacker"
	var aa: int = _ld(a + 6, 1)
	if aa == 0x33 or (aa >= 0x26 and aa <= 0x30) or (aa >= 0x34 and aa <= 0x66) or aa >= 0x85:
		return "attacker act %x" % aa
	if (_ld(a + 0x250, 4) & 0x20C00) != 0:
		return "attacker in a sequence"
	return ""


func _vanish(f: int, side: int) -> void:
	vanishes += 1
	var a: int = g.f_02027bd0(side)
	var pool: int = _ld(POOL, 4)
	_ghosts.append([f, _ld(f + 0x38, 4, true) / 256.0, _ld(f + 0x3C, 4, true) / 256.0, 0])
	g.f_0202247c(f, BURST)                               # the puff where it was
	g.f_02027950(f, COST, 1)                             # 50 %, unscaled (INFINITE KI: free)
	var ax: int = _ld(a + 0x38, 4, true) >> 8
	var ay: int = _ld(a + 0x3C, 4, true)
	var vx: int = _ld(f + 0x38, 4, true) >> 8
	var fa: int = _ld(a + 7, 1)
	var dirx: int = 1 if (fa > 0x40 and fa < 0xC0) else -1   # (the attacker faces left: behind = right)
	if vx != ax:
		dirx = 1 if vx < ax else -1                     # the far side from where the victim was
	var tx: int = ax + dirx * DIST
	if (_ld(pool + 0x4DE7, 1) & 1) != 0:                # a stage with walls
		var lw: int = _ld(pool + 0x4DE8, 2, true)
		var rw: int = _ld(pool + 0x4DEC, 2, true)
		var cx: int = clampi(tx, lw + 8, rw - 8)
		if absi(cx - ax) < 24:
			cx = clampi(ax - dirx * DIST, lw + 8, rw - 8)    # pinned at the wall: the near side
		tx = cx
	var flo: int = _ld(pool + 0x4DEE, 2, true)
	var ceil_y: int = _ld(pool + 0x4DEA, 2, true)
	var feet: int = _ld(f + 0x24F, 1)
	var ground: bool = (_ld(a + 0x10, 2) & 1) != 0
	var ty: int
	if ground:
		ty = (flo + feet) << 8
	else:
		ty = clampi(ay, (ceil_y + 4) << 8, (flo + feet - 1) << 8)
	g.f_02021340(f)                                      # motion stopped (speed, velocity, target, accel)
	_st(f + 0x38, 4, (tx << 8) & 0xFFFFFFFF)
	_st(f + 0x3C, 4, ty & 0xFFFFFFFF)
	_st(f + 0x25E, 2, 0)
	var flags: int = _ld(f + 0x10, 2)
	_st(f + 0x10, 2, (flags | 1) if ground else (flags & ~1))
	_st(f + 0x250, 4, 0)
	_st(f + 0x25D, 1, side)
	g.f_02021b4c(f, 5 if ground else 0)
	_st(f + 0x250, 4, 0x40)                              # not registered for collision
	_imm[f] = IMM
	_st(a + 0x257, 1, 0)                                 # the attacker's combo window closed (RUSH restarts)
	g.f_02029e3c(f, SE)
	g.f_0202247c(f, BURST)                               # the puff where it appears
	if _dbg:
		print("ZV f%d VANISH fighter %x side %d -> x%d y%d behind %x (ki left %x)" % [g._port_frame(), f, side, tx, ty >> 8, a,
			_ld(_ld(TEAMS, 4) + side * 0x8E8 + 0x8D0, 2)])


func any_fx() -> bool:
	return not _ghosts.is_empty()


## the afterimages: a pale copy of the fighter's sprite where it vanished, fading
func draw(idx: Dictionary, cv: Array) -> bool:
	if _ghosts.is_empty():
		return false
	var run: bool = g.f_02012fd4() == 0
	var g8: int = g._ld(g._ld(g.SPR_LIST, 4, false) + 0x184, 4, true)
	var z: float = cv[4]
	var keep: Array = []
	var drew := false
	for e in _ghosts:
		var f: int = e[0]
		var p := f + 0x124
		var age: int = e[3]
		if idx.has(p) and _ld(p, 4) != 0 and _ld(p + 0x3D, 1) != 0:
			var dx: float = z * (float(e[1]) - _ld(f + 0x38, 4, true) / 256.0)
			var dy: float = z * (float(e[2]) - _ld(f + 0x3C, 4, true) / 256.0)
			var al := clampi(int(16.0 * (1.0 - age / float(GHOST_T))), 1, 16)
			g._spr_copy(p, g8, 1.0, 1.0, floorf(dx), floorf(dy), 2, al, PID_GHOST, 0x7F7A)   # pale blue-white
			drew = true
		if run:
			e[3] = age + 1
		if int(e[3]) < GHOST_T:
			keep.append(e)
	_ghosts = keep
	return drew
