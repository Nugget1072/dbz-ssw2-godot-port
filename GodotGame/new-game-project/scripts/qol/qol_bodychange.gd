extends RefCounted
## BODY CHANGE (part 42, cheat page 9 POWERS; QoLSettings cheat "body_change", test flag `cheats=body_change`), after
## Captain Ginyu's technique. Owned by QoLGame (`# ---- BODY CHANGE (part 42)`), which calls tick() once per battle
## frame (its FUN_0202954C override), draw() after the game's sprite list (_fx_draw) and reset() at every battle load.
## Nothing here runs with the cheat off.
## Every SWAP_T running battle frames the two active fighters trade their HP: each gets the share of ITS OWN max HP
## that the other one had (a boss with more max HP keeps its size; at least 1 HP). The last WARN frames count down
## ("5" .. "1", purple digits at the bottom centre, between the two ki gauges); then Ginyu's ray flashes between them and both glow purple. The
## game repaints the active members' life bars itself when their HP changes (up: at once; down: the usual drain).
## The clock runs only while the fight runs (battle state 7, no pause / cut-in, camera mode 0, no tag) and waits while
## a fighter is KO'd or in a sequence; a swap that comes due then happens as soon as both are free.
## LAN: integers from battle RAM, counted in battle frames: both machines agree.
## Debug: `bcdbg` (swap lines), `bct=N` (SWAP_T).

const SWAP_T := 1200                     ## 20 s
const WARN := 300                        ## the countdown's last 5 s
const RAY_T := 24                        ## picture frames of the ray / glow
const TEAMS := 0x020DE3D0
const CAMERA := 0x020DE3A4
const BATTLE_STATE := 0x020DD4C5
const SWAP_SE := 0x0C                    ## FUN_02029E3C: the step-dash burst (a 0.6 s whoosh, DATA_NOTES part 39 table)
const PURPLE_TOP := 0x7D3B               ## (27, 9, 31)
const PURPLE_BOT := 0x4C70               ## (16, 3, 19)
const PID_GLOW := 0x2D                   ## polygon IDs (port effects; shared with TIME SKIP's stone copy: never on one px)
const PID_RAY := 0x29
const PID_RAY2 := 0x2B                   ## (the core over the body: another ID)
const FXK_BC := 0x0F00                   ## PLTT_BASE pairing keys of the ray quads
const PAL_RAM := 0x027C01C0              ## port-only RAM: 32 bytes (TIME SKIP 0x1A0-0x1BF)
const VIOLET := [0, 0x2807, 0x3009, 0x380B, 0x400D, 0x480F, 0x5011, 0x5813, 0x6015, 0x6437, 0x6859, 0x6C7B, 0x709D,
	0x74BF, 0x7CDF, 0x7EFF]              ## dark -> light violet (BGR555)

var g = null                             ## the QoLGame
var _t := 0                              ## running battle frames since the last swap
var _swap_t := SWAP_T
var _last := -2
var _fx := -1                            ## picture frames since the last swap (-1 none)
var _ends: Array = []                    ## [x0, y0, x1, y1] world px of the ray
var _pal := -1
var swaps := 0
var _dbg := Game.args.has("bcdbg")


func _init(game) -> void:
	g = game
	_swap_t = maxi(int(Game.flag("bct", str(SWAP_T))), WARN + 60)
	reset()


func reset() -> void:
	_t = 0
	_last = -2
	_fx = -1
	_ends.clear()
	_pal = -1


func _ld(a: int, n: int, s := false) -> int:
	return g._ld(a, n, s)


func _st(a: int, n: int, v: int) -> void:
	g._st(a, n, v)


func _running() -> bool:
	if _ld(BATTLE_STATE, 1) != 7 or g.f_02012fd4() != 0:
		return false
	var cam: int = _ld(CAMERA, 4)
	if cam == 0 or _ld(cam, 2) != 0:
		return false
	return _ld(_ld(TEAMS, 4) + 0x11DC, 4) == 0       # (no tag)


## a fighter that may take part in a swap now
func _free(r: int) -> bool:
	return r != 0 and _ld(r + 0x24A, 2, true) > 0 and _ld(r + 6, 1) != 0x33 and (_ld(r + 0x250, 4) & 0x420) == 0 \
		and _ld(r + 0x24C, 2) > 0


func tick(pf: int) -> void:
	if pf == _last:
		return
	_last = pf
	if not _running():
		return
	if _t < _swap_t:
		_t += 1
		return
	var a: int = g.f_02027c00(0)
	var b: int = g.f_02027c00(1)
	if not _free(a) or not _free(b):
		return                                          # due: as soon as both are free
	var ha: int = _ld(a + 0x24A, 2, true)
	var hb: int = _ld(b + 0x24A, 2, true)
	var ma: int = _ld(a + 0x24C, 2)
	var mb: int = _ld(b + 0x24C, 2)
	var na: int = clampi(hb * ma / mb, 1, ma)
	var nb: int = clampi(ha * mb / ma, 1, mb)
	_st(a + 0x24A, 2, na)
	_st(b + 0x24A, 2, nb)
	g.f_02029e3c(a, SWAP_SE)
	_ends = [_ld(a + 0x38, 4, true) / 256.0, _ld(a + 0x3C, 4, true) / 256.0 - 12.0, _ld(b + 0x38, 4, true) / 256.0,
		_ld(b + 0x3C, 4, true) / 256.0 - 12.0]
	_fx = 0
	_t = 0
	swaps += 1
	if _dbg:
		print("BC f%d BODY CHANGE: side 0 %d/%d -> %d, side 1 %d/%d -> %d" % [pf, ha, ma, na, hb, mb, nb])


## frames left before the next swap (shown in the countdown)
func left() -> int:
	return _swap_t - _t


func any_fx() -> bool:
	return true


## after the game's sprite list (QoLGame._fx_draw)
func draw(idx: Dictionary, cv: Array) -> bool:
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
	var drew := false
	# the countdown: purple digits under the middle of the HUD, the last WARN frames
	var l := left()
	if l <= WARN and _fx < 0 and cam != 0 and _ld(cam, 2) == 0 and _ld(BATTLE_STATE, 1) == 7:
		if g._dn_glyphs.size() < 11:
			g._dn_init()
		var secs := (l + 59) / 60
		var pop := l % 60 > 50                          # a new second: one size bigger for a moment
		var ps := 3 if pop else 2
		var w := 5 * ps
		var bst: int = _ld(BATTLE_STATE, 1)
		var mirror: bool = g.cheats.mirror_mode and _ld(0x027E0004, 4) == 0x02013030 and bst >= 4 and bst != 9
		g._dn_k = 0x900 + secs * 4 + ps
		g._dn_emit(str(maxi(secs, 1)), ps, (128.0 + w * 0.5) if mirror else (128.0 - w * 0.5), 186.0 - 7.0 * ps, mirror, PURPLE_TOP, PURPLE_BOT, 31)   # part 42 QA: bottom centre, between the ki gauges (the top centre met HOT POTATO's countdown)
		drew = true
	if _fx < 0:
		return drew
	# the swap: both fighters glow violet, Ginyu's ray between them
	var u := _fx / float(RAY_T)
	if _pal == -1:
		for i in 16:
			_st(PAL_RAM + i * 2, 2, VIOLET[i])
		var s: int = g.f_02010b6c(PAL_RAM, 0x20)
		_pal = s if s != 0xFFFF else -2
	var g8: int = g._ld(g._ld(g.SPR_LIST, 4, false) + 0x184, 4, true)
	for side in 2:
		var r: int = g.f_02027c00(side)
		var p := r + 0x124
		if r != 0 and _pal >= 0 and idx.has(p) and _ld(p, 4) != 0 and _ld(p + 0x3D, 1) != 0 and _ld(p + 0xC, 4, true) == 3:
			g._spr_copy(p, g8, 1.0, 1.0, 0, 0, _ld(p + 0x3C, 1) + 1, clampi(int(24.0 * (1.0 - u)), 1, 30), PID_GLOW, 0x7FFF, _pal)
			drew = true
	var z: float = cv[4]
	var ax: float = cv[2] + z * (float(_ends[0]) - cv[0])
	var ay: float = cv[3] + z * (float(_ends[1]) - cv[1])
	var bx: float = cv[2] + z * (float(_ends[2]) - cv[0])
	var by: float = cv[3] + z * (float(_ends[3]) - cv[1])
	var d := Vector2(bx - ax, by - ay)
	var n := clampi(int(d.length() / 5.0), 2, 60)
	var perp := Vector2(-d.y, d.x).normalized()
	var al := clampi(int(30.0 * (1.0 - u * u)), 1, 30)
	for i in n + 1:
		var k := i / float(n)
		var wob := sin(k * 18.0 + _fx * 0.9) * 3.0 * (1.0 - u)    # a wavy ray
		var c := Vector2(ax, ay) + d * k + perp * wob
		var sz := 6 if (i + _fx) % 3 == 0 else 5         # a violet body with a white core
		g._fx_box(floorf(c.x - sz * 0.5), floorf(c.y - sz * 0.5), sz, sz, 0x7D3B, 0x80C0 | (maxi(al * 2 / 3, 1) << 16) | (PID_RAY << 24), 38, FXK_BC + ((i * 2) & 0xFF))
		g._fx_box(floorf(c.x - 1.0), floorf(c.y - 1.0), 2, 2, 0x7FFF, 0x80C0 | (al << 16) | (PID_RAY2 << 24), 39, FXK_BC + ((i * 2 + 1) & 0xFF))
	drew = true
	if run:
		_fx += 1
		if _fx >= RAY_T:
			_fx = -1
	return drew
