extends RefCounted
## VAMPIRE (part 41, cheat page 5 FIGHTING; QoLSettings cheat "vampire", test flag `cheats=vampire`). Owned by QoLGame
## (`# ---- VAMPIRE (part 41)`), which calls hit() for every fighter that loses HP inside the game's collision pass
## FUN_0201E5BC (its f_020293A4 override measures the HP really lost: HARD MODE / INFINITE HEALTH / guarding count),
## draw() after the game's sprite list (_fx_draw) and reset() at every battle load. Nothing here runs with the cheat off.
## Every hit drains life: the active fighter of the OTHER side (the attacker's team: hits, shots, beams, assists) gets
## RATE_NUM / RATE_DEN of the HP the victim lost, up to its max HP (+0x24A / +0x24C; the game repaints the active
## member's life bar when its HP rises, DATA_NOTES part 35). Both teams. Not while the attacker is KO'd.
## Looks: green sparks fly from the victim to the healed fighter, which pulses green (its own texture through a green
## 16-colour palette, as ULTRA INSTINCT's silhouettes) and shows a green "+N" (DAMAGE NUMBERS' digits; hits within
## MERGE frames add up).
## LAN: integers from battle RAM only (the looks are drawing only).
## Debug: `vpdbg` (heal lines).

const RATE_NUM := 2                      ## heal = HP lost x 2 / 5 (40 %)
const RATE_DEN := 5
const MERGE := 12                        ## picture frames: heals this close add to the same number
const NUM_LIFE := 54
const NUM_RISE := 18.0
const SPARKS := 6                        ## sparks per heal
const SPARK_T := 20                      ## picture frames from the victim to the healed fighter
const GLOW_T := 18                       ## picture frames of the green pulse
const GREEN_TOP := 0x23EC                ## (12, 31, 8)
const GREEN_BOT := 0x12C4                ## (4, 22, 4)
const PID_GLOW := 0x2E                   ## polygon IDs (port effects 0x28-0x3F; 0x2E / 0x2F were free)
const PID_SPARK := 0x2F
const PID_CORE := 0x3E                   ## (ULTRA INSTINCT's copies use it too: never at the same time on the same px)
const FXK_VP := 0x0C00                   ## PLTT_BASE pairing keys of the sparks (QoLGame FXK_* list)
const PAL_RAM := 0x027C0140              ## port-only RAM: 32 bytes (ULTRA INSTINCT uses 0x027C0100-0x013F)
const GREEN := [0, 0x0140, 0x0181, 0x01C2, 0x0603, 0x0A44, 0x0E85, 0x12C6, 0x16E7, 0x1B08, 0x1F29, 0x234A, 0x2B6C,
	0x338E, 0x3BB0, 0x47D3]              ## dark green rim -> light green (BGR555)

var g = null                             ## the QoLGame
var _pal := -1                           ## palette VRAM byte offset, -2 = refused
var _nums: Array = []                    ## [fighter, total, age, world x, world y, serial]
var _sparks: Array = []                  ## [from x, from y, fighter, age, index, generation]
var _glow := {}                          ## fighter -> age of its pulse
var _serial := 0
var _gen := 0
var healed := 0                          ## (debug / tests)
var _dbg := Game.args.has("vpdbg")


func _init(game) -> void:
	g = game


func reset() -> void:
	_nums.clear()
	_sparks.clear()
	_glow.clear()
	_pal = -1                                       # the scene's palette list starts over


func _ld(a: int, n: int, s := false) -> int:
	return g._ld(a, n, s)


func _st(a: int, n: int, v: int) -> void:
	g._st(a, n, v)


## victim v lost `lost` HP inside the collision pass
func hit(v: int, lost: int) -> void:
	if lost <= 0:
		return
	var side: int = _ld(v + 0x1A, 1) & 1
	if v != g.f_02027c00(side):
		return                                      # only the active fighters' HP counts
	var a: int = g.f_02027c00(1 - side)
	if a == 0:
		return
	var hp: int = _ld(a + 0x24A, 2, true)
	var mx: int = _ld(a + 0x24C, 2)
	if hp <= 0 or mx <= 0 or _ld(a + 6, 1) == 0x33:
		return
	var heal: int = mini(lost * RATE_NUM / RATE_DEN, mx - hp)
	if heal <= 0:
		return
	_st(a + 0x24A, 2, hp + heal)
	healed += heal
	if _dbg:
		print("VP f%d fighter %x hit %x for %d: heals %d -> %d / %d" % [g._port_frame(), v, a, lost, heal, hp + heal, mx])
	# looks
	var vx := _ld(v + 0x38, 4, true) / 256.0
	var vy := _ld(v + 0x3C, 4, true) / 256.0 - 14.0
	_gen += 1
	for i in SPARKS:
		_sparks.append([vx, vy, a, -i, i, _gen])          # (negative age: a short stagger)
	if _sparks.size() > 48:
		_sparks = _sparks.slice(_sparks.size() - 48)
	_glow[a] = 0
	for n in _nums:
		if n[0] == a and n[2] <= MERGE:
			n[1] += heal
			n[2] = 0
			return
	_serial += 1
	_nums.append([a, heal, 0, _ld(a + 0x38, 4, true) / 256.0, _ld(a + 0x3C, 4, true) / 256.0 - 44.0, _serial])
	if _nums.size() > 4:
		_nums.pop_front()


func any_fx() -> bool:
	return not _nums.is_empty() or not _sparks.is_empty() or not _glow.is_empty()


## the green palette into a slot of the game's texture-palette manager (once per battle, at the first pulse)
func _alloc_pal() -> void:
	if _pal != -1:
		return
	for i in 16:
		_st(PAL_RAM + i * 2, 2, GREEN[i])
	var s: int = g.f_02010b6c(PAL_RAM, 0x20)
	_pal = s if s != 0xFFFF else -2


## after the game's sprite list (QoLGame._fx_draw): idx = sprites drawn this frame, cv = camera. Runs on the picture's
## frames, frozen while the game is paused / in a cut-in.
func draw(idx: Dictionary, cv: Array) -> bool:
	if not any_fx():
		return false
	var run: bool = g.f_02012fd4() == 0
	var z: float = cv[4]
	var drew := false
	# the green pulse on the healed fighter
	if not _glow.is_empty():
		_alloc_pal()
		var g8: int = g._ld(g._ld(g.SPR_LIST, 4, false) + 0x184, 4, true)
		for f in _glow.keys():
			var age: int = _glow[f]
			var p: int = f + 0x124
			var visible: bool = idx.has(p) and _ld(p + 0x3D, 1) != 0 and _ld(p + 0x3B, 1) > 7 and _ld(p, 4) != 0
			var pal4: bool = _pal >= 0 and _ld(p + 0xC, 4, true) == 3
			if visible and pal4:
				var k := age / float(GLOW_T)
				var al := int(8.0 * (1.0 - k)) + 2           # (a glow over its own colours, not a green fighter)
				g._spr_copy(p, g8, 1.0, 1.0, 0, 0, _ld(p + 0x3C, 1) + 1, al, PID_GLOW, 0x7FFF, _pal)
				var s := 1.05 + 0.25 * k
				var al2 := int(7.0 * (1.0 - k))
				if al2 >= 1:
					g._spr_copy(p, g8, s, s, 0, 0, 2, al2, PID_GLOW, 0x7FFF, _pal)
				drew = true
			if run:
				_glow[f] = age + 1
				if age + 1 >= GLOW_T:
					_glow.erase(f)
	# the sparks: victim -> healed fighter, on a bowed path, a 2x2 light-green head with a 1 px darker trail
	var keep: Array = []
	for e in _sparks:
		var age: int = e[3]
		if age >= 0:
			var f: int = e[2]
			var tx := _ld(f + 0x38, 4, true) / 256.0
			var ty := _ld(f + 0x3C, 4, true) / 256.0 - 14.0
			var u := minf(age / float(SPARK_T), 1.0)
			var ease := u * u * (3.0 - 2.0 * u)
			var bow := sin(u * PI) * (10.0 + 4.0 * float(e[4])) * (1.0 if int(e[4]) % 2 == 0 else -1.0)
			var dx: float = tx - float(e[0])
			var dy: float = ty - float(e[1])
			var ln := maxf(sqrt(dx * dx + dy * dy), 1.0)
			var wx: float = float(e[0]) + dx * ease - dy / ln * bow
			var wy: float = float(e[1]) + dy * ease + dx / ln * bow
			var sx := floorf(cv[2] + z * (wx - cv[0]))
			var sy := floorf(cv[3] + z * (wy - cv[1]))
			var al := clampi(int(31.0 * (1.0 - u * u * 0.6)), 1, 31)
			var key: int = FXK_VP + ((int(e[4]) * 4 + (int(e[5]) & 3)) & 0xFF) * 2
			g._fx_box(sx - 2.0, sy - 2.0, 4, 4, 0x0D02, 0x80C0 | (al << 16) | (PID_SPARK << 24), 9, key)   # dark green rim
			g._fx_box(sx - 1.0, sy - 1.0, 2, 2, 0x47D3 if age % 4 < 2 else 0x7FFB, 0x80C0 | (al << 16) | (PID_CORE << 24), 10, key + 0x80)
			var tu := maxf(u - 0.08, 0.0)
			var te := tu * tu * (3.0 - 2.0 * tu)
			var tb := sin(tu * PI) * (10.0 + 4.0 * float(e[4])) * (1.0 if int(e[4]) % 2 == 0 else -1.0)
			var px := floorf(cv[2] + z * (float(e[0]) + dx * te - dy / ln * tb - cv[0]))
			var py := floorf(cv[3] + z * (float(e[1]) + dy * te + dx / ln * tb - cv[1]))
			g._fx_box(px, py, 1, 1, GREEN_BOT, 0x80C0 | (maxi(al - 8, 1) << 16) | (PID_SPARK << 24), 9, key + 1)
			drew = true
		if run:
			e[3] = age + 1
		if int(e[3]) <= SPARK_T:
			keep.append(e)
	_sparks = keep
	# the "+N" numbers (DAMAGE NUMBERS' digits, ':' = the plus glyph), rising and fading
	if not _nums.is_empty():
		if g._dn_glyphs.size() < 11:
			g._dn_init()
		var bst: int = _ld(0x020DD4C5, 1)
		var mirror: bool = g.cheats.mirror_mode and _ld(0x027E0004, 4) == 0x02013030 and bst >= 4 and bst != 9
		var nk: Array = []
		for n in _nums:
			var age: int = n[2]
			if age <= MERGE:                                # still adding up: follows the fighter
				n[3] = _ld(int(n[0]) + 0x38, 4, true) / 256.0
				n[4] = _ld(int(n[0]) + 0x3C, 4, true) / 256.0 - 44.0
			var u := minf(age / float(NUM_LIFE), 1.0)
			var rise := NUM_RISE * (1.0 - (1.0 - u) * (1.0 - u))
			var ps := 2 if age < 3 else 1
			var digits := ":" + str(n[1])
			var w := (digits.length() * 6 - 1) * ps
			var sx := clampf(cv[2] + z * (float(n[3]) - cv[0]), w * 0.5 + 2.0, 254.0 - w * 0.5)
			var sy := clampf(cv[3] + z * (float(n[4]) - cv[1]) - rise, 64.0, 150.0)   # (part 42 QA: never in the HUD / RUSH band, y < 57, nor on the HUD rows below)
			var al := 31 if age < NUM_LIFE - 14 else clampi(31 * (NUM_LIFE - age) / 14, 1, 30)
			g._dn_k = 0x800 + ((int(n[5]) * 37 + ps * 5) & 0x7FF)
			g._dn_emit(digits, ps, floorf(sx + w * 0.5) if mirror else floorf(sx - w * 0.5), floorf(sy - 3.5 * ps), mirror, GREEN_TOP, GREEN_BOT, al)
			drew = true
			if run:
				n[2] = age + 1
			if int(n[2]) < NUM_LIFE:
				nk.append(n)
		_nums = nk
	return drew
