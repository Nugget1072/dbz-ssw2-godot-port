extends RefCounted
## ULTRA INSTINCT (part 39, cheat page 10 POWERS since part 41 (page 5 FIGHTING before); QoLSettings cheat "ultra_instinct", test flag
## `cheats=ultra_instinct`): a parry after Super Smash Bros. Ultimate / Street Fighter III: 3rd Strike. Owned by
## QoLGame (`# ---- ULTRA INSTINCT (part 39)`), which calls tick() for player 1's active fighter once per battle frame
## (both players' in local / LAN multiplayer: QoLGame._helped), before() / after() around the game's collision pass
## FUN_0201E5BC, draw() after the game's sprite list (_fx_draw) and reset() at every battle load. Nothing here runs
## with the cheat off.
## A fresh B press (the guard button) in neutral / moving / guarding opens a WINDOW of 5 collision passes (5 frames,
## like Smash Ultimate's parry). An enemy attack box touching the fighter's hurt box in that window is PARRIED: the
## fighter is left out of that collision pass (fighter +4 = 0 while FUN_0201E5BC runs, so no hit handler runs for
## it: no damage, no hit stun, no guard push), and then:
## - a melee attacker (the opponent's active fighter, not in a super / throw / sequence) is stunned: hit reaction 0x11
##   with stun STUN frames, pushed away a little (like the game's dash-attack hit, FUN_02027C2C);
## - a ki blast (plain projectile, handler 0x020209E0) is sent back the way the game's own dash attack reflects one
##   (FUN_02027C2C's non-fighter branch: velocities negated, side / direction flipped);
## - any other shot (beams, super parts) is ignored for its whole life (IGNORE frames at most);
## - the battle freezes STOP frames (the game's hit stop FUN_02012F9C, like SF3's parry freeze), the game's guard spark
##   (common effect 0xB) appears at the contact point, SE `uise` plays (default PARRY_SE) and the fighter gets a
##   silver "Ultra Instinct" flash (port drawing: expanding light copies of its sprite + a ring of sparkles);
## - IMMUNE frames of immunity follow (the rest of a multi-hit attack).
## A B TAP (released within TAP frames) whose window parried nothing is a MISS: a red flicker on the fighter and no
## new window for LOCK frames. Holding B is a normal guard (no miss).
## LAN: only battle RAM + the game's functions decide anything (no RNG); drawing reads the game's camera.
## Debug: `uidbg` (window / parry / miss lines), `uiauto` (every pass is a window: parries every hit on player 1, for
## captures), `uise=N` (parry sound, -1 none). DATA_NOTES "part 39 findings".

const WINDOW := 5                        ## collision passes a B press keeps the parry window open
const TAP := 12                          ## a B released within this many frames of the press is a tap (a parry try)
const LOCK := 30                         ## frames without a new window after a miss
const IMMUNE := 20                       ## frames every hit is ignored after a parry
const IGNORE := 180                      ## a parried non-reflectable shot is ignored at most this long
const STUN := 30                         ## the parried attacker's stun (+0x25E) in reaction 0x11
const STOP := 12                         ## hit stop frames (the game uses 2 / 3 / 8)
const PARRY_SE := 0x21                   ## FUN_02029E3C sound: the tag-in "shing" (part 39 choice, DATA_NOTES; `uise`)
const SPARK_KIND := 0xB                  ## common effect: the game's guard spark (FUN_02027C2C guard branch)
const OPEN_ACTS := [0, 1, 2, 3, 4, 5, 6, 0x0E, 0x18]   ## neutral / move / walk, guard reaction, guard
const NOOP_HIT := 0x02020EC4             ## a fighter's hit handler when it has no attack (set every frame)
const NO_DAMAGE_HIT := 0x0201F74C
const MELEE_HIT := 0x02027C2C
const BLAST := 0x020209E0                ## plain projectile per-frame handler (ki blasts)
const TEAMS := 0x020DE3D0
const COLL := 0x020DE3C0                 ## u32 -> collision list: u8 count, u8 skip, +0x24 u32 objects[]
const POOL := 0x020DE3CC
const FX_T := 40                         ## picture frames of the parry flash (the first STOP + 2: silver fighter)
const MISS_T := 20                       ## picture frames of the miss flicker
const TINT_UI := 0x7F98                  ## (24, 28, 31): silver-blue (modulation tint of the copies)
const TINT_MISS := 0x0C3F                ## (31, 1, 3): red
const PID_UI := 0x3E                     ## polygon IDs of the copies (afterimages use 0x30-0x3D)
const PID_MISS := 0x3F
const FXK_UI := 0x0B00                   ## PLTT_BASE pairing keys of the sparkle quads (QoLGame FXK_* list)
const RING := 12                         ## sparkles in the ring

var g = null                             ## the QoLGame
var _win := {}                           ## fighter -> {"t": frames since the press, "pass": passes left, "rel": B let go, "hit": parried}
var _imm := {}                           ## fighter -> frames of immunity left
var _lock := {}                          ## fighter -> frames until a new window may open
var _ign := {}                           ## shot object -> [fighter, frames left]
var _hidden: Array = []                  ## [fighter, its +4] left out of the current collision pass
var _events: Array = []                  ## [fighter, attackers, contact x, contact y] found by before()
var _fx: Array = []                      ## [fighter, 1 parry / 2 miss, age, world x, world y]
var _gen := 0                            ## effect generation (sparkle pairing keys)
var parries := 0                         ## (debug / tests)
var misses := 0
var _dbg := Game.args.has("uidbg")
var _auto := Game.args.has("uiauto")
var _se := int(Game.flag("uise", str(PARRY_SE)))


func _init(game) -> void:
	g = game


func reset() -> void:
	_win.clear()
	_imm.clear()
	_lock.clear()
	_ign.clear()
	_hidden.clear()
	_events.clear()
	_fx.clear()
	_pal = -1                                       # the scene's palette list starts over


func _ld(a: int, n: int, s := false) -> int:
	return g._ld(a, n, s)


func _st(a: int, n: int, v: int) -> void:
	g._st(a, n, v)


## once per battle frame for a helped active fighter (before its action handler: this frame's B press is in +0x26C)
func tick(f: int) -> void:
	_alloc_pal()
	for d in [_imm, _lock]:
		if d.has(f):
			d[f] -= 1
			if d[f] <= 0:
				d.erase(f)
	var held: int = _ld(f + 0x270, 2)
	if _dbg and (_ld(f + 0x26C, 2) & 2) != 0:
		print("UI f%d B pressed: fighter %x act %x locked %s window %s" % [g._port_frame(), f, _ld(f + 6, 1), _lock.has(f), str(_win.get(f, {}))])
	var w: Dictionary = _win.get(f, {})
	if not w.is_empty():
		w["t"] += 1
		if (held & 2) == 0:
			w["rel"] = true
		if w["hit"]:
			if w["pass"] <= 0:
				_win.erase(f)
		elif w["pass"] <= 0:
			if w["rel"] and w["t"] <= TAP + 1:
				_miss(f)
				_win.erase(f)
			elif w["t"] > TAP:
				_win.erase(f)                           # held: a normal guard
	if (_ld(f + 0x26C, 2) & 2) != 0 and not _lock.has(f) and (not _win.has(f) or _win[f]["hit"]) \
			and _ld(f + 6, 1) in OPEN_ACTS and _ld(f + 0x24A, 2, true) > 0:
		_win[f] = {"t": 0, "pass": WINDOW, "rel": false, "hit": false}
		if _dbg:
			print("UI f%d window opens: fighter %x act %x" % [g._port_frame(), f, _ld(f + 6, 1)])


func _miss(f: int) -> void:
	misses += 1
	_lock[f] = LOCK
	_fx.append([f, 2, 0, _ld(f + 0x38, 4, true) / 256.0, _ld(f + 0x3C, 4, true) / 256.0 - 16.0])
	if _dbg:
		print("UI f%d MISS fighter %x (locked %d frames)" % [g._port_frame(), f, LOCK])


## anything to do in this collision pass?
func busy() -> bool:
	return _auto or not _win.is_empty() or not _imm.is_empty() or not _ign.is_empty()


## before FUN_0201E5BC: which helped fighters an enemy attack box touches; those in a window parry, those immune
## (or touched only by ignored shots) are left out of the pass
func before() -> void:
	_hidden.clear()
	_events.clear()
	for o in _ign.keys():
		_ign[o][1] -= 1
		if _ign[o][1] <= 0 or (_ld(o + 4, 1) & 1) == 0:
			_ign.erase(o)
	var lst: int = _ld(COLL, 4)
	if lst == 0 or _ld(lst + 1, 1) != 0:
		return
	var n: int = _ld(lst, 1)
	var objs: Array = []
	for i in n:
		objs.append(_ld(lst + 0x24 + 4 * i, 4))
	for side in 2:
		var v: int = g.f_02027c00(side)
		if v == 0 or not v in objs or not g._helped(v) or _ld(v + 4, 1) == 0:
			continue
		var auto: bool = _auto and side == 0
		var w: Dictionary = _win.get(v, {})
		var open: bool = auto or (not w.is_empty() and w["pass"] > 0 and not w["hit"])
		if not w.is_empty():
			w["pass"] -= 1                              # one pass of the window used (touched or not)
		if not open and not _imm.has(v) and not _ign_for(v):
			continue
		var hurt := _boxes(v, [2, 4])
		if hurt.is_empty():
			continue
		var hits: Array = []
		var cx := 0.0
		var cy := 0.0
		for a in objs:
			if a == v or _ld(a + 4, 1) == 0 or _ld(a + 0x1A, 1) == _ld(v + 0x1A, 1):
				continue
			var hd: int = _ld(a + 0x34, 4)
			if hd == NOOP_HIT or hd == NO_DAMAGE_HIT or hd == 0:
				continue
			if hd == MELEE_HIT and (_ld(a + 0x250, 4) & 4) != 0:
				continue                                    # its hit this animation frame already landed
			var c := _touch(_boxes(a, [1]), hurt)
			if c.is_empty():
				continue
			hits.append(a)
			cx = c[0]
			cy = c[1]
		if hits.is_empty():
			continue
		var fresh: Array = []
		for a in hits:
			if not (_ign.has(a) and _ign[a][0] == v):
				fresh.append(a)
		if not open and not _imm.has(v) and not fresh.is_empty():
			continue                                        # only ignored shots are excused: the others hit
		_hidden.append([v, _ld(v + 4, 1)])
		_st(v + 4, 1, 0)
		if open and not fresh.is_empty():
			if not w.is_empty():
				w["hit"] = true
			_events.append([v, fresh, cx, cy])


func _ign_for(v: int) -> bool:
	for o in _ign:
		if _ign[o][0] == v:
			return true
	return false


## after FUN_0201E5BC: the hidden fighters are back, the parries take effect
func after() -> void:
	for h in _hidden:
		_st(h[0] + 4, 1, h[1])
	_hidden.clear()
	for e in _events:
		_parry(e[0], e[1], e[2], e[3])
	_events.clear()


func _parry(v: int, hits: Array, cx: float, cy: float) -> void:
	parries += 1
	_imm[v] = IMMUNE
	_lock.erase(v)
	var side: int = _ld(v + 0x1A, 1)
	var opp: int = g.f_02027bd0(side)
	var what := []
	for a in hits:
		if _is_fighter(a):
			if a == opp and _stunnable(a):
				_stun(a, v)
				what.append("stun %x" % a)
			else:
				what.append("fighter %x (busy)" % a)
		elif _ld(_ld(a + 0x40, 4) + _ld(a + 6, 1) * 8, 4) == BLAST and _ld(a + 0x118, 4) != 0 \
				and _ld(_ld(a + 0x118, 4) + 6, 1) <= 2:
			_reflect(a, v)
			what.append("reflect %x" % a)
		else:
			_ign[a] = [v, IGNORE]
			what.append("ignore %x" % a)
	g.f_02012f9c(STOP)
	var sp: int = g.f_0202247c(v, SPARK_KIND)
	if sp != 0:
		_st(sp + 0x38, 4, int(cx) << 8)
		_st(sp + 0x3C, 4, int(cy) << 8)
	if _se >= 0:
		g.f_02029e3c(v, _se)
	_gen += 1
	_fx.append([v, 1, 0, cx, cy, _gen])
	if _dbg:
		print("UI f%d PARRY fighter %x at %d,%d: %s" % [g._port_frame(), v, int(cx), int(cy), ", ".join(what)])


func _is_fighter(a: int) -> bool:
	var teams: int = _ld(TEAMS, 4)
	return (a >= teams and a < teams + 2 * 0x8E8) or (a >= 0x02700000 and a < 0x02710000)


func _stunnable(a: int) -> bool:
	var act: int = _ld(a + 6, 1)
	if _ld(a + 0x24A, 2, true) <= 0 or act == 0x33 or (act >= 0x26 and act <= 0x30) or act >= 0x85:
		return false
	if act >= 0x34 and act <= 0x66:
		return false
	return (_ld(a + 0x250, 4) & 0xC20) == 0


## the parried attacker staggers back (what FUN_02027C2C does to a dash-attack victim, with a longer stun)
func _stun(a: int, v: int) -> void:
	var dir := 0 if _ld(a + 0x38, 4, true) >= _ld(v + 0x38, 4, true) else 0x80
	g.f_020213a8(a, 0x300, -0x40, 0, dir)
	_st(a + 0x250, 4, 0)
	_st(a + 0x25D, 1, _ld(a + 0x1A, 1))
	g.f_02021b4c(a, 0x11)
	_st(a + 0x25E, 2, STUN)
	_st(a + 0x250, 4, _ld(a + 0x250, 4) | 2)


## FUN_02027C2C's reflection of a shot by a dash attack: the shot turns around and belongs to the parrying side
func _reflect(o: int, v: int) -> void:
	for off in [0x28, 0x2A, 0x2C, 0x2E, 0x30, 0x32]:
		_st(o + off, 2, (-_ld(o + off, 2, true)) & 0xFFFF)
	_st(o + 0x1A, 1, _ld(v + 0x1A, 1))
	_st(o + 7, 1, (_ld(o + 7, 1) + 0x80) & 0xFF)
	_st(o + 0x21, 1, (_ld(o + 0x21, 1) + 0x80) & 0xFF)
	g.f_02011f74(o + 0x124, 0, 0, (0x100 - _ld(o + 7, 1)) & 0xFF)


## the object's boxes of the given types as [x0, y0, x1, y1] world px, exactly as FUN_0201E5BC places them
func _boxes(o: int, types: Array) -> Array:
	var d: int = _ld(o + 0x120, 4)
	if d == 0:
		return []
	var cnt: int = _ld(d + 6, 2) & 0xFF
	var out: Array = []
	var sx: int = _ld(o + 0x154, 2)
	var sy: int = _ld(o + 0x156, 2)
	var fa: int = _ld(o + 7, 1)
	var x: int = _ld(o + 0x38, 4, true) >> 8
	var y: int = _ld(o + 0x3C, 4, true) >> 8
	for i in cnt:
		var b := d + 8 + i * 0xC
		if not _ld(b + 8, 4, true) in types:
			continue
		var bx: int = (sx * _ld(b, 2, true)) >> 8
		var bw: int = (sx * _ld(b + 4, 2, true)) >> 8
		var y0: int = y + ((sy * _ld(b + 2, 2, true)) >> 8)
		var y1: int = y0 + ((sy * _ld(b + 6, 2, true)) >> 8)
		if fa < 0xC1 and fa > 0x3F:
			var x1 := x - bx
			out.append([x1 - bw, y0, x1, y1])
		else:
			var x0 := x + bx
			out.append([x0, y0, x0 + bw, y1])
	return out


## [centre x, centre y] of the first overlap of an attack box with a hurt box (the game's <= tests), [] if none
func _touch(att: Array, hurt: Array) -> Array:
	for a in att:
		for h in hurt:
			if h[0] <= a[2] and a[0] <= h[2] and h[1] <= a[3] and a[1] <= h[3]:
				return [(maxi(a[0], h[0]) + mini(a[2], h[2])) * 0.5, (maxi(a[1], h[1]) + mini(a[3], h[3])) * 0.5]
	return []


# ------------------------------------------------------------------------------------------------ drawing
## Our two 16-colour palettes (silver, red) for the fighters' 4-bit textures: written into port-only RAM and given to
## the game's palette allocator FUN_02010B6C once per battle (a slot of the scene's list, uploaded at VBlank like the
## game's own); the copies below draw the fighter's own texture through them: a white / red silhouette.
const PAL_RAM := 0x027C0100              ## port-only RAM: 2 x 32 bytes
const SILVER := [0, 0x6988, 0x7E8E, 0x7EAF, 0x7ED0, 0x7ED1, 0x7EF2, 0x7F13, 0x7F34, 0x7F36, 0x7F57, 0x7F78, 0x7F99, 0x7F9A,
	0x7FBB, 0x7FDC]                       ## dark blue rim, then light blue -> silver (BGR555)
const RED := [0, 0x0010, 0x0419, 0x085F, 0x0C7F, 0x109F, 0x14BF, 0x18DF, 0x1CFF, 0x211F, 0x253F, 0x295F, 0x2D7F,
	0x2D7F, 0x2D7F, 0x2D7F]
var _pal := -1                           ## palette VRAM byte offset of the silver palette (red = + 0x20), -2 = refused


## once per battle (tick): the palettes into a slot of the game's texture-palette manager
func _alloc_pal() -> void:
	if _pal != -1:
		return
	for i in 16:
		_st(PAL_RAM + i * 2, 2, SILVER[i])
		_st(PAL_RAM + 0x20 + i * 2, 2, RED[i])
	var s: int = g.f_02010b6c(PAL_RAM, 0x40)
	_pal = s if s != 0xFFFF else -2
	if _dbg:
		print("UI f%d palettes at %x" % [g._port_frame(), _pal])


func any_fx() -> bool:
	return not _fx.is_empty()


## after the game's sprite list (QoLGame._fx_draw): idx = sprites drawn this frame, cv = camera. The flashes run on
## the picture's frames (also through the parry's hit stop), frozen while the game is paused / in a cut-in.
func draw(idx: Dictionary, cv: Array, _step: bool) -> bool:
	if _fx.is_empty():
		return false
	var run: bool = g.f_02012fd4() == 0
	var g8: int = g._ld(g._ld(g.SPR_LIST, 4, false) + 0x184, 4, true)
	var z: float = cv[4]
	var drew := false
	var keep: Array = []
	for e in _fx:
		var f: int = e[0]
		var p: int = f + 0x124
		var age: int = e[2]
		var visible: bool = idx.has(p) and _ld(p + 0x3D, 1) != 0 and _ld(p + 0x3B, 1) > 7 and _ld(p, 4) != 0
		var pal4: bool = _pal >= 0 and _ld(p + 0xC, 4, true) == 3      # a 4-bit texture: our palettes fit
		var zf: int = _ld(p + 0x3C, 1)
		if e[1] == 1:
			var k := age / float(FX_T)
			if visible:
				if age < STOP + 2:                      # the freeze: the fighter turns silver-white, pulsing
					var al := 30 if (age / 2) % 2 == 0 else 23
					g._spr_copy(p, g8, 1.0, 1.0, 0, 0, zf + 1, al, PID_MISS, 0x7FFF if pal4 else TINT_UI, _pal if pal4 else -1)
					g._spr_copy(p, g8, 1.12, 1.12, 0, 0, 2, 12, PID_UI, 0x7FFF if pal4 else TINT_UI, _pal if pal4 else -1)
				for j in 2:                             # two silver silhouettes growing out of the fighter, fading
					var kk := clampf(k * 1.3 - 0.2 * j, 0.0, 1.0)
					var s := 1.08 + 0.6 * kk
					var al1 := int(18.0 * (1.0 - kk))
					if al1 >= 1:
						g._spr_copy(p, g8, s, s, 0, 0, 2, al1, PID_UI, 0x7FFF if pal4 else TINT_UI, _pal if pal4 else -1)
				drew = true
			for i in RING:                            # a ring of sparkles from the contact point
				var ang: float = TAU * i / RING + 0.3 * e[5]
				var r := 4.0 + 34.0 * sqrt(k)
				var sx := floorf(cv[2] + z * (e[3] + cos(ang) * r - cv[0]))
				var sy := floorf(cv[3] + z * (e[4] + sin(ang) * r - cv[1]))
				var al2 := clampi(int(31.0 * (1.0 - k * k)), 1, 30)
				var col := 0x7FFF if i % 2 == 0 else 0x7FD4
				var big := age < FX_T / 2
				var key: int = FXK_UI + ((i * 2) * 4 + (int(e[5]) & 3))
				g._fx_box(sx - (1.0 if big else 0.0), sy, 3 if big else 1, 1, col, 0x80C0 | (al2 << 16) | (0x2C << 24), 9, key)
				g._fx_box(sx, sy - (1.0 if big else 0.0), 1, 3 if big else 1, col, 0x80C0 | (al2 << 16) | (0x2C << 24), 9, key + 4)
				drew = true
			if run:
				e[2] += 1
			if e[2] < FX_T:
				keep.append(e)
		else:
			if visible and (age / 3) % 2 == 0:       # red flicker: on 3 frames, off 3
				var al3 := int(18.0 * (1.0 - age / float(MISS_T))) + 6
				g._spr_copy(p, g8, 1.0, 1.0, 0, 0, zf + 1, al3, PID_MISS, 0x7FFF if pal4 else TINT_MISS, _pal + 0x20 if pal4 else -1)
				drew = true
			if run:
				e[2] += 1
			if e[2] < MISS_T:
				keep.append(e)
	_fx = keep
	return drew