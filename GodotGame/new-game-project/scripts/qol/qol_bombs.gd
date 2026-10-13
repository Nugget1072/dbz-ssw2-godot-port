extends RefCounted
## BOMB RAIN (part 25, WEIRD STUFF 3; QoLSettings.bomb_rain, test flag `weird=bombs`). Owned by QoLGame (`# ---- BOMB
## RAIN (part 25)`), which calls tick() once per battle frame (from its FUN_0202954C override), draw() after the game's
## sprite list (_fx_draw) and reset() at every battle load. Nothing here runs with the setting off.
## Walking bombs (the user's art, assets_qol/bomb.png: 6 frames = feet A/B x 3 fuse sparks) drop from just above the
## battle picture near the fighters while the fight itself runs (battle state 7; no pause / cut-in / tag / camera
## special mode / KO), fall at a readable speed with a slight sway, a round shadow marks the landing spot on the floor.
## Touching an active fighter's hurt box: the bomb explodes, the fighter loses 1/4 of its max HP (a guarding fighter
## 1/16, never below 1 HP) and is knocked away (hit reaction 0x11 like a heavy ki blast); others in the blast take the
## ground blast. Reaching the floor: explodes, fighters within BLAST_R world px lose 3-12 % of max HP by distance
## (reaction 0xF). Explosion = the game's own ki-blast explosion (common effect kind 1, FUN_0202247C + FUN_0202216C,
## like the blast hit handler FUN_0201F474) + its sound (FUN_02029E3C, SE 0x1E). HP goes through FUN_020293A4 (the
## QoLGame override: INFINITE HEALTH, HARD MODE, BLOOD, DAMAGE NUMBERS, SCREEN SHAKE all apply). Bombs hurt both teams.
## Own RNG (seed `bombseed=N`, default SEED) reset at every battle load: the game's RNG is never used.
## Drawing (part 26): each bomb and its shadow is ONE textured GX quad, like the game's own sprites, so CAMERA ZOOM,
## SCREEN SHAKE, MIRROR MODE and smooth motion move it as one piece. The 6 frames + the shadow are a direct-colour
## texture (0xD00 bytes) in a block reserved at the top of the game's texture VRAM manager (u32 0x020DE380; offset
## TEX_OFS, slot 2 = bank C in battles) with its own key, so the game never allocates over it; no texture palette.
## (Part 36: the block is qol_texblock.gd, shared with GREEN DEMON at 0xD00..0x1000; same offsets and texels.)
## (Part 25 drew ~38 untextured quads per bomb: in in-between frames (FPS > 60) the renderer matched them by polygon
## number to different quads of the previous list and moved / stretched each one differently: separated pixels and
## one-colour boxes. DATA_NOTES "part 26 findings (bomb sprite)".)
## Debug: `bombdbg` (spawn / hit / blast / damage / texture lines), `bombpos` (BOMBD: drawn position per frame),
## `bombvram` (VRAMCNT + texture manager blocks every 20 battle frames), `bombseed=N`, `bombrate=F` (spawn interval
## x 1/F), `bombfx=V` / `bombfxcycle` / `bombkind=K` (explosion).
## DATA_NOTES "Session 1 part 25 findings (bomb rain)".

const PNG := "res://assets_qol/bomb.png"
const FRAMES := 6                        ## feet A sparks 0-2, feet B sparks 0-2
const MAX_ALIVE := 5
const SEED := 0xB0B0B
const FIRST_WAIT := 70                   ## battle frames from the fight's start to the first bomb
const GAP_MIN := 72                      ## frames between spawns (1.2 - 2.5 s)
const GAP_MAX := 150
const V0 := 0.9                          ## fall speed (world px / frame): start, gain, top
const VA := 0.035
const VMAX := 2.1
const SWAY := 3.0                        ## px
const DIRECT := 0.25                     ## of max HP
const GUARD_DIV := 4                     ## a guarded direct hit: 1/4 of it
const BLAST_R := 40.0                    ## world px from the blast centre to the hurt box
const BLAST_MAX := 0.12
const BLAST_MIN := 0.03
const COOL := 45                         ## frames a fighter is safe from bombs after a bomb hurt it
const EXPL_KIND := 1                     ## common effect kind: ki-blast explosion
const EXPL_DIRECT := 0x10008             ## FUN_0202216C argument: size variant +0x1D (0 ~40 px, 1 ~70, 2 ~110, 3-4 huge)
const EXPL_GROUND := 0x10008
const SE_BOOM := 0x1E                    ## FUN_02029E3C(obj, 0x1E): the blast explosion sound
const GUARD_SPARK := 0xB                 ## common effect kind of a guarded hit (FUN_0201E9EC)
const BOX := 0x027C0000                  ## port-only RAM: 8 bytes, FUN_0201DF20's box output
const TEAMS := 0x020DE3D0
const CAMERA := 0x020DE3A4
const BATTLE_STATE := 0x020DD4C5
const Z_BOMB := 10
const Z_SHADOW := 1
const PID_BOMB := 0x22
const PID_SHADOW := 0x23
const ATTR := 0x80C0 | (31 << 16)        ## POLYGON_ATTR like the game's sprites: both faces, fog bit, opaque
const TEX_MGR := 0x020DE380              ## u32 -> the game's texture VRAM manager (DATA_NOTES part 18)
const TEX_KEY := 0x7B0B0B26              ## our block's key (the game's keys: -1, 0x2000000x, small ids)
const TEX_END := 0x60000                 ## the manager's tail sentinel: texture slots 0-2 (A|B|C)
const TEX_BLOCK := 0x1000                ## reserved block: TEX_END - TEX_BLOCK .. TEX_END
const TEX_OFS := TEX_END - TEX_BLOCK     ## texture VRAM offset of frame 0 (slot 2 + 0x1F000)
const FR_BYTES := 0x200                  ## one frame: 16x16 direct colour
const SH_OFS := FRAMES * FR_BYTES        ## the shadow: 16x8 direct colour after the frames
const TEX_BYTES := SH_OFS + 0x100
const SH_W := 16                         ## shadow ellipse (px)
const SH_H := 6

var g = null                             ## the QoLGame
var _rng := RandomNumberGenerator.new()
var _slots: Array = []                   ## MAX_ALIVE x (null or [x, y, vy, age, phase, land_y, x0])
var _wait := FIRST_WAIT
var _last := -2                          ## port frame of the last tick
var _t := 0
var _cool := {}                          ## record -> frames left
var _tex := PackedByteArray()            ## the texture block's bytes (TEX_BYTES): frames, shadow
var _ready := false                      ## our block is reserved and holds _tex: bombs may spawn / be drawn
var _qb: Array = []                      ## per slot, per picture frame: the bomb quad's GX commands (read-only, built once)
var _qs: Array = []                      ## per slot: the shadow quad's GX commands
var _w := 11
var _h := 12
var _dbg := Game.args.has("bombdbg")
var _vdbg := Game.args.has("bombvram")
var _pdbg := Game.args.has("bombpos")
var _rate := maxf(0.05, float(Game.flag("bombrate", "1")))
var _us_tick := 0                        ## debug timing (bombdbg)
var _n_tick := 0
var _us_draw := 0
var _n_draw := 0
var _hidden := false
var _cv_draw: Array = []                 ## camera of the last drawn battle frame (see draw)
var _fxc := 0                            ## debug: bombfxcycle
var _hw := 0                             ## slots in use since the last time none was alive (all drawn)


func _init(game, img: Image) -> void:
	g = game
	var t0 := Time.get_ticks_usec()
	_load_art(img)
	for i in MAX_ALIVE:
		var fr: Array = []
		for f in FRAMES:
			fr.append(_quad(f * FR_BYTES, 1, PID_BOMB, i, _w, _h))
		_qb.append(fr)
		_qs.append(_quad(SH_OFS, 0, PID_SHADOW, 8 + i, SH_W, SH_H))
	if _dbg:
		print("BOMB art prepared in %d us" % (Time.get_ticks_usec() - t0))
	reset()


## the picture (main thread, when QoLGame is created: loading a texture on the game thread would wait for the main
## thread, which waits for the game thread); null when it is missing
static func load_image() -> Image:
	var tex = load(PNG) if ResourceLoader.exists(PNG) else null
	if not tex is Texture2D:
		push_warning("BOMB RAIN: %s missing" % PNG)
		return null
	var img: Image = (tex as Texture2D).get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	return img


func reset() -> void:
	_rng.seed = int(Game.flag("bombseed", str(SEED)))
	_slots.clear()
	for i in MAX_ALIVE:
		_slots.append(null)
	_wait = FIRST_WAIT
	_cool.clear()
	_hw = 0
	_t = 0
	_hidden = false
	_cv_draw = []
	_ready = false                                   # the manager is rebuilt with the scene: checked again


## the picture -> direct-colour texels (bit 15 = opaque): frame f = 16x16 at f * FR_BYTES (the 11x12 picture in its
## top-left corner), then the shadow (16x8, a 16x6 black ellipse)
func _load_art(img: Image) -> void:
	_tex = PackedByteArray()
	if img == null:
		return
	_w = img.get_width() / FRAMES
	_h = img.get_height()
	if _w > 16 or _h > 16 or img.get_width() != _w * FRAMES:
		push_warning("BOMB RAIN: %s must be %d frames of at most 16x16 px" % [PNG, FRAMES])
		return
	_tex.resize(TEX_BYTES)
	for f in FRAMES:
		for y in _h:
			for x in _w:
				var c := img.get_pixel(f * _w + x, y)
				if c.a >= 0.5:
					_tex.encode_u16(f * FR_BYTES + (y * 16 + x) * 2, _c15(c) | 0x8000)
	for r in [[4, 0, 8, 6], [1, 1, 14, 4], [0, 2, 16, 2]]:   # the ellipse (the part 25 shadow's three rectangles)
		for y in range(r[1], r[1] + r[3]):
			for x in range(r[0], r[0] + r[2]):
				_tex.encode_u16(SH_OFS + (y * 16 + x) * 2, 0x8000)
	g._tex_block().put(0, _tex)                     # part 36: the shared block (qol_texblock.gd)


func _c15(c: Color) -> int:
	return int(c.r * 31.0 + 0.5) | (int(c.g * 31.0 + 0.5) << 5) | (int(c.b * 31.0 + 0.5) << 10)


## Our texture block (part 36: qol_texblock.gd, shared with GREEN DEMON; the reservation in the game's texture VRAM
## manager and the texel writes are described there). False (no bombs) when the layout is not the battle's.
func _tex_ok() -> bool:
	if _tex.is_empty():
		return false
	return g._tex_block().ok()


func _ld(a: int, n: int, s: bool = false) -> int:
	return g._ld(a, n, s)


func _st(a: int, n: int, v: int) -> void:
	g._st(a, n, v)


## (diagnostic, flag bombvram) VRAMCNT, texture slots and the game's texture VRAM manager (u32 0x020DE380)
func _vram_diag(pf: int) -> void:
	var hw = g.hw
	var cnt := PackedStringArray()
	for i in 9:
		cnt.append("%02x" % hw.vramcnt[i])
	var mg: int = _ld(0x020DE380, 4)
	var s := "VRAM f%d cnt %s tex %s pal %s gen %s" % [pf, ",".join(cnt), str(hw.tex_slots), str(hw.texpal_slots), str(hw.bank_gen)]
	if mg != 0:
		var n: int = _ld(mg + 0x7AE, 1)
		var used := 0
		var top := 0
		var bl := PackedStringArray()
		for i in n + 2:
			var p: int = _ld(mg + 0x600 + i * 4, 4)
			var o: int = _ld(p, 4)
			var z: int = _ld(p + 4, 4)
			if i > 0 and i <= n:
				used += z
				top = maxi(top, o + z)
			bl.append("%x+%x:%x" % [o, z, _ld(p + 8, 4)])
		var np: int = _ld(mg + 0x8B8, 1)
		var pe := 0
		for i in np:
			pe = maxi(pe, _ld(mg + 0x7B4 + i * 4, 2) + _ld(mg + 0x7B6 + i * 4, 2))
		s += " | mgr blocks %d used %x top %x pal slots %d top %x | %s" % [n, used, top, np, pe, " ".join(bl)]
	print(s)


func _active() -> Array:
	var teams: int = _ld(TEAMS, 4)
	var r: Array = []
	for side in 2:
		var tb := teams + side * 0x8E8
		r.append(tb + _ld(tb + 0x8C8, 1) * 0x2D8)
	return r


func _floor_y() -> float:
	return float(_ld(_ld(_ld(0x0201B49C, 4), 4) + 0xCC2, 2) + 64)   # where fighters' feet stand (BLOOD's BL_FEET)


## camera: [x at screen x cam30, y at screen y cam34, cam30, cam34, zoom (1.0 = 256)]
func _cam() -> Array:
	var cam: int = _ld(CAMERA, 4)
	return [_ld(cam + 0xC, 4, true), _ld(cam + 0x10, 4, true), _ld(cam + 0x30, 4, true), _ld(cam + 0x34, 4, true),
		maxf(_ld(cam + 6, 2) / 256.0, 0.05)]


## once per battle frame (QoLGame's FUN_0202954C override, before the first fighter of the frame runs)
func tick(port_frame: int) -> void:
	if port_frame == _last:
		return
	_last = port_frame
	var t0 := Time.get_ticks_usec()
	_tick(port_frame)
	_us_tick += Time.get_ticks_usec() - t0
	_n_tick += 1


func _tick(port_frame: int) -> void:
	var st: int = _ld(BATTLE_STATE, 1)
	var act := _active()
	if _vdbg and port_frame % 20 == 0:
		_vram_diag(port_frame)
	if _dbg and port_frame % 60 == 0:
		var cm: int = _ld(CAMERA, 4)
		print("BOMB f%d state %d pause/cut-in %d tag %d camera mode %d wait %d alive %d; avg us tick %d draw %d" % [port_frame, st,
			g.f_02012fd4(), _ld(_ld(TEAMS, 4) + 0x11DC, 4), _ld(cm, 2) if cm != 0 else -1, _wait, _hw, _us_tick / maxi(_n_tick, 1),
			_us_draw / maxi(_n_draw, 1)])
		_us_tick = 0
		_n_tick = 0
		_us_draw = 0
		_n_draw = 0
	var ko := false
	for r in act:
		if _ld(r + 0x24A, 2, true) <= 0:
			ko = true
	if not ko and (st == 8 or (st >= 9 and st <= 0xE)):
		return                                       # pause 9, events inside the fight 8 / 0xA-0xE: frozen
	if st != 7 or ko:
		if _hw > 0 and _dbg:
			print("BOMB f%d gone (battle state %d, KO %s)" % [port_frame, st, ko])
		if _hw > 0:
			for i in MAX_ALIVE:
				_slots[i] = null
			_hw = 0
		if st != 7:
			_wait = FIRST_WAIT
		return
	if g.f_02012fd4() != 0 or _ld(_ld(TEAMS, 4) + 0x11DC, 4) != 0:
		return                                       # pause / cut-in, tag change: frozen
	var cam: int = _ld(CAMERA, 4)
	if cam != 0 and _ld(cam, 2) != 0:
		return                                       # super / team arts camera: frozen
	_hidden = false
	for r in act:
		if _ld(r + 6, 1) == 0x34:
			_hidden = true                           # throw / clash sequence (~240 frames): frozen and not drawn
			return
	_t += 1
	_ready = _tex_ok()                               # part 26: our texture block (no bombs without it)
	for r in _cool.keys():
		_cool[r] -= 1
		if _cool[r] <= 0:
			_cool.erase(r)
	# part 30: a LAN battle uses the game's own camera (the drawn one includes this machine's CAMERA ZOOM)
	var cv: Array = _cv_draw if not _cv_draw.is_empty() and not g.lan_battle() else _cam()
	var floor_y := _floor_y()
	_wait -= 1
	if _wait <= 0 and _ready:
		_wait = int(_rng.randi_range(GAP_MIN, GAP_MAX) / _rate)
		_spawn(cv, act, floor_y, port_frame)
	var live := 0
	for i in MAX_ALIVE:
		var b = _slots[i]
		if b == null:
			continue
		b[3] += 1
		b[2] = minf(b[2] + VA, VMAX)
		b[1] += b[2]
		b[0] = b[6] + SWAY * _sin(b[3] * 0.07 + b[4])
		var x: float = b[0]
		var y: float = b[1]
		var hit := -1
		var bx0 := x - _w * 0.5 + 1.0
		var bx1 := x + _w * 0.5 - 1.0
		var by0 := y - _h * 0.5 + 3.0                # the fuse spark does not count
		var by1 := y + _h * 0.5
		for r in act:
			if absf(_ld(r + 0x38, 4, true) / 256.0 - x) > 96.0 or absf(_ld(r + 0x3C, 4, true) / 256.0 - y) > 112.0:
				continue                                 # far away: skip the hurt box (FUN_0201DF20 is not free)
			if not _hittable(r):
				continue
			var hb := _hurtbox(r)
			if bx1 >= hb[0] and bx0 <= hb[2] and by1 >= hb[1] and by0 <= hb[3]:
				hit = r
				break
		if hit >= 0:
			_explode(x, y, hit, act, port_frame)
			_slots[i] = null
			continue
		if by1 >= b[5]:
			_explode(x, b[5] - 6.0, -1, act, port_frame)
			_slots[i] = null
			continue
		var bottom: float = cv[1] + (192.0 - cv[3]) / maxf(cv[4], 0.05)
		if y - _h > bottom + 24.0 or b[3] > 1200:
			if _dbg:
				print("BOMB f%d slot %d left the picture at %.0f,%.0f (dodged)" % [port_frame, i, x, y])
			_slots[i] = null
			continue
		live += 1
	if live == 0:
		_hw = 0


func _spawn(cv: Array, act: Array, floor_y: float, pf: int) -> void:
	var slot := -1
	for i in MAX_ALIVE:
		if _slots[i] == null:
			slot = i
			break
	if slot < 0:
		return
	var z: float = maxf(cv[4], 0.05)
	var left: float = cv[0] + (0.0 - cv[2]) / z
	var right: float = cv[0] + (256.0 - cv[2]) / z
	var top: float = cv[1] + (0.0 - cv[3]) / z
	var who: int = act[_rng.randi_range(0, 1)]
	var x := _ld(who + 0x38, 4, true) / 256.0 + _rng.randf_range(-80.0, 80.0)
	x = clampf(x, left + 12.0, right - 12.0)
	var y := top - _h * 0.5 - 2.0
	var land := floor_y + _rng.randf_range(0.0, 8.0)
	var ph := _rng.randf_range(0.0, TAU)
	if y + _h * 0.5 >= land:
		return
	_slots[slot] = [x, y, V0, 0, ph, land, x - SWAY * _sin(ph)]
	_hw = maxi(_hw, slot + 1)
	if _dbg:
		print("BOMB f%d spawn slot %d at %.0f,%.0f (view x %.0f..%.0f, floor %.0f, zoom %.2f, g %d) near %x" % [pf, slot, x, y,
			left, right, land, z, _ld(_ld(0x020DE384, 4) + 0x184, 4, true), who])


## part 30: in a LAN battle the game's sine table (s16, 256 steps per turn, 1.0 = 256) instead of the C runtime's sin,
## so the bombs move the same on every OS (LAN_DESIGN 1.2); elsewhere unchanged
func _sin(a: float) -> float:
	if not g.lan_battle():
		return sin(a)
	var i := int(floor(a * 256.0 / TAU)) & 0xFF
	return _ld(0x020B64D4 + i * 2, 2, true) / 256.0


func _hittable(r: int) -> bool:
	if _cool.has(r) or _ld(r + 0x24A, 2, true) <= 0 or (_ld(r + 0x12, 2) & 8) != 0:
		return false
	if (_ld(r + 0x250, 4) & 0x800) != 0:
		return false                                 # frozen (game-controlled sequence)
	var a: int = _ld(r + 6, 1)
	return not (a in [0x13, 0x14, 0x15, 0x33])       # intro / win poses, KO


## hurt box (type 2, first) as FUN_0201EE60 reads it: [x0, y0, x1, y1] world px
func _hurtbox(r: int) -> Array:
	g.f_0201df20(BOX, r, 2, 0)
	return [_ld(BOX, 2, true), _ld(BOX + 2, 2, true), _ld(BOX + 4, 2, true), _ld(BOX + 6, 2, true)]


func _explode(x: float, y: float, direct: int, act: Array, pf: int) -> void:
	var own: int = act[0]
	var kind := int(Game.flag("bombkind", str(EXPL_KIND)))
	var arg := EXPL_DIRECT if direct >= 0 else EXPL_GROUND
	if Game.args.has("bombfx"):
		arg = (int(Game.flag("bombfx")) << 16) | 8
	if Game.args.has("bombfxcycle"):
		_fxc += 1
		arg = ((_fxc % 5) << 16) | 8
	var o: int = g.f_0202247c(own, kind)
	if o != 0:
		g.f_0202216c(o, arg, 0)
		_st(o + 0x38, 4, int(x * 256.0) & 0xFFFFFFFF)
		_st(o + 0x3C, 4, int(y * 256.0) & 0xFFFFFFFF)
	g.f_02029e3c(own, SE_BOOM)
	if _dbg:
		var pool: int = _ld(0x020DE3CC, 4)
		print("BOMB f%d %s at %.0f,%.0f effect %x kind %d arg %x (kind table hit handler %x)" % [pf, "DIRECT HIT" if direct >= 0 else "ground blast",
			x, y, o, kind, arg, _ld(_ld(pool + 0x4F10, 4) + EXPL_KIND * 8 + 4, 4)])
	for r in act:
		if not _hittable(r):
			continue
		if r == direct:
			_hurt(r, DIRECT, 0x500, 0x11, x, y, pf)
			continue
		var hb := _hurtbox(r)
		var dx := maxf(maxf(hb[0] - x, x - hb[2]), 0.0)
		var dy := maxf(maxf(hb[1] - y, y - hb[3]), 0.0)
		var d := sqrt(dx * dx + dy * dy)
		if d <= BLAST_R:
			_hurt(r, lerpf(BLAST_MAX, BLAST_MIN, d / BLAST_R), 0x380, 0xF, x, y, pf)


## the game's ki-blast hit (FUN_0201E9EC, not guarded): push FUN_020213A8, HP FUN_020293A4, reaction FUN_02021B4C,
## stun +0x25E, hit flag +0x250 |= 2. Guarded: guard spark, a quarter of the damage (HP stays >= 1), guard push only.
func _hurt(r: int, frac: float, push: int, react: int, x: float, y: float, pf: int) -> void:
	var mx: int = _ld(r + 0x24C, 2)
	var hp: int = _ld(r + 0x24A, 2, true)
	var want := maxi(1, int(round(mx * frac)))
	var guard := (_ld(r + 0x250, 4) & 1) != 0
	var hb := _hurtbox(r)
	var cx: float = (hb[0] + hb[2]) * 0.5
	var cy: float = (hb[1] + hb[3]) * 0.5
	var dir := 0x10 if cx >= x else 0x70             # away from the blast, a little upward (0 right, 0x40 up)
	if guard:
		want = mini(maxi(1, want / GUARD_DIV), hp - 1)
		var s: int = g.f_0202247c(r, GUARD_SPARK)
		if s != 0:
			_st(s + 0x38, 4, int(cx * 256.0) & 0xFFFFFFFF)
			_st(s + 0x3C, 4, int(cy * 256.0) & 0xFFFFFFFF)
		g.f_020213a8(r, push / 3, -0x40, 0, dir)
	else:
		g.f_020213a8(r, push, -0x40, 0, dir)
	var sc: int = _ld(_ld(TEAMS, 4) + 0x1676, 2)     # FUN_020293A4 scales by this / 256: undo it
	var arg := 0
	if want > 0 and sc > 0:
		arg = (want * 256 + sc - 1) / sc
		g.f_020293a4(r, arg, 0)
	if not guard:
		if _ld(r + 6, 1) != 0x33:
			_st(r + 0x250, 4, 0)
			_st(r + 0x25D, 1, _ld(r + 0x1A, 1))
			g.f_02021b4c(r, react)
		_st(r + 0x25E, 2, 10)
		_st(r + 0x250, 4, _ld(r + 0x250, 4) | 2)
	_cool[r] = COOL
	if _dbg:
		print("BOMB f%d damage rec %x side %d %s %.1f%% of %d: want %d arg %d (scale %d) hp %d -> %d act %x" % [pf, r, _ld(r + 0x1A, 1),
			"GUARDED" if guard else ("direct" if react == 0x11 else "blast"), frac * 100.0, mx, want, arg, sc, hp,
			_ld(r + 0x24A, 2, true), _ld(r + 6, 1)])


## after the game's sprite list (QoLGame._fx_draw); cv = [cam x, cam y, cam30, cam34, zoom]
func draw(cv: Array) -> bool:
	_cv_draw = cv                                   # the view as drawn (CAMERA ZOOM applies only while drawing)
	if _hw == 0 or not _ready or _hidden:
		return false
	var t0 := Time.get_ticks_usec()
	_draw(cv)
	_us_draw += Time.get_ticks_usec() - t0
	_n_draw += 1
	return true


func _draw(cv: Array) -> void:
	var z: float = cv[4]
	if absf(z - 1.0) < 0.02:
		z = 1.0
	var out: Array = g.gx_cmds
	# shadows (black ellipses on the floor like the game's own fighter shadows; smaller while the bomb is high)
	for i in _hw:
		var b = _slots[i]
		var sx := -4000.0                               # a free slot: off screen (keeps the polygon numbers of the
		var sy := -4000.0                               # later slots: smooth motion pairs polygons by number)
		var sc := 1.0
		if b != null:
			sx = cv[2] + z * (float(b[0]) - cv[0])
			sy = cv[3] + z * (float(b[5]) - cv[1])
			var hgt := float(b[5]) - (float(b[1]) + _h * 0.5)
			sc = maxf(0.25, clampf(1.0 - hgt / 240.0, 0.4, 1.0) * z)
		_mtx(out, 16.0 * sc, floorf(sx - SH_W * 0.5 * sc), floorf(sy - SH_H * 0.5 * sc), float(Z_SHADOW))
		out.append_array(_qs[i])
	var s := 16.0 * z
	for i in _hw:
		var b = _slots[i]
		var tx := -4000.0
		var ty := -4000.0
		var f := 0
		if b != null:
			tx = floorf(cv[2] + z * (float(b[0]) - cv[0]) - _w * z * 0.5)
			ty = floorf(cv[3] + z * (float(b[1]) - cv[1]) - _h * z * 0.5)
			var a: int = b[3]
			f = ((a / 8) % 2) * 3 + (a / 3 + i) % 3   # feet every 8 frames, spark every 3
			if _pdbg:
				print("BOMBD f%d slot %d at %d,%d frame %d cmds %d" % [g._port_frame(), i, tx, ty, f, out.size()])
		_mtx(out, s, tx, ty, float(Z_BOMB))
		out.append_array(_qb[i][f])


## MTX_MODE position, MTX_PUSH, MTX_MULT_4x3 (scale s in x / y: a vertex unit of 1/16 = 1 px at s 16)
func _mtx(out: Array, s: float, tx: float, ty: float, tz: float) -> void:
	out.append([0x4000440, 2])
	out.append([0x4000444, 0])
	for v in [s, 0.0, 0.0, 0.0, s, 0.0, 0.0, 0.0, 1.0, tx, ty, tz]:
		out.append([0x4000464, int(roundf(v * 4096.0)) & 0xFFFFFFFF])


## The commands of one textured quad w x h px (texel = px) of the 16 x (8 << th) direct-colour texture at our block +
## `ofs`, then MTX_POP (built once per slot and picture frame, appended after the matrix). PLTT_BASE (unused by
## direct colour) = `key`, unique per bomb / shadow slot: the renderer's smooth motion pairs a polygon with the previous list's polygon of the same number only when POLYGON_ATTR, TEXIMAGE_PARAM, PLTT_BASE
## and texture coordinates are equal, so a bomb is never paired with another bomb, and a new picture frame (another
## TEXIMAGE_PARAM) is simply not blended for one game frame - the whole quad moves together either way. The commands
## are appended to the core's GX command log (DSCoreBase.gx_cmds, what io_write records for 0x04000400-0x040005FF; the
## GX ports are write-only, so nothing else is lost) in one go, like part 25 did.
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
