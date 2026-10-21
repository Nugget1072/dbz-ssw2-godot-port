extends RefCounted
## HITBOXES (part 45, settings page 3; QoLSettings.hitboxes, test flag `weird=hitbox`): the game's own collision boxes
## drawn over the battle, like a fighting game's training mode. Owned by QoLGame (`# ---- HITBOXES (part 45)`), which
## calls draw() from _fx_draw (after the game's sprite list, before DAMAGE NUMBERS). Drawing only: nothing here writes
## game RAM, so battles, LAN lockstep and records are the same with it on.
## The boxes are the ones the collision pass FUN_0201E5BC tests (DATA_NOTES part 39 "Collision pass"): the frame
## descriptor u32 [obj+0x120] (u16 +6 count, 12-byte boxes from +8: s16 x, y, w, h, s32 type), x scaled by u16 +0x154
## and y by u16 +0x156 (>> 8), mirrored when 0x40 < +7 < 0xC1, placed at the object's position +0x38 / +0x3C (>> 8).
## - BLUE = hurt boxes (types 2 and 4), only while the object takes part in the pass (+4 != 0); drawn first;
## - RED = hit boxes (type 1), only while the object's hit handler u32 [+0x34] is a real attack (not the no-op
##   0x02020EC4 / no-damage 0x0201F74C / 0): the frames on which the box can land a hit; drawn over the blue ones (a ki
##   blast's hit and hurt boxes are the same rectangle: it shows red).
## - Beams: the beam-body handler FUN_0201F0E4 only uses its (huge) box as a first test; a hit needs the victim's
##   position inside the band of 32 px above / below the line from u32 [obj] to u32 [[obj]] (slope from the second
##   one's +7 and the game's sine table 0x020B64D4; a near-vertical beam, +7 0x3C-0x44 / 0xBC-0xC4: 32 px left / right),
##   within their bounding box +-32 px. That band is drawn instead of the box (DATA_NOTES part 45).
## Objects: every fighter record (both teams, supports, ASSIST SPAM copies) and every live effect object (ki blasts,
## beams, super parts; pool [0x020DE3CC], 48 x 0x164, +4 bit 0 alive) whose sprite (+0x124) was drawn this frame.
## Each box = a faint translucent fill + a 1 px opaque outline, in screen px through the battle camera (zoom included).

const NOOP_HIT := 0x02020EC4
const NO_DAMAGE_HIT := 0x0201F74C
const BEAM_HIT := 0x0201F0E4
const SIN := 0x020B64D4                  ## s16[256] sine table (4.12), cosine = index + 0x40
const BAND := 32                         ## world px (0x2000 >> 8)
const POOL := 0x020DE3CC                 ## u32 -> effect objects
const POOL_N := 48
const POOL_SIZE := 0x164
const RED := 0x111F                      ## (31, 8, 4)
const BLUE := 0x7D44                     ## (4, 10, 31)
const FILL_AL := 7                       ## fill alpha (0-31)
const PID := 0x20                        ## polygon ID (port effects 0x20-0x3F; game sprites 1-31): overlapping fills of
										 ## one ID never darken each other; the opaque outlines draw over them
const Z_FILL := 32                       ## above the fighters' effects, below DAMAGE NUMBERS (40) and the HUD markers
const Z_LINE := 33
const FXK_HB := 0x0100                   ## PLTT_BASE pairing keys: 0x100 + object slot * 12 + polygon (QoLGame FXK_* list)
const QUADS := 12                        ## keys per object; more polygons share the last key
const SLOT_POOL := 14                    ## key slots 0-13 fighter records, 14-61 the effect pool

var g = null                             ## the QoLGame
var _dbg := Game.args.has("hbdbg")


func _init(game) -> void:
	g = game


func _ld(a: int, n: int, s := false) -> int:
	return g._ld(a, n, s)


## after the game's sprite list: idx = sprite objects drawn this frame, cv = camera [x, y, screen x, screen y, zoom]
func draw(idx: Dictionary, cv: Array) -> bool:
	var objs: Array = []                                # [object, key slot]
	var recs: Array = g._fx_recs()
	for i in recs.size():
		objs.append([recs[i], mini(i, SLOT_POOL - 1)])
	var pool: int = _ld(POOL, 4)
	if pool != 0:
		for i in POOL_N:
			var o := pool + i * POOL_SIZE
			if (_ld(o + 4, 1) & 1) != 0:
				objs.append([o, SLOT_POOL + i])
	var hurt: Array = []                                # [world polygon, key slot]
	var hit: Array = []
	for e in objs:
		var o: int = e[0]
		if not idx.has(o + 0x124):
			continue                                    # not drawn this frame (tagged out, hidden, another scene)
		var hd: int = _ld(o + 0x34, 4)
		var hit_live: bool = hd != NOOP_HIT and hd != NO_DAMAGE_HIT and hd != 0
		var hurt_live: bool = _ld(o + 4, 1) != 0
		var bs := _boxes(o)
		if _dbg and g._port_frame() % 8 == 0 and not bs.is_empty():
			print("HB f%d obj %x slot %d act %x hit %x +4 %x boxes %s" % [g._port_frame(), o, e[1], _ld(o + 6, 1), hd, _ld(o + 4, 1), str(bs)])
		for b in bs:
			var t: int = b[4]
			var x1: int = b[2] + 1                      # the game's tests are inclusive (<=): the last px is inside
			var y1: int = b[3] + 1
			var r := [Vector2(b[0], b[1]), Vector2(x1, b[1]), Vector2(x1, y1), Vector2(b[0], y1)]
			if (t == 2 or t == 4) and hurt_live:
				hurt.append([r, e[1]])
			elif t == 1 and hit_live:
				if hd == BEAM_HIT:
					var band := _beam_band(o)
					if not band.is_empty():
						hit.append([band, e[1]])
				else:
					hit.append([r, e[1]])
	var q := {}                                         # key slot -> next polygon
	for h in hurt:
		_poly(h[0], BLUE, cv, h[1], q)
	for h in hit:
		_poly(h[0], RED, cv, h[1], q)
	if _dbg and not (hurt.is_empty() and hit.is_empty()):
		print("HB f%d hurt %d hit %d" % [g._port_frame(), hurt.size(), hit.size()])
	return not (hurt.is_empty() and hit.is_empty())


## the object's boxes as [x0, y0, x1, y1, type] world px, exactly as FUN_0201E5BC places them (qol_ultra.gd _boxes)
func _boxes(o: int) -> Array:
	var d: int = _ld(o + 0x120, 4)
	if d < 0x02000000 or d >= 0x02800000:
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
		var t: int = _ld(b + 8, 4, true)
		var bx: int = (sx * _ld(b, 2, true)) >> 8
		var bw: int = (sx * _ld(b + 4, 2, true)) >> 8
		var y0: int = y + ((sy * _ld(b + 2, 2, true)) >> 8)
		var y1: int = y0 + ((sy * _ld(b + 6, 2, true)) >> 8)
		if fa < 0xC1 and fa > 0x3F:
			var x1 := x - bx
			out.append([x1 - bw, y0, x1, y1, t])
		else:
			var x0 := x + bx
			out.append([x0, y0, x0 + bw, y1, t])
	return out


## FUN_0201F0E4's real hit area (world px polygon, [] if the beam's end objects are missing)
func _beam_band(o: int) -> Array:
	var a: int = _ld(o, 4)
	if a < 0x02000000 or a >= 0x02800000:
		return []
	var b: int = _ld(a, 4)
	if b < 0x02000000 or b >= 0x02800000:
		return []
	var ax := _ld(a + 0x38, 4, true) / 256.0
	var ay := _ld(a + 0x3C, 4, true) / 256.0
	var bx := _ld(b + 0x38, 4, true) / 256.0
	var by := _ld(b + 0x3C, 4, true) / 256.0
	var poly := [Vector2(minf(ax, bx) - BAND, minf(ay, by) - BAND), Vector2(maxf(ax, bx) + BAND, minf(ay, by) - BAND),
		Vector2(maxf(ax, bx) + BAND, maxf(ay, by) + BAND), Vector2(minf(ax, bx) - BAND, maxf(ay, by) + BAND)]
	var ang: int = _ld(b + 7, 1)
	if (ang >= 0x3C and ang <= 0x44) or (ang >= 0xBC and ang <= 0xC4):
		poly = _clip(poly, Vector2(1, 0), bx - BAND)    # |x - bx| < 32
		poly = _clip(poly, Vector2(-1, 0), -(bx + BAND))
	else:
		var sn: int = _ld(SIN + ang * 2, 2, true)
		var cs: int = _ld(SIN + ((ang + 0x40) & 0xFF) * 2, 2, true)
		var k := float(sn) / float(cs) if cs != 0 else 0.0
		# |(by - y) - (x - bx) * k| < 32  <=>  y + k x lies within (by + k bx - 32, by + k bx + 32)
		var c := by + k * bx
		poly = _clip(poly, Vector2(k, 1), c - BAND)
		poly = _clip(poly, Vector2(-k, -1), -(c + BAND))
	return poly


## Sutherland-Hodgman: the part of convex polygon `p` with n . v >= c
func _clip(p: Array, n: Vector2, c: float) -> Array:
	var out: Array = []
	for i in p.size():
		var s: Vector2 = p[i]
		var e: Vector2 = p[(i + 1) % p.size()]
		var ds := n.dot(s) - c
		var de := n.dot(e) - c
		if ds >= 0.0:
			out.append(s)
		if (ds >= 0.0) != (de >= 0.0):
			out.append(s + (e - s) * (ds / (ds - de)))
	return out


## a convex world polygon on screen: translucent fill (triangle fan) + 1 px opaque outline (one thin quad per edge)
func _poly(wp: Array, col: int, cv: Array, slot: int, q: Dictionary) -> void:
	if wp.size() < 3:
		return
	var z: float = cv[4]
	var sp: Array = []
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for v in wp:
		var s := Vector2(cv[2] + z * (v.x - cv[0]), cv[3] + z * (v.y - cv[1]))
		s = Vector2(clampf(s.x, -512.0, 768.0), clampf(s.y, -512.0, 704.0))
		sp.append(s)
		lo = Vector2(minf(lo.x, s.x), minf(lo.y, s.y))
		hi = Vector2(maxf(hi.x, s.x), maxf(hi.y, s.y))
	if hi.x < 0.0 or lo.x > 256.0 or hi.y < 0.0 or lo.y > 192.0:
		return                                          # off the picture
	var key: int = FXK_HB + slot * QUADS
	var n: int = q.get(slot, 0)
	_begin(0x80C0 | (FILL_AL << 16) | (PID << 24), col, Z_FILL, 0)
	for i in range(1, sp.size() - 1):
		_key(key, n)
		n += 1
		_vtx(sp[0])
		_vtx(sp[i])
		_vtx(sp[i + 1])
	_end()
	_begin(0x80C0 | (31 << 16) | (PID << 24), col, Z_LINE, 1)
	for i in sp.size():
		var a: Vector2 = sp[i]
		var b: Vector2 = sp[(i + 1) % sp.size()]
		var d := b - a
		if d.length() < 0.01:
			continue
		var m := Vector2(-d.y, d.x).normalized() * 0.5   # half a pixel each side: a 1 px line
		_key(key, n)
		n += 1
		_vtx(a + m)
		_vtx(b + m)
		_vtx(b - m)
		_vtx(a - m)
	_end()
	q[slot] = n


## GX: polygon attributes + colour, a 256x scale (vertex unit = 1 screen px / 16 in 4.12) at depth z, BEGIN_VTXS
func _begin(attr: int, col: int, z: int, prim: int) -> void:
	g.io_write(0x4000440, 4, 2)
	g.io_write(0x4000444, 4, 0)                         # MTX_PUSH
	for v in [256.0, 0.0, 0.0, 0.0, 256.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, float(z)]:
		g.io_write(0x4000464, 4, int(roundf(v * 4096.0)) & 0xFFFFFFFF)   # MTX_MULT_4x3
	g.io_write(0x40004A8, 4, 0)                         # TEXIMAGE_PARAM: no texture
	g.io_write(0x40004A4, 4, attr)
	g.io_write(0x4000480, 4, col)
	g.io_write(0x4000500, 4, prim)                      # BEGIN_VTXS: 0 triangles, 1 quads


func _end() -> void:
	g.io_write(0x4000504, 4, 0)
	g.io_write(0x4000448, 4, 1)                         # MTX_POP


## PLTT_BASE: unused without a texture; the polygon's smooth-motion pairing key (part 26)
func _key(key: int, n: int) -> void:
	g.io_write(0x40004AC, 4, key + mini(n, QUADS - 1))


## VTX_16 at screen px p (z 0 in the 256x space: the matrix's depth)
func _vtx(p: Vector2) -> void:
	g.io_write(0x4000488, 4, 0)                         # TEXCOORD 0 (keeps the polygon key stable)
	var x := int(roundf(p.x * 16.0)) & 0xFFFF
	var y := int(roundf(p.y * 16.0)) & 0xFFFF
	g.io_write(0x400048C, 4, x | (y << 16))
	g.io_write(0x400048C, 4, 0)
