class_name DSRender3D
extends SubViewport
## Renders the DS 3D engine's output (DSGX polygons) into a 256x192 transparent texture that the 2D engine
## shader composites as BG0. Opaque polygons go first (depth write), translucent ones after in submission
## order (depth write only when POLYGON_ATTR bit 11 asks for it), like the DS.

var gx := DSGX.new()
var mesh_inst := MeshInstance3D.new()
var cam := Camera3D.new()
var mat_opaque := ShaderMaterial.new()
var mat_trans := ShaderMaterial.new()
var mat_trans_dw := ShaderMaterial.new()
var tex_vram: ImageTexture
var tex_pal: ImageTexture
var clear_quad := MeshInstance3D.new()
var clear_mat := ShaderMaterial.new()


func _init() -> void:
	size = Vector2i(256, 192)
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_DISABLED
	var code: String = (load("res://shaders/ds_poly.gdshader") as Shader).code
	var sh_o := Shader.new()
	sh_o.code = code
	var sh_t := Shader.new()
	sh_t.code = code.replace("depth_draw_opaque", "depth_draw_never").replace("//DEPTH_BIAS", DEPTH_BIAS).replace("//ALPHA_LINE", "ALPHA = opaque_rear ? (floor(c.a * 31.0 + 0.5) + 1.0) / 32.0 : c.a;   // over an opaque rear plane: DS blend weights (a+1)/32 : (31-a)/32")
	var sh_tw := Shader.new()
	sh_tw.code = code.replace("depth_draw_opaque", "depth_draw_always").replace("//DEPTH_BIAS", DEPTH_BIAS).replace("//ALPHA_LINE", "ALPHA = opaque_rear ? (floor(c.a * 31.0 + 0.5) + 1.0) / 32.0 : c.a;   // over an opaque rear plane: DS blend weights (a+1)/32 : (31-a)/32")
	_code = code
	_code_plain = code
	_variants[""] = [sh_o, sh_t, sh_tw, _trans_shaders, code]
	_enc = _enc6()
	for m in [mat_opaque, mat_trans, mat_trans_dw]:
		m.set_shader_parameter("enc6", _enc)
	mat_opaque.shader = sh_o
	mat_trans.shader = sh_t
	mat_trans_dw.shader = sh_tw
	add_child(cam)
	cam.current = true
	mesh_inst.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	mesh_inst.extra_cull_margin = 16384.0
	add_child(mesh_inst)
	var ws := World3D.new()
	world_3d = ws
	own_world_3d = true


## Compatibility renderer: the scene shader converts ALBEDO with Godot's approximations
## srgb_to_linear(c) = c*(c*(c*0.305306011+0.682171111)+0.012522878) and then
## linear_to_srgb(l) = max(1.055*l^0.416666667-0.055, 0). For each 6-bit DS level k find the ALBEDO whose round
## trip is k/63 (bisection), so the viewport holds exactly the DS colour.
static func _enc6() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in 64:
		var target := k / 63.0
		var lo := 0.0
		var hi := 1.0
		for i in 40:
			var mid := (lo + hi) * 0.5
			var l := mid * (mid * (mid * 0.305306011 + 0.682171111) + 0.012522878)
			var o := maxf(1.055 * pow(l, 0.416666667) - 0.055, 0.0)
			if o < target:
				lo = mid
			else:
				hi = mid
		out.append((lo + hi) * 0.5)
	return out


var _tex_sig := ""
var dbg_tex: Array = []   ## gxdbg: the last uploaded [texture view, palette view]


## (part 32) refresh read half: the texture / palette VRAM views when their signature changed since the last upload
func _upload_read(core) -> void:
	var hw: DSHardware = core.hw
	var sig := hw.slots_sig(hw.tex_slots) + "|" + hw.slots_sig(hw.texpal_slots)
	if sig == _tex_sig and tex_vram != null:
		_rd_tex = []
		return
	_rd_tex = [sig, hw.tex_view(), hw.texpal_view()]


var _rd_tex: Array = []                ## [signature, texture view, palette view] or [] (no change)


func _upload() -> void:
	if _rd_tex.is_empty():
		return
	_tex_sig = _rd_tex[0]
	var tv: PackedByteArray = _rd_tex[1]
	var tp: PackedByteArray = _rd_tex[2]
	_rd_tex = []
	if _dbg:
		dbg_tex = [tv, tp]
	var img_v := Image.create_from_data(1024, 512, false, Image.FORMAT_R8, tv)
	var img_p := Image.create_from_data(1024, 96, false, Image.FORMAT_R8, tp)
	if tex_vram == null:
		tex_vram = ImageTexture.create_from_image(img_v)
		tex_pal = ImageTexture.create_from_image(img_p)
	else:
		tex_vram.update(img_v)
		tex_pal.update(img_p)


## Interpret the frame's GX commands and rebuild the mesh. Call while the game thread is parked.
## The DS draws the geometry swapped in at the end of frame N while frame N+1 is displayed, so the commands
## are kept one frame (`_pending`) and drawn with the VRAM/registers of the following frame.
var _pending: Array = []
var _code: String
var _enc: PackedFloat32Array
var _trans_shaders: Dictionary = {}   ## (depth_write << 8 | polygon id) -> Shader


## Translucent polygons: the DS does not draw a translucent pixel over one already drawn by a translucent
## polygon with the same polygon ID (GBATEK "DS 3D Polygon Attributes"); stencil = ID + 1 does the same.
func _trans_material(dw: bool, pid: int, order: int) -> ShaderMaterial:
	var key := (int(dw) << 8) | pid
	if not _trans_shaders.has(key):
		var sh := Shader.new()
		sh.code = _code.replace("depth_draw_opaque", "depth_draw_always" if dw else "depth_draw_never") \
			.replace("//DEPTH_BIAS", DEPTH_BIAS).replace("//ALPHA_LINE", "ALPHA = opaque_rear ? (floor(c.a * 31.0 + 0.5) + 1.0) / 32.0 : c.a;   // over an opaque rear plane: DS blend weights (a+1)/32 : (31-a)/32") \
			.replace("\nvoid vertex()", "\nstencil_mode read, write, compare_not_equal, %d;\n\nvoid vertex()" % (pid + 1))
		_trans_shaders[key] = sh
	# part 32 (same picture, less work): the material of the n-th translucent run is kept from frame to frame (its
	# shader, priority and enc6 depend only on the key; _build sets the per-frame parameters on it as before)
	var ck := (order << 16) | key
	var m: ShaderMaterial = _tm_cache.get(ck)
	if m != null and m.shader == _trans_shaders[key]:
		return m
	m = ShaderMaterial.new()
	m.shader = _trans_shaders[key]
	m.render_priority = clampi(order - 128, -128, 127)   # keep submission order
	m.set_shader_parameter("enc6", _enc)
	_tm_cache[ck] = m
	return m
var _tm_cache: Dictionary = {}       ## (translucent run index << 16 | key) -> ShaderMaterial
var clear_alpha: int = 0
## Translucent polygons pass the DS depth test only when strictly nearer ("less"; attribute bit 14 = "equal"
## test excepted): a translucent polygon at the same depth as what is already drawn is not drawn (e.g. the
## shine overlay on the menu bars). Godot's test passes on equal depth, so these move 2^-20 farther.
const DEPTH_BIAS := "if ((int(CUSTOM0.w + 0.5) & 0x4000) == 0) POSITION.z -= w * (1.0 / 1048576.0);"
var t_gx: int = 0                     ## profiling (usec)
var t_up: int = 0   ## rear-plane alpha of the frame last rendered


## Draws the geometry of the previous frame's commands (the DS shows 3D one frame after it is submitted). The
## geometry engine (DSGX) works through this frame's commands on a worker thread while the game emulates the
## next frame; its result is collected here next time. `threaded = false` does the same work in line.
var threaded: bool = true
var _task: int = -1
var t_gx_work: int = 0                ## profiling (usec): geometry engine time (t_gx = time waited for it)


var _mats: Array = []                ## materials of the mesh on screen (QoL smooth motion: interp per display frame)
var _fresh: bool = false              ## the mesh on screen is a new polygon list (else in-between frames hold still)
var _built_swaps: int = -1
var _interp: float = 1.0


func set_interp(a: float) -> void:
	var v := a if _fresh else 1.0
	if v == _interp:
		return
	_interp = v
	RenderingServer.global_shader_parameter_set("ds_interp_3d", v)   # every polygon material at once (part 20)


func render(core) -> int:
	render_read(core)
	return render_apply()


## (part 32) what render() reads from the emulated machine: call while the game thread is parked
var _rd_core = null
var _rd_queue: Array = []
var _rd_regs: Array = []               ## [CLEAR_COLOR, DISP3DCNT, toon table, alpha test ref]


func render_read(core) -> void:
	_rd_core = core
	_rd_queue = _queue
	_queue = []
	var toon := PackedVector3Array()
	for i in 32:
		var c: int = core.IO.decode_u16(0x380 + i * 2)
		toon.append(Vector3((c & 31) / 31.0, ((c >> 5) & 31) / 31.0, ((c >> 10) & 31) / 31.0))
	var cc: int = core.IO.decode_u32(0x350)
	_rd_regs = [cc, core.IO.decode_u16(0x60), toon, core.IO.decode_u8(0x340) & 31]
	clear_alpha = (cc >> 16) & 31
	_upload_read(core)


## the Godot side of render(): geometry of the previous frame, mesh, textures (may overlap the next game frame)
func render_apply() -> int:
	var core = _rd_core
	var t0 := Time.get_ticks_usec()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	elif not threaded:
		_run_gx(_pending, core)
	_pending = _rd_queue
	_rd_queue = []
	t_gx += Time.get_ticks_usec() - t0
	var n3 := _build()
	if threaded:
		_task = WorkerThreadPool.add_task(_run_gx.bind(_pending, core), false, "DS geometry")
	return n3


## the geometry commands of one emulated frame (queued until the next render)
var _queue: Array = []


func submit(cmds: Array) -> void:
	_queue.append_array(cmds)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


var _surfaces: Array = []             ## mesh arrays of the polygon list last swapped in: [arrays, kind, dw, pid]
var _ntris: int = 0
var _seen_swaps: int = 0
var _dbg: bool = Game.args.has("gxdbg")


## The native geometry engine (native/, dsnative.gdextension: same results, ~40x faster) when its library is
## present; otherwise DSGX in GDScript. `gxnative=0` forces the GDScript one.
var native = ClassDB.instantiate("DSGXNative") if ClassDB.class_exists("DSGXNative") and Game.flag("gxnative", "1") != "0" else null


func _run_gx(cmds: Array, core) -> void:
	var t0 := Time.get_ticks_usec()
	if native != null:
		native.run(cmds)
		if native.get_swaps() != _seen_swaps:
			_seen_swaps = native.get_swaps()
			_surfaces = native.prepare()
			_ntris = native.get_tri_count()
		t_gx_work += Time.get_ticks_usec() - t0
		return
	gx.run(cmds, core)
	if _dbg:
		print("GXDBG cmds %d swaps %d committed verts %d acc %d" % [cmds.size(), gx.swaps, gx.out_pos.size(), gx.acc_pos.size()])
	if gx.swaps != _seen_swaps:
		_seen_swaps = gx.swaps
		_prepare()
	t_gx_work += Time.get_ticks_usec() - t0


## (worker thread) split the swapped-in polygon list into the opaque surface and the translucent runs (in
## submission order, one per depth-write flag / polygon ID) and build their vertex arrays
func _prepare() -> void:
	var n := gx.out_pos.size()
	var opaque := PackedInt32Array()
	var runs: Array = []   # [depth_write, indices, polygon id]
	for t in range(0, n, 3):
		var pa: int = gx.out_attr[t]
		var tp: int = gx.out_tex[t]
		var alpha := (pa >> 16) & 31
		var fmt := (tp >> 26) & 7
		var trans := (alpha > 0 and alpha < 31) or fmt == 1 or fmt == 6
		if not trans:
			opaque.append(t)
		else:
			var dw := (pa & 0x800) != 0
			var pid := (pa >> 24) & 63
			if runs.is_empty() or runs[-1][0] != dw or runs[-1][2] != pid:
				runs.append([dw, [], pid])   # plain Array: a PackedInt32Array inside an Array is copied on access
			(runs[-1][1] as Array).append(t)
	var surf: Array = []
	if not opaque.is_empty():
		surf.append([_arrays(opaque), 0, false, 0])
	for r in runs:
		surf.append([_arrays(PackedInt32Array(r[1])), 1, r[0], r[2]])
	_surfaces = surf
	_ntris = n / 3


## Every frame: the 3D engine renders the current polygon list with the current textures and registers.
func _build() -> int:
	# rear plane: CLEAR_COLOR (0x04000350) with a non-zero alpha is an opaque background the translucent
	# polygons blend with; drawn as a far quad. With alpha 0 the viewport stays transparent and the 2D
	# compositor un-premultiplies the polygon colours.
	var cc: int = _rd_regs[0]
	clear_alpha = (cc >> 16) & 31
	var disp3dcnt: int = _rd_regs[1]
	var am := ArrayMesh.new()
	_fresh = _seen_swaps != _built_swaps
	_built_swaps = _seen_swaps
	_mats = [mat_opaque]
	if not _surfaces.is_empty():
		var t1 := Time.get_ticks_usec()
		_upload()
		t_up += Time.get_ticks_usec() - t1
		var toon: PackedVector3Array = _rd_regs[2]
		_set_params(mat_opaque, disp3dcnt, toon)
		if clear_alpha > 0:
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _clear_arrays(cc), [], {}, _FMT)
			am.surface_set_material(am.get_surface_count() - 1, mat_opaque)
		var k := 0
		for sf in _surfaces:
			var m: ShaderMaterial = mat_opaque
			if sf[1] == 1:
				m = _trans_material(sf[2], sf[3], k)
				_set_params(m, disp3dcnt, toon)
				_mats.append(m)
				k += 1
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sf[0], [], {}, _FMT)
			am.surface_set_material(am.get_surface_count() - 1, m)
	mesh_inst.mesh = am
	if idvp != null:   # BEVEL EMBOSS: the same polygons into the object-id render
		id_inst.mesh = am
		if not _surfaces.is_empty():
			_set_params(id_mat, disp3dcnt, _toon0)
		if _dbg_fx and Engine.get_process_frames() % 60 == 0:
			_fx_debug()
	return _ntris


const _FMT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)


## the rear plane as an opaque far quad in the CLEAR_COLOR
func _clear_arrays(cc: int) -> Array:
	var col := Color((cc & 31) / 31.0, ((cc >> 5) & 31) / 31.0, ((cc >> 10) & 31) / 31.0, 1.0)
	var v := PackedVector3Array()
	var w := PackedVector2Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	for p in [Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
		v.append(Vector3(p.x, p.y, 1.0))
		w.append(Vector2(1.0, 1.0))   # UV2.y = 1: the rear plane (unused by the plain shader; FX_ID skips it)
		cols.append(col)
		uv.append(Vector2.ZERO)
		c0.append_array([0.0, 0.0, 0.0, 0x00C0])
		c1.append_array([0x1F, 0.0, 0.0, 0.0])
		c2.append_array([0.0, 0.0, 0.0, 0.0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV2] = w
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_CUSTOM2] = c2
	return arr


func _set_params(m: ShaderMaterial, disp3dcnt: int, toon: PackedVector3Array) -> void:
	m.set_shader_parameter("texvram", tex_vram)
	m.set_shader_parameter("palvram", tex_pal)
	m.set_shader_parameter("disp3dcnt", disp3dcnt)
	m.set_shader_parameter("alpha_ref", _rd_regs[3])
	m.set_shader_parameter("opaque_rear", clear_alpha > 0)
	m.set_shader_parameter("toon", toon)


func _arrays(tris: PackedInt32Array) -> Array:
	var nv := tris.size() * 3
	var v := PackedVector3Array()
	var w := PackedVector2Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	v.resize(nv)
	w.resize(nv)
	col.resize(nv)
	uv.resize(nv)
	c0.resize(nv * 4)
	c1.resize(nv * 4)
	c2.resize(nv * 4)
	var opos := gx.out_pos
	var ocol := gx.out_col
	var ouv := gx.out_uv
	var j := 0
	for t in tris:
		# texture / palette / polygon attributes and the texture coordinate range are per triangle
		var tp: int = gx.out_tex[t]
		var pa: int = gx.out_attr[t]
		var pl: int = gx.out_pal[t]
		var bx: Vector4 = gx.out_uvbox[t]
		for k in 3:
			var i := t + k
			var p: Vector4 = opos[i]
			v[j] = Vector3(p.x, p.y, p.z)
			w[j] = Vector2(p.w, 0.0)
			col[j] = ocol[i]
			uv[j] = ouv[i]
			var q := j * 4
			c0[q] = tp & 0xFFFF
			c0[q + 1] = (tp >> 16) & 0xFFFF
			c0[q + 2] = pl
			c0[q + 3] = pa & 0xFFFF
			c1[q] = (pa >> 16) & 0xFFFF
			if i < gx.out_prev.size():   # previous screen position + valid flag (QoL smooth motion)
				var pr: Vector4 = gx.out_prev[i]
				c1[q + 1] = pr.x
				c1[q + 2] = pr.y
				c1[q + 3] = pr.z
			c2[q] = bx.x
			c2[q + 1] = bx.y
			c2[q + 2] = bx.z
			c2[q + 3] = bx.w
			j += 1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV2] = w
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_CUSTOM2] = c2
	return arr

# ---- WEIRD SETTINGS (part 21): shader variants for TOUCH FUZZY / BEVEL EMBOSS (picture effects only) ----------------
# Both off (the default): the plain shaders above, no extra viewport, nothing else changes.
var _code_plain: String
var _variants: Dictionary = {}       ## defines -> [opaque, trans, trans_dw shaders, translucent shader cache, code]
var _fx_key: String = ""             ## defines of the variant in use ("" = plain)
var idvp: SubViewport = null         ## BEVEL EMBOSS: object-id render of the same polygons (FX_ID), 256x192
var id_inst: MeshInstance3D
var id_mat: ShaderMaterial
var _id_key: String = ""
var _toon0 := PackedVector3Array()
var _dbg_fx: bool = Game.args.has("fxdbg")


func _defined(defs: String) -> String:
	return _code_plain.replace("shader_type spatial;\n", "shader_type spatial;\n" + defs)


## fuzzy: stage geometry waves (FX_FUZZY variant of every polygon material); ids: keep the object-id render
func set_fx(fuzzy: bool, ids: bool) -> void:
	var defs := "#define FX_ANY\n#define FX_FUZZY\n" if fuzzy else ""
	if defs != _fx_key:
		_fx_key = defs
		if not _variants.has(defs):
			var code := _defined(defs)
			var sh := []
			for kind in 3:
				var c := code
				if kind > 0:
					c = c.replace("depth_draw_opaque", "depth_draw_never" if kind == 1 else "depth_draw_always") \
						.replace("//DEPTH_BIAS", DEPTH_BIAS).replace("//ALPHA_LINE", "ALPHA = opaque_rear ? (floor(c.a * 31.0 + 0.5) + 1.0) / 32.0 : c.a;   // over an opaque rear plane: DS blend weights (a+1)/32 : (31-a)/32")
				var s := Shader.new()
				s.code = c
				sh.append(s)
			_variants[defs] = [sh[0], sh[1], sh[2], {}, code]
		var v: Array = _variants[defs]
		mat_opaque.shader = v[0]
		mat_trans.shader = v[1]
		mat_trans_dw.shader = v[2]
		_trans_shaders = v[3]
		_code = v[4]
		for m in [mat_opaque, mat_trans, mat_trans_dw]:
			m.set_shader_parameter("enc6", _enc)
	if ids and idvp == null:
		idvp = SubViewport.new()
		idvp.size = Vector2i(256, 192)
		idvp.transparent_bg = true
		idvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		idvp.msaa_3d = Viewport.MSAA_DISABLED
		idvp.own_world_3d = true
		var c := Camera3D.new()
		idvp.add_child(c)
		c.current = true
		id_inst = MeshInstance3D.new()
		id_inst.custom_aabb = mesh_inst.custom_aabb
		id_inst.extra_cull_margin = 16384.0
		id_inst.mesh = mesh_inst.mesh
		idvp.add_child(id_inst)
		id_mat = ShaderMaterial.new()
		id_inst.material_override = id_mat
		add_child(idvp)
		_id_key = "?"
		_toon0.resize(32)
	elif not ids and idvp != null:
		idvp.queue_free()
		idvp = null
	if idvp != null:
		var idefs := "#define FX_ID\n" + (defs if defs != "" else "#define FX_ANY\n")
		if idefs != _id_key:
			_id_key = idefs
			var s := Shader.new()
			s.code = _defined(idefs)
			id_mat.shader = s
			id_mat.set_shader_parameter("enc6", _enc)


## fxdbg: depth values of the orthographic (sprite) vertices on screen, to check FX_ID's rank mapping
func _fx_debug() -> void:
	var zs := {}
	var ws := {}
	for sf in _surfaces:
		var vv: PackedVector3Array = sf[0][Mesh.ARRAY_VERTEX]
		var w2: PackedVector2Array = sf[0][Mesh.ARRAY_TEX_UV2]
		for i in vv.size():
			if absf(w2[i].x - 1.0) < 0.0001 and absf(vv[i].z) < 0.5:
				zs[int(roundf(vv[i].z * 1024.0))] = true
			else:
				ws[int(log(maxf(w2[i].x, 1.0)) / log(2.0) * 3.0)] = true
	print("FXDBG ortho z*1024 %s  persp log2(w)*3 %s" % [str(zs.keys()), str(ws.keys())])
