class_name StageView
extends SubViewport
## The 3D stage panorama (engine A BG0 = 3D layer), rendered into its own 256x192 viewport.
##
## Camera model solved from melonDS clip-space vertices (DATA_NOTES "Stage camera", confidence H):
##   P = perspective fovy 60°, aspect 4:3, eye at origin looking down -Z
##   view = 128 * (model + (tx, ty, 0)) + (0, 0, -1)
##   tx = (9216 - camX) / 256, ty = (camY - 8216) / 1024
## Every object is wrapped independently with period 8 units: it is drawn once, at the copy whose
## centre is closest to the camera (fit to 40 camera positions, confidence M on the exact threshold).

var stage_id: int = 0
var _root: Node3D
var _objects: Array[Node3D] = []
var _centers: PackedFloat32Array = []   ## model-space x centre of each object
var _camera: Camera3D


func build(id: int) -> void:
	stage_id = id
	size = Vector2i(256, 192)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_DISABLED
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = 60.0
	_camera.near = 0.5
	_camera.far = 4096.0
	add_child(_camera)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_root = Node3D.new()
	add_child(_root)
	var dir := "stage/stage_%02d/" % id
	var mesh: Dictionary = Assets.json(dir + "mesh.json")
	var tex_sizes: Array = mesh["textures"]
	var materials: Array[StandardMaterial3D] = []
	for i in tex_sizes.size():
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = Assets.texture(dir + "tex_%d.png" % i)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.texture_repeat = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_BACK
		materials.append(m)
	for o in mesh["objects"]:
		var ti: int = int(o["texture"])
		var ts: Array = tex_sizes[ti]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for tri in o["tris"]:
			# DS triangles are counter-clockwise; Godot's front faces are clockwise -> emit reversed
			for k in [0, 2, 1]:
				var v: Array = tri[k]
				st.set_color(Color(float(v[5]) / 31.0, float(v[6]) / 31.0, float(v[7]) / 31.0))
				st.set_uv(Vector2(float(v[3]) / float(ts[0]), float(v[4]) / float(ts[1])))
				st.add_vertex(Vector3(v[0], v[1], v[2]))
		st.set_material(materials[ti])
		var am := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = am
		_root.add_child(mi)
		_objects.append(mi)
		var aabb := am.get_aabb()
		_centers.append(aabb.position.x + aabb.size.x * 0.5)


func update_camera(cam_x: int, cam_y: int) -> void:
	var tx: float = float(9216 - cam_x) / 256.0
	var ty: float = float(cam_y - 8216) / 1024.0
	_root.transform = Transform3D(Basis.from_scale(Vector3(128, 128, 128)), Vector3(0.0, 128.0 * ty, -1.0))
	for i in _objects.size():
		var c: float = _centers[i] + tx
		var k: float = -roundf(c / 8.0)
		_objects[i].position = Vector3(tx + 8.0 * k, 0, 0)
