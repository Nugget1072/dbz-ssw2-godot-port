class_name DSGX
extends RefCounted
## DS geometry engine (GBATEK "DS 3D Video"): interprets the commands the game sent this frame (ports
## 0x04000440-0x040005FF and packed FIFO words / display lists, recorded by DSCoreBase.gx_cmds) and produces
## screen-ready polygons: clip-space vertices already mapped to the current VIEWPORT, vertex colours (with the
## DS lighting equation), texture coordinates in texels and the polygon/texture attributes.
## Matrices use Godot's Projection with the DS row-vector convention (see _mat()).

const NPARAMS := {
	0x00: 0, 0x10: 1, 0x11: 0, 0x12: 1, 0x13: 1, 0x14: 1, 0x15: 0, 0x16: 16, 0x17: 12, 0x18: 16,
	0x19: 12, 0x1A: 9, 0x1B: 3, 0x1C: 3, 0x20: 1, 0x21: 1, 0x22: 1, 0x23: 2, 0x24: 1, 0x25: 1,
	0x26: 1, 0x27: 1, 0x28: 1, 0x29: 1, 0x2A: 1, 0x2B: 1, 0x30: 1, 0x31: 1, 0x32: 1, 0x33: 1,
	0x34: 32, 0x40: 1, 0x41: 0, 0x50: 1, 0x60: 1, 0x70: 3, 0x71: 2, 0x72: 1,
}

# output (per frame): one entry per vertex, triangles = 3 consecutive vertices
var out_pos := PackedVector4Array()   ## clip x, y, z, w (viewport applied)
var out_col := PackedColorArray()     ## vertex colour (0..1), alpha = polygon alpha
var out_uv := PackedVector2Array()    ## texture coordinate in texels
var out_attr := PackedInt32Array()    ## per vertex: polygon attr
var out_tex := PackedInt32Array()     ## per vertex: TEXIMAGE_PARAM
var out_pal := PackedInt32Array()     ## per vertex: PLTT_BASE
var out_uvbox := PackedVector4Array() ## per vertex: the triangle's texture coordinate range (min u, v, max u, v)
var out_prev := PackedVector4Array()  ## per vertex: screen motion (x, y) since the previous polygon list, z = 1 if
                                      ## known (QoL smooth motion: in-between frames move each vertex back by it)
var swap_params: int = 0

# state
var mtx_mode: int = 0
var proj := Projection.IDENTITY
var pos := Projection.IDENTITY
var vec := Projection.IDENTITY
var tex := Projection.IDENTITY
var proj_stack: Array = [Projection.IDENTITY]
var pos_stack: Array = []
var vec_stack: Array = []
var stack_ptr: int = 0
var clip := Projection.IDENTITY
var clip_dirty: bool = true

var color := Color(1, 1, 1)
var texcoord := Vector2.ZERO
var texcoord0 := Vector2.ZERO
var vtx := Vector3.ZERO
var polyattr_next: int = 0
var polyattr: int = 0
var teximage: int = 0
var pltt: int = 0
var dif := Color(0, 0, 0)
var amb := Color(0, 0, 0)
var spe := Color(0, 0, 0)
var emi := Color(0, 0, 0)
var use_shine: bool = false
var shininess := PackedFloat32Array()
var light_vec: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var light_col: Array = [Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK]
var viewport := Vector4i(0, 0, 255, 191)
var light_dirty: bool = true
var light_half: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var light_k := PackedFloat64Array()     ## per light: spe*lc, dif*lc, amb*lc for r, g, b (see _light_prep)

var prim_type: int = -1
var prim_p := PackedVector4Array([Vector4(), Vector4(), Vector4(), Vector4()])   ## current primitive's vertices
var prim_c := PackedColorArray([Color(), Color(), Color(), Color()])
var prim_u := PackedVector2Array([Vector2(), Vector2(), Vector2(), Vector2()])
var prim_o := PackedInt32Array([0, 0, 0, 0])   ## outcodes (see _outcode)
var prim_n: int = 0
var strip_n: int = 0

# packed FIFO decoding
var _fifo_cmds := PackedInt32Array()
var _fifo_params := PackedInt32Array()
var _fifo_need: int = 0
# direct port decoding
var _port_cmd: int = -1
var _port_params := PackedInt32Array()
var NP := PackedInt32Array()     ## NPARAMS as a 256-entry table


func _init() -> void:
	for i in 31:
		pos_stack.append(Projection.IDENTITY)
		vec_stack.append(Projection.IDENTITY)
	shininess.resize(128)
	light_k.resize(36)
	NP.resize(256)
	for k in NPARAMS:
		NP[k] = NPARAMS[k]


static func _s(v: int, bits: int) -> int:
	v &= (1 << bits) - 1
	return v - (1 << bits) if v & (1 << (bits - 1)) else v


static func _c5(v: int) -> Color:
	return Color((v & 31) / 31.0, ((v >> 5) & 31) / 31.0, ((v >> 10) & 31) / 31.0)


## DS matrix from 16 fixed-point (20.12) values in row-major order; v' = v * M becomes P * v with P's
## columns = M's rows.
static func _mat(m: Array) -> Projection:
	return Projection(Vector4(m[0], m[1], m[2], m[3]), Vector4(m[4], m[5], m[6], m[7]),
		Vector4(m[8], m[9], m[10], m[11]), Vector4(m[12], m[13], m[14], m[15]))


## Polygons accumulate until SWAP_BUFFERS (command 0x50); then they become the frame the 3D engine renders
## (out_*, `swaps` counts them). Without a swap the DS keeps rendering the previous polygon list - games skip
## the swap during hit-stop frames, and drawing nothing then made the whole 3D layer vanish.
var swaps: int = 0
var acc_pos := PackedVector4Array()
var acc_col := PackedColorArray()
var acc_uv := PackedVector2Array()
var acc_attr := PackedInt32Array()
var acc_tex := PackedInt32Array()
var acc_pal := PackedInt32Array()
var acc_uvbox := PackedVector4Array()
var acc_prev := PackedVector4Array()
## Every submitted polygon (also culled / off-screen ones, so the numbering stays stable) is kept for the next
## list: key (POLYGON_ATTR, TEXIMAGE_PARAM, PLTT_BASE), texture coordinates and clip-space vertices. A polygon
## with the same number and key in the previous list is the same polygon one frame earlier: each emitted vertex
## gets its previous screen position from the same clip-space weights of that polygon's vertices.
var poly_key := PackedInt64Array()        ## 3 per polygon
var poly_uv := PackedVector2Array()       ## 4 per polygon
var poly_v := PackedVector4Array()        ## 4 per polygon
var prev_key := PackedInt64Array()
var prev_uv := PackedVector2Array()
var prev_v := PackedVector4Array()
var _pv_ok: bool = false                  ## the polygon being emitted has a previous position
var _pv := PackedVector4Array([Vector4(), Vector4(), Vector4(), Vector4()])   ## the polygon in the previous list
var _cv := PackedVector4Array([Vector4(), Vector4(), Vector4(), Vector4()])   ## and now
const L0 := Vector4(1, 0, 0, 0)
const L1 := Vector4(0, 1, 0, 0)
const L2 := Vector4(0, 0, 1, 0)
const L3 := Vector4(0, 0, 0, 1)


## register the polygon of vertex slots `idx` (3 or 4) and find it in the previous list
func _poly_begin(idx: Array) -> void:
	var k := poly_key.size() / 3
	poly_key.append(polyattr)
	poly_key.append(teximage)
	poly_key.append(pltt)
	for j in 4:
		var s: int = idx[mini(j, idx.size() - 1)]
		poly_uv.append(prim_u[s])
		poly_v.append(prim_p[s])
	_pv_ok = k * 3 + 2 < prev_key.size() and prev_key[k * 3] == polyattr and prev_key[k * 3 + 1] == teximage \
		and prev_key[k * 3 + 2] == pltt
	if _pv_ok:
		for j in 4:
			if prev_uv[k * 4 + j] != poly_uv[k * 4 + j]:
				_pv_ok = false
				break
	if _pv_ok:
		for j in 4:
			_pv[j] = prev_v[k * 4 + j]
			_cv[j] = poly_v[k * 4 + j]


## screen motion since the previous list of the point with clip-space weights `lam` over the polygon's vertices
## (both positions unsnapped and computed the same way, so a still polygon gives exactly 0)
func _prev_of(lam: Vector4) -> Vector4:
	if not _pv_ok:
		return Vector4()
	var p := _pv[0] * lam.x + _pv[1] * lam.y + _pv[2] * lam.z + _pv[3] * lam.w
	var c := _cv[0] * lam.x + _cv[1] * lam.y + _cv[2] * lam.z + _cv[3] * lam.w
	var w := p.w
	var wc := c.w
	if w <= 0.0 or wc <= 0.0:
		return Vector4()
	var vw := float(viewport.z - viewport.x + 1)
	var vh := float(viewport.w - viewport.y + 1)
	return Vector4((p.x + w) * vw / (2.0 * w) - (c.x + wc) * vw / (2.0 * wc),
		(-p.y + w) * vh / (2.0 * w) - (-c.y + wc) * vh / (2.0 * wc), 1.0, 0.0)


func _swap() -> void:
	out_pos = acc_pos
	out_col = acc_col
	out_uv = acc_uv
	out_attr = acc_attr
	out_tex = acc_tex
	out_pal = acc_pal
	out_uvbox = acc_uvbox
	out_prev = acc_prev
	acc_prev = PackedVector4Array()
	prev_key = poly_key
	prev_uv = poly_uv
	prev_v = poly_v
	poly_key = PackedInt64Array()
	poly_uv = PackedVector2Array()
	poly_v = PackedVector4Array()
	acc_pos = PackedVector4Array()
	acc_col = PackedColorArray()
	acc_uv = PackedVector2Array()
	acc_attr = PackedInt32Array()
	acc_tex = PackedInt32Array()
	acc_pal = PackedInt32Array()
	acc_uvbox = PackedVector4Array()
	swaps += 1


## (kept for the debug tools: results of a frame are in out_* after its SWAP_BUFFERS)
func begin_frame() -> void:
	pass


## Process this frame's recorded commands. `core` is the ARM9 core (display lists not copied at DMA time are
## read from its main RAM).
func run(cmds: Array, core) -> void:
	for c in cmds:
		var a: int = c[0]
		if a == -1:   # display list by DMA into the FIFO: c = [-1, src, words, copied words]
			var words: PackedInt32Array
			if c.size() > 3:
				words = c[3]
			else:
				var o: int = c[1] - 0x02000000
				words = core.M.slice(o, o + int(c[2]) * 4).to_int32_array()
			_run_words(words)
		elif a < 0x4000440:
			_fifo_word(c[1])
		else:
			_port_write(a, c[1])


## packed FIFO words: a word with up to four command ids (lowest byte first, zero ids = padding) followed by
## all their parameters. Commands whose parameters are all in `words` run straight from it.
func _run_words(words: PackedInt32Array) -> void:
	var n := words.size()
	var i := 0
	while i < n:
		var w := words[i]
		if _fifo_need > 0:
			_fifo_word(w)
			i += 1
			continue
		if (w & -256) == 0:   # one command per word (the common case)
			var n1 := NP[w]
			if i + 1 + n1 > n:
				_fifo_word(w)
				i += 1
				continue
			# the per-vertex commands are handled here (same code as in _exec) to save a call per command
			if w == 0x22 and (teximage >> 30) & 3 != 1:   # TEXCOORD
				var v := words[i + 1]
				texcoord0 = Vector2((((v & 0xFFFF) ^ 0x8000) - 0x8000) / 16.0, ((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 16.0)
				texcoord = texcoord0
			elif w == 0x23:   # VTX_16
				var v := words[i + 1]
				vtx = Vector3((((v & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0, ((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0,
					(((words[i + 2] & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0)
				if prim_type >= 0:
					_vertex()
			elif w == 0x21:   # NORMAL
				_normal(words[i + 1])
			elif w != 0:
				_exec(w, words, i + 1)
			i += 1 + n1
			continue
		var id0 := w & 0xFF
		var id1 := (w >> 8) & 0xFF
		var id2 := (w >> 16) & 0xFF
		var id3 := (w >> 24) & 0xFF
		var n0 := NP[id0]
		var n1 := NP[id1]
		var n2 := NP[id2]
		var n3 := NP[id3]
		if i + 1 + n0 + n1 + n2 + n3 > n:
			_fifo_word(w)
			i += 1
			continue
		var o := i + 1
		if id0 != 0:
			_exec(id0, words, o)
		o += n0
		if id1 != 0:
			_exec(id1, words, o)
		o += n1
		if id2 != 0:
			_exec(id2, words, o)
		o += n2
		if id3 != 0:
			_exec(id3, words, o)
		i = o + n3


func _port_write(addr: int, v: int) -> void:
	var cmd := 0x10 + ((addr - 0x4000440) >> 2)
	var n: int = NP[cmd & 0xFF]
	if cmd != _port_cmd:
		_port_cmd = cmd
		_port_params.clear()
	if n == 0:
		_exec(cmd, _port_params, 0)
		_port_cmd = -1
		return
	_port_params.append(v)
	if _port_params.size() >= n:
		_exec(cmd, _port_params, 0)
		_port_params.clear()
		_port_cmd = -1


## one FIFO word at a time (port writes to GXFIFO, or a packed command split between transfers)
func _fifo_word(w: int) -> void:
	if _fifo_need > 0:
		_fifo_params.append(w)
		_fifo_need -= 1
		if _fifo_need == 0:
			_flush_fifo()
		return
	_fifo_cmds.clear()
	_fifo_params.clear()
	var total := 0
	for k in 4:
		var id := (w >> (8 * k)) & 0xFF
		_fifo_cmds.append(id)
		total += NP[id]
	_fifo_need = total
	if total == 0:
		_flush_fifo()


func _flush_fifo() -> void:
	var i := 0
	for id in _fifo_cmds:
		if id == 0:
			continue
		_exec(id, _fifo_params, i)
		i += NP[id]
	_fifo_cmds.clear()
	_fifo_params.clear()


func _cur_set(m: Projection) -> void:
	match mtx_mode:
		0: proj = m
		1: pos = m
		2:
			pos = m
			vec = m
		3: tex = m
	clip_dirty = true


func _cur() -> Projection:
	match mtx_mode:
		0: return proj
		3: return tex
	return pos


## M_new = N * M_cur (DS row-vector order) = P_cur * P_N with our column layout
func _mul(n: Projection) -> void:
	match mtx_mode:
		0: proj = proj * n
		1: pos = pos * n
		2:
			pos = pos * n
			vec = vec * n
		3: tex = tex * n
	clip_dirty = true


func _fx(v: int) -> float:
	return _s(v, 32) / 4096.0


## run one command; its parameters are p[o], p[o + 1], ... (most frequent commands first)
func _exec(cmd: int, p: PackedInt32Array, o: int) -> void:
	var v: int = p[o] if o < p.size() else 0
	if cmd >= 0x20 and cmd <= 0x28:
		match cmd:
			0x22:
				texcoord0 = Vector2((((v & 0xFFFF) ^ 0x8000) - 0x8000) / 16.0, ((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 16.0)
				texcoord = texcoord0
				if ((teximage >> 30) & 3) == 1:   # texcoord source: (s, t, 1/16, 1/16) * texture matrix
					var tv := tex * Vector4(texcoord0.x, texcoord0.y, 1.0 / 16.0, 1.0 / 16.0)
					texcoord = Vector2(tv.x, tv.y)
			0x21:
				_normal(v)
			0x23:
				vtx = Vector3((((v & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0, ((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0,
					(((p[o + 1] & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0)
				_vertex()
			0x26:
				vtx = Vector3((((v & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0, vtx.y, ((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0)
				_vertex()
			0x27:
				vtx = Vector3(vtx.x, (((v & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0, ((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0)
				_vertex()
			0x25:
				vtx = Vector3((((v & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0, ((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0, vtx.z)
				_vertex()
			0x28:
				vtx += Vector3((((v & 0x3FF) ^ 0x200) - 0x200) / 4096.0, ((((v >> 10) & 0x3FF) ^ 0x200) - 0x200) / 4096.0,
					((((v >> 20) & 0x3FF) ^ 0x200) - 0x200) / 4096.0)
				_vertex()
			0x24:
				vtx = Vector3(_s(v, 10) / 64.0, _s(v >> 10, 10) / 64.0, _s(v >> 20, 10) / 64.0)
				_vertex()
			0x20:
				color = _c5(v)
		return
	match cmd:
		0x40:
			prim_type = v & 3
			polyattr = polyattr_next
			prim_n = 0
			strip_n = 0
		0x41:
			prim_type = -1
			prim_n = 0
		0x10:
			mtx_mode = v & 3
		0x11:   # MTX_PUSH
			if mtx_mode == 0:
				proj_stack[0] = proj
			elif mtx_mode == 3:
				pass
			else:
				if stack_ptr < 31:
					pos_stack[stack_ptr] = pos
					vec_stack[stack_ptr] = vec
				stack_ptr = mini(stack_ptr + 1, 31)
		0x12:   # MTX_POP
			if mtx_mode == 0:
				proj = proj_stack[0]
			elif mtx_mode != 3:
				stack_ptr = clampi(stack_ptr - _s(v, 6), 0, 31)
				pos = pos_stack[stack_ptr]
				vec = vec_stack[stack_ptr]
			clip_dirty = true
		0x13:   # MTX_STORE
			if mtx_mode == 0:
				proj_stack[0] = proj
			elif mtx_mode != 3:
				var i: int = v & 31
				if i < 31:
					pos_stack[i] = pos
					vec_stack[i] = vec
		0x14:   # MTX_RESTORE
			if mtx_mode == 0:
				proj = proj_stack[0]
			elif mtx_mode != 3:
				var i: int = v & 31
				if i < 31:
					pos = pos_stack[i]
					vec = vec_stack[i]
			clip_dirty = true
		0x15:
			_cur_set(Projection.IDENTITY)
		0x16:
			_cur_set(_m44(p, o))
		0x17:
			_cur_set(_m43(p, o))
		0x18:
			_mul(_m44(p, o))
		0x19:
			_mul(_m43(p, o))
		0x1A:
			_mul(Projection(Vector4(_fx(p[o]), _fx(p[o + 1]), _fx(p[o + 2]), 0.0),
				Vector4(_fx(p[o + 3]), _fx(p[o + 4]), _fx(p[o + 5]), 0.0),
				Vector4(_fx(p[o + 6]), _fx(p[o + 7]), _fx(p[o + 8]), 0.0), Vector4(0.0, 0.0, 0.0, 1.0)))
		0x1B:   # MTX_SCALE (does not affect the vector matrix)
			var m := Projection(Vector4(_fx(v), 0, 0, 0), Vector4(0, _fx(p[o + 1]), 0, 0),
				Vector4(0, 0, _fx(p[o + 2]), 0), Vector4(0, 0, 0, 1))
			if mtx_mode == 2:
				pos = pos * m
				clip_dirty = true
			else:
				_mul(m)
		0x1C:   # MTX_TRANS
			_mul(Projection(Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0),
				Vector4(_fx(v), _fx(p[o + 1]), _fx(p[o + 2]), 1)))
		0x29:
			polyattr_next = v
		0x2A:
			teximage = v
		0x2B:
			pltt = v & 0x1FFF
		0x30:
			dif = _c5(v)
			amb = _c5(v >> 16)
			light_dirty = true
			if v & 0x8000:
				color = dif
		0x31:
			spe = _c5(v)
			emi = _c5(v >> 16)
			light_dirty = true
			use_shine = (v & 0x8000) != 0
		0x32:   # LIGHT_VECTOR: transformed by the vector matrix now
			var i: int = (v >> 30) & 3
			var d := Vector4(_s(v, 10) / 512.0, _s(v >> 10, 10) / 512.0, _s(v >> 20, 10) / 512.0, 0.0)
			var t := vec * d
			light_vec[i] = Vector3(t.x, t.y, t.z)
			light_dirty = true
		0x33:
			light_col[(v >> 30) & 3] = _c5(v)
			light_dirty = true
		0x34:
			for i in 32:
				for k in 4:
					shininess[i * 4 + k] = ((p[o + i] >> (8 * k)) & 0xFF) / 256.0
		0x50:
			swap_params = v
			_swap()
		0x60:
			viewport = Vector4i(v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255)


## 4x4 / 4x3 matrix parameters (row-major 20.12) as a Projection (see _mat)
func _m44(p: PackedInt32Array, o: int) -> Projection:
	return Projection(Vector4(_fx(p[o]), _fx(p[o + 1]), _fx(p[o + 2]), _fx(p[o + 3])),
		Vector4(_fx(p[o + 4]), _fx(p[o + 5]), _fx(p[o + 6]), _fx(p[o + 7])),
		Vector4(_fx(p[o + 8]), _fx(p[o + 9]), _fx(p[o + 10]), _fx(p[o + 11])),
		Vector4(_fx(p[o + 12]), _fx(p[o + 13]), _fx(p[o + 14]), _fx(p[o + 15])))


func _m43(p: PackedInt32Array, o: int) -> Projection:
	return Projection(Vector4(_fx(p[o]), _fx(p[o + 1]), _fx(p[o + 2]), 0.0),
		Vector4(_fx(p[o + 3]), _fx(p[o + 4]), _fx(p[o + 5]), 0.0),
		Vector4(_fx(p[o + 6]), _fx(p[o + 7]), _fx(p[o + 8]), 0.0),
		Vector4(_fx(p[o + 9]), _fx(p[o + 10]), _fx(p[o + 11]), 1.0))


## per-light constants: half vectors and material * light colour products (same evaluation order as the
## per-vertex sum, so the result is unchanged)
func _light_prep() -> void:
	light_dirty = false
	for i in 4:
		var lc: Color = light_col[i]
		light_half[i] = ((light_vec[i] as Vector3) + Vector3(0, 0, -1)) * 0.5
		var k := i * 9
		light_k[k] = spe.r * lc.r
		light_k[k + 1] = dif.r * lc.r
		light_k[k + 2] = amb.r * lc.r
		light_k[k + 3] = spe.g * lc.g
		light_k[k + 4] = dif.g * lc.g
		light_k[k + 5] = amb.g * lc.g
		light_k[k + 6] = spe.b * lc.b
		light_k[k + 7] = dif.b * lc.b
		light_k[k + 8] = amb.b * lc.b


func _normal(v: int) -> void:
	var n4 := Vector4((((v & 0x3FF) ^ 0x200) - 0x200) / 512.0, ((((v >> 10) & 0x3FF) ^ 0x200) - 0x200) / 512.0,
		((((v >> 20) & 0x3FF) ^ 0x200) - 0x200) / 512.0, 0.0)
	if ((teximage >> 30) & 3) == 2:   # texcoord from the normal
		var t := tex * n4
		texcoord = texcoord0 + Vector2(t.x, t.y)
	var t2 := vec * n4
	var n := Vector3(t2.x, t2.y, t2.z)
	var c := emi
	var en := polyattr_next & 15
	if en == 0:
		color = Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))
		return
	if light_dirty:
		_light_prep()
	for i in 4:
		if (en & (1 << i)) == 0:
			continue
		var lv: Vector3 = light_vec[i]
		var diffuse: float = maxf(0.0, -lv.dot(n))
		var half: Vector3 = light_half[i]
		var shine: float = maxf(0.0, -half.dot(n))
		shine = minf(shine * shine, 1.0)
		if use_shine:
			shine = shininess[clampi(int(shine * 127.0), 0, 127)]
		var k := i * 9
		c += Color(light_k[k] * shine + light_k[k + 1] * diffuse + light_k[k + 2],
			light_k[k + 3] * shine + light_k[k + 4] * diffuse + light_k[k + 5],
			light_k[k + 6] * shine + light_k[k + 7] * diffuse + light_k[k + 8], 0.0)
	color = Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))


func _vertex() -> void:
	if prim_type < 0:
		return
	if clip_dirty:
		clip = proj * pos
		clip_dirty = false
	var v4 := Vector4(vtx.x, vtx.y, vtx.z, 1.0)
	var uv := texcoord
	if ((teximage >> 30) & 3) == 3:   # texcoord from the vertex
		var t := tex * v4
		uv = texcoord0 + Vector2(t.x, t.y)
	var k := prim_n
	var cv := clip * v4
	prim_p[k] = cv
	var w := cv.w
	var oc := 0
	if w + cv.x < 0.0:
		oc = 1
	if w - cv.x < 0.0:
		oc |= 2
	if w + cv.y < 0.0:
		oc |= 4
	if w - cv.y < 0.0:
		oc |= 8
	if w + cv.z < 0.0:
		oc |= 16
	if w - cv.z < 0.0:
		oc |= 32
	prim_o[k] = oc
	prim_c[k] = color
	prim_u[k] = uv
	prim_n = k + 1
	match prim_type:
		0:
			if prim_n == 3:
				_tri(0, 1, 2)
				prim_n = 0
		1:
			if prim_n == 4:
				_quad4(0, 1, 2, 3)
				prim_n = 0
		2:
			if prim_n == 3:
				if strip_n & 1:
					_tri(1, 0, 2)
				else:
					_tri(0, 1, 2)
				strip_n += 1
				_shift(1, 0)
				_shift(2, 1)
				prim_n = 2
		3:
			if prim_n == 4:
				_quad4(0, 1, 3, 2)
				_shift(2, 0)
				_shift(3, 1)
				prim_n = 2


func _shift(src: int, dst: int) -> void:
	prim_p[dst] = prim_p[src]
	prim_c[dst] = prim_c[src]
	prim_u[dst] = prim_u[src]
	prim_o[dst] = prim_o[src]


## One triangle (vertex slots of the current primitive) with DS face culling (POLYGON_ATTR bit 6 = draw back
## faces, bit 7 = draw front faces), then clipping against the view volume (attributes interpolated linearly in
## clip space) and the viewport transform to integer screen positions, in that order, like the DS (GBATEK "DS 3D
## Polygon Definitions", melonDS GPU3D ClipPolygon / posX/posY).
## facing from the clip-space (x, y, w) triple product, valid for vertices behind the camera too (dividing by w
## flips those): v1 . ((v0 - v1) x (v2 - v1)) < 0 = front (GBATEK / melonDS GPU3D SubmitPolygon); 0 = edge-on
static func _facing(pa: Vector4, pb: Vector4, pc: Vector4) -> float:
	var nx := (pa.y - pb.y) * (pc.w - pb.w) - (pa.w - pb.w) * (pc.y - pb.y)
	var ny := (pa.w - pb.w) * (pc.x - pb.x) - (pa.x - pb.x) * (pc.w - pb.w)
	var nz := (pa.x - pb.x) * (pc.y - pb.y) - (pa.y - pb.y) * (pc.x - pb.x)
	return pb.x * nx + pb.y * ny + pb.w * nz


func _culled(dot: float) -> bool:
	if dot < 0.0:
		return (polyattr & 0x80) == 0
	if dot > 0.0:
		return (polyattr & 0x40) == 0
	return false


func _tri(ia: int, ib: int, ic: int) -> void:
	_poly_begin([ia, ib, ic])
	var pa := prim_p[ia]
	var pb := prim_p[ib]
	var pc := prim_p[ic]
	var ca := prim_o[ia]
	var cb := prim_o[ib]
	var cc := prim_o[ic]
	if (ca & cb & cc) != 0:   # entirely outside one plane: clipping would leave nothing
		return
	if (polyattr & 0xC0) != 0xC0 and _culled(_facing(pa, pb, pc)):
		return
	var alpha := ((polyattr >> 16) & 31) / 31.0
	if (ca | cb | cc) == 0:   # entirely inside the view volume (the common case): no clipping
		_emit_tri(pa, prim_c[ia], prim_u[ia], pb, prim_c[ib], prim_u[ib], pc, prim_c[ic], prim_u[ic], alpha, 0, L0, L1, L2)
		return
	_clip_emit([[pa, prim_c[ia], prim_u[ia], L0], [pb, prim_c[ib], prim_u[ib], L1], [pc, prim_c[ic], prim_u[ic], L2]], alpha)


## A quad is one polygon on the DS: it is culled and clipped as a whole (clipping its two triangles separately
## put the clipped points of the shared diagonal on different pixels: the MODE SELECT bar's step at the screen
## edge), then drawn as triangles whose shared diagonal is not dilated.
func _quad4(i0: int, i1: int, i2: int, i3: int) -> void:
	_poly_begin([i0, i1, i2, i3])
	var o0 := prim_o[i0]
	var o1 := prim_o[i1]
	var o2 := prim_o[i2]
	var o3 := prim_o[i3]
	if (o0 & o1 & o2 & o3) != 0:
		return
	if (polyattr & 0xC0) != 0xC0:
		var dot := _facing(prim_p[i0], prim_p[i1], prim_p[i2])
		if dot == 0.0:
			dot = _facing(prim_p[i0], prim_p[i2], prim_p[i3])
		if _culled(dot):
			return
	var alpha := ((polyattr >> 16) & 31) / 31.0
	if (o0 | o1 | o2 | o3) == 0:
		_emit_tri(prim_p[i0], prim_c[i0], prim_u[i0], prim_p[i1], prim_c[i1], prim_u[i1], prim_p[i2], prim_c[i2], prim_u[i2], alpha, 4, L0, L1, L2)
		_emit_tri(prim_p[i0], prim_c[i0], prim_u[i0], prim_p[i2], prim_c[i2], prim_u[i2], prim_p[i3], prim_c[i3], prim_u[i3], alpha, 1, L0, L2, L3)
		return
	_clip_emit([[prim_p[i0], prim_c[i0], prim_u[i0], L0], [prim_p[i1], prim_c[i1], prim_u[i1], L1],
		[prim_p[i2], prim_c[i2], prim_u[i2], L2], [prim_p[i3], prim_c[i3], prim_u[i3], L3]], alpha)


## clip a convex polygon ([position, colour, uv] per vertex) against the view volume and draw it as a fan; the
## fan's diagonals are inner edges (not dilated)
func _clip_emit(poly: Array, alpha: float) -> void:
	for plane in 6:
		poly = _clip_plane(poly, plane)
		if poly.size() < 3:
			return
	var pn := poly.size()
	for i in range(1, pn - 1):
		var v0: Array = poly[0]
		var v1: Array = poly[i]
		var v2: Array = poly[i + 1]
		var inn := (1 if i > 1 else 0) | (4 if i + 2 < pn else 0)
		_emit_tri(v0[0], v0[1], v0[2], v1[0], v1[1], v1[2], v2[0], v2[1], v2[2], alpha, inn, v0[3], v1[3], v2[3])


## DS polygon coverage: the rasteriser fills each scanline from the first pixel the left edge touches to the last
## pixel the right edge touches, so neighbouring polygons overlap by up to a pixel and small gaps between
## separate pieces of a model are closed (GBATEK "DS 3D Rendering"; matches melonDS captures). On the GPU this
## is the triangle dilated by just under half a pixel (every pixel the triangle touches), with the attributes
## extrapolated perspective-correctly from the snapped triangle. `dilate = false` draws the plain triangles.
var dilate: bool = true
const DILATE := 118.0 / 256.0   ## (0.461) < 0.5 by more than GPU sub-pixel precision, so pixels the polygon only
## touches at their border stay uncovered; a multiple of 1/256 px so the ring corners lie on the GPU's sub-pixel grid
const CORNER := [Vector2(DILATE, DILATE), Vector2(-DILATE, DILATE), Vector2(-DILATE, -DILATE), Vector2(DILATE, -DILATE)]


static func _quad(nx: float, ny: float) -> int:
	if nx > 0.0 and ny >= 0.0:
		return 0
	if nx <= 0.0 and ny > 0.0:
		return 1
	if nx < 0.0 and ny <= 0.0:
		return 2
	return 3


## one triangle (clip-space vertices inside the view volume): snap to the viewport's integer pixel grid and emit
func _emit_tri(pa: Vector4, ca: Color, ua: Vector2, pb: Vector4, cb: Color, ub: Vector2, pc: Vector4, cc: Color,
		uc: Vector2, alpha: float, inner: int = 0, la4: Vector4 = L0, lb4: Vector4 = L1, lc4: Vector4 = L2) -> void:
	var wa := pa.w
	var wb := pb.w
	var wc := pc.w
	if wa <= 0.0 or wb <= 0.0 or wc <= 0.0:
		return
	var vw := float(viewport.z - viewport.x + 1)
	var vh := float(viewport.w - viewport.y + 1)
	var ox := float(viewport.x)
	var oy := float(191 - viewport.w)
	var ax := floorf((pa.x + wa) * vw / (2.0 * wa) + 1e-4) + ox
	var ay := floorf((-pa.y + wa) * vh / (2.0 * wa) + 1e-4) + oy
	var bx := floorf((pb.x + wb) * vw / (2.0 * wb) + 1e-4) + ox
	var by := floorf((-pb.y + wb) * vh / (2.0 * wb) + 1e-4) + oy
	var cx := floorf((pc.x + wc) * vw / (2.0 * wc) + 1e-4) + ox
	var cy := floorf((-pc.y + wc) * vh / (2.0 * wc) + 1e-4) + oy
	var area := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
	# texture coordinates stay inside the triangle's range (the DS interpolates them between the span's edges;
	# the GPU's corner sampling and the dilation would otherwise reach texels outside the polygon)
	var box := Vector4(minf(ua.x, minf(ub.x, uc.x)), minf(ua.y, minf(ub.y, uc.y)),
		maxf(ua.x, maxf(ub.x, uc.x)), maxf(ua.y, maxf(ub.y, uc.y)))
	if not dilate:
		_emit(Vector4((ax / 128.0 - 1.0) * wa, (1.0 - ay / 96.0) * wa, pa.z, wa), ca, ua, alpha, box, _prev_of(la4))
		_emit(Vector4((bx / 128.0 - 1.0) * wb, (1.0 - by / 96.0) * wb, pb.z, wb), cb, ub, alpha, box, _prev_of(lb4))
		_emit(Vector4((cx / 128.0 - 1.0) * wc, (1.0 - cy / 96.0) * wc, pc.z, wc), cc, uc, alpha, box, _prev_of(lc4))
		return
	if area == 0.0:
		return
	# outline of the dilated triangle: at each vertex the square corners between the two edge normals
	var sx := PackedFloat64Array([ax, bx, cx])
	var sy := PackedFloat64Array([ay, by, cy])
	if area < 0.0:   # positive orientation (normals then turn in the corner order of CORNER)
		sx = PackedFloat64Array([ax, cx, bx])
		sy = PackedFloat64Array([ay, cy, by])
	var qs := PackedInt32Array([0, 0, 0])
	for i in 3:
		var j := (i + 1) % 3
		qs[i] = _quad(sy[j] - sy[i], sx[i] - sx[j])   # outward normal of edge i -> i+1
	# Pieces: the snapped triangle itself (corners on the pixel grid, so every GPU rebuilds its attribute planes
	# exactly), then the dilation ring around it: a band along each outer edge and a corner wedge at each vertex.
	# Edges inside the polygon (a quad's diagonal, the fan edges of a clipped polygon) get no band and the ring
	# is cut back to their line; the triangles of one polygon meet there under the GPU's fill rule. (One fan over
	# the whole dilated outline made long slivers whose planes GPUs rebuild from sub-pixel-snapped corners: on
	# some GPUs texels one row off next to a quad's diagonal, loose pixels on the scrolling menu bars.)
	var ino := PackedInt32Array([inner & 1, inner & 2, inner & 4]) if area > 0.0 \
		else PackedInt32Array([inner & 4, inner & 2, inner & 1])   # inner flags per oriented edge i -> i+1
	var pieces: Array = [PackedVector2Array([Vector2(sx[0], sy[0]), Vector2(sx[1], sy[1]), Vector2(sx[2], sy[2])])]
	for i in 3:
		var vi := Vector2(sx[i], sy[i])
		if ino[i] == 0:
			var o: Vector2 = CORNER[qs[i]]
			var vj := Vector2(sx[(i + 1) % 3], sy[(i + 1) % 3])
			pieces.append(PackedVector2Array([vi, vj, vj + o, vi + o]))
		var q := qs[(i + 2) % 3]
		var qe := qs[i]
		if q != qe:
			var wedge := PackedVector2Array([vi, vi + CORNER[q]])
			while q != qe:
				q = (q + 1) & 3
				wedge.append(vi + CORNER[q])
			pieces.append(wedge)
	var ex := PackedFloat64Array([ax, bx, cx])
	var ey := PackedFloat64Array([ay, by, cy])
	for e in 3:
		if (inner & (1 << e)) == 0:
			continue
		var e1 := (e + 1) % 3
		var e2 := (e + 2) % 3
		var dx := ex[e1] - ex[e]
		var dy := ey[e1] - ey[e]
		var ref := dx * (ey[e2] - ey[e]) - dy * (ex[e2] - ex[e])   # > 0 side = the triangle's side
		for pi in range(1, pieces.size()):
			var pts: PackedVector2Array = pieces[pi]
			var cut := PackedVector2Array()
			var np := pts.size()
			for k in np:
				var p0 := pts[k]
				var p1 := pts[(k + 1) % np]
				var s0 := (dx * (p0.y - ey[e]) - dy * (p0.x - ex[e])) * ref
				var s1 := (dx * (p1.y - ey[e]) - dy * (p1.x - ex[e])) * ref
				if s0 >= 0.0:
					cut.append(p0)
				if (s0 > 0.0 and s1 < 0.0) or (s0 < 0.0 and s1 > 0.0):
					var t := s0 / (s0 - s1)
					cut.append(Vector2(p0.x + (p1.x - p0.x) * t, p0.y + (p1.y - p0.y) * t))
			pieces[pi] = cut
	# attributes at the piece corners (perspective-correct barycentric extrapolation from the snapped triangle)
	var ia := 1.0 / wa
	var ib := 1.0 / wb
	var ic := 1.0 / wc
	var za := pa.z * ia
	var zb := pb.z * ib
	var zc := pc.z * ic
	var inv_area := 1.0 / area
	for pts: PackedVector2Array in pieces:
		var n := pts.size()
		if n < 3:
			continue
		var out_p := PackedVector4Array()
		var out_c := PackedColorArray()
		var out_u := PackedVector2Array()
		var out_v := PackedVector4Array()
		out_p.resize(n)
		out_c.resize(n)
		out_u.resize(n)
		out_v.resize(n)
		for k in n:
			var x := pts[k].x
			var y := pts[k].y
			var lb := ((x - ax) * (cy - ay) - (y - ay) * (cx - ax)) * inv_area
			var lc := ((bx - ax) * (y - ay) - (by - ay) * (x - ax)) * inv_area
			var la := 1.0 - lb - lc
			var qa := la * ia
			var qb := lb * ib
			var qc := lc * ic
			var qsum := qa + qb + qc
			if qsum <= 1e-12:   # (cannot happen for a half-pixel step unless w is extreme) nearest vertex
				qa = 1.0 if la >= lb and la >= lc else 0.0
				qb = 1.0 if qa == 0.0 and lb >= lc else 0.0
				qc = 1.0 - qa - qb
				qsum = qa * ia + qb * ib + qc * ic
				qa *= ia
				qb *= ib
				qc *= ic
			var w := 1.0 / qsum
			var col := (ca * qa + cb * qb + cc * qc) * w
			out_c[k] = Color(clampf(col.r, 0.0, 1.0), clampf(col.g, 0.0, 1.0), clampf(col.b, 0.0, 1.0), alpha)
			out_u[k] = (ua * qa + ub * qb + uc * qc) * w
			out_v[k] = _prev_of((la4 * qa + lb4 * qb + lc4 * qc) * w)
			var z := (la * za + lb * zb + lc * zc) * w
			out_p[k] = Vector4((x / 128.0 - 1.0) * w, (1.0 - y / 96.0) * w, z, w)
		for k in range(1, n - 1):
			for m in [0, k, k + 1]:
				acc_pos.append(out_p[m])
				acc_col.append(out_c[m])
				acc_uv.append(out_u[m])
				acc_prev.append(out_v[m])
				acc_attr.append(polyattr)
				acc_tex.append(teximage)
				acc_pal.append(pltt)
				acc_uvbox.append(box)


## bit per clip plane the point is outside of (same test as _dist < 0)
static func _outcode(p: Vector4) -> int:
	var w := p.w
	var c := 0
	if w + p.x < 0.0:
		c |= 1
	if w - p.x < 0.0:
		c |= 2
	if w + p.y < 0.0:
		c |= 4
	if w - p.y < 0.0:
		c |= 8
	if w + p.z < 0.0:
		c |= 16
	if w - p.z < 0.0:
		c |= 32
	return c


func _emit(p: Vector4, col: Color, uv: Vector2, alpha: float, box: Vector4, prev: Vector4) -> void:
	acc_pos.append(p)
	acc_prev.append(prev)
	acc_col.append(Color(col.r, col.g, col.b, alpha))
	acc_uv.append(uv)
	acc_attr.append(polyattr)
	acc_tex.append(teximage)
	acc_pal.append(pltt)
	acc_uvbox.append(box)


## signed distance to a clip plane: 0/1 = x >= -w / x <= w, 2/3 = y, 4/5 = z
static func _dist(p: Vector4, plane: int) -> float:
	var k := plane >> 1
	var v := p.x if k == 0 else (p.y if k == 1 else p.z)
	return p.w + v if (plane & 1) == 0 else p.w - v


static func _clip_plane(poly: Array, plane: int) -> Array:
	var inside := true
	for v in poly:
		if _dist(v[0], plane) < 0.0:
			inside = false
			break
	if inside:
		return poly
	var out: Array = []
	var n := poly.size()
	for i in n:
		var cur: Array = poly[i]
		var nxt: Array = poly[(i + 1) % n]
		var dc := _dist(cur[0], plane)
		var dn := _dist(nxt[0], plane)
		if dc >= 0.0:
			out.append(cur)
		if (dc >= 0.0) != (dn >= 0.0):
			var t := dc / (dc - dn)
			out.append([(cur[0] as Vector4).lerp(nxt[0], t), (cur[1] as Color).lerp(nxt[1], t), (cur[2] as Vector2).lerp(nxt[2], t),
				(cur[3] as Vector4).lerp(nxt[3], t)])
	return out


## clip position -> integer DS screen position in the viewport (posX = (x + w) * width / (2w) + x1,
## posY = (-y + w) * height / (2w) + (191 - y2), truncated) -> full-screen NDC at that pixel corner, same w
func _to_screen(cv: Vector4) -> Vector4:
	var w := cv.w
	if w <= 0.0:
		return cv
	var vw := viewport.z - viewport.x + 1
	var vh := viewport.w - viewport.y + 1
	var px := floorf((cv.x + w) * vw / (2.0 * w) + 1e-4) + viewport.x
	var py := floorf((-cv.y + w) * vh / (2.0 * w) + 1e-4) + (191 - viewport.w)
	return Vector4((px / 128.0 - 1.0) * w, (1.0 - py / 96.0) * w, cv.z, w)
