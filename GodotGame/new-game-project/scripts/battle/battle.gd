extends Node2D
## Battle scene: top screen = sky (BG3) + horizon (BG2) + 3D stage + fighters, bottom screen = sub-screen.
## Runs at the DS tick rate (60 Hz physics). Camera/scroll formulas: DATA_NOTES "Stages" / "Battle coordinates".

const P1_START := Vector2i(8127, 8128)   # Free Battle start positions (fighter+0x38/+0x3C >> 8)
const P2_START := Vector2i(8161, 8128)

var top: SubViewport
var bottom: SubViewport
var stage: StageView
var bg2: ColorRect
var bg3: ColorRect
var fighters_layer: Node2D
var p1: Fighter
var p2: Fighter
var cam_x: int = 8143
var cam_y: int = 8128
var tick: int = 0
var sky_y: int = 0
var stage_meta: Dictionary
var hud: BattleHUD
var timer_value: int = 1800      ## top-centre counter (RAM 0x02101B3C); decrements every ~6.7 frames (M)


func _ready() -> void:
	_build_screens()
	_build_top()
	_build_bottom()
	Sound.play_music(Sound.battle_music_for_stage(Game.stage_id))


func _build_screens() -> void:
	top = _screen(Vector2(0, 0))
	bottom = _screen(Vector2(0, 192))
	if Game.single_screen:
		bottom.get_parent().visible = false


func _screen(pos: Vector2) -> SubViewport:
	var c := SubViewportContainer.new()
	c.position = pos
	c.size = Vector2(256, 192)
	c.stretch = true
	var v := SubViewport.new()
	v.size = Vector2i(256, 192)
	v.disable_3d = true
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	c.add_child(v)
	add_child(c)
	return v


func _bg_layer(tex: Texture2D, ref: Vector2, abcd: Vector4) -> ColorRect:
	var r := ColorRect.new()
	r.size = Vector2(256, 192)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/ds_bg.gdshader")
	m.set_shader_parameter("layer", tex)
	m.set_shader_parameter("layer_size", Vector2(tex.get_width(), tex.get_height()))
	m.set_shader_parameter("ref", ref)
	m.set_shader_parameter("abcd", abcd)
	r.material = m
	return r


func _build_top() -> void:
	var sdir := "stage/stage_%02d/" % Game.stage_id
	stage_meta = Assets.json(sdir + "stage.json")
	# BG3 sky (priority 3). Ruins values read from the 2D engine during battle: pa=127, pd=255,
	# xref=16448, yref += 64/frame. TODO: per-stage table at 0x020CFAC8.
	bg3 = _bg_layer(Assets.texture(sdir + "bg3.png"), Vector2(16448, 0), Vector4(127, 0, 0, 255))
	top.add_child(bg3)
	# BG2 horizon (priority 2): hofs = camX >> 3, vofs = (camY * 3 >> 7) - 64  (fit to 60 samples, M)
	bg2 = _bg_layer(Assets.texture(sdir + "bg2.png"), Vector2.ZERO, Vector4(256, 0, 0, 256))
	top.add_child(bg2)
	# 3D stage (BG0)
	stage = StageView.new()
	stage.build(Game.stage_id)
	add_child(stage)
	var tr := TextureRect.new()
	tr.texture = stage.get_texture()
	tr.size = Vector2(256, 192)
	top.add_child(tr)
	fighters_layer = Node2D.new()
	top.add_child(fighters_layer)
	p1 = Fighter.new()
	p2 = Fighter.new()
	fighters_layer.add_child(p1)
	fighters_layer.add_child(p2)
	p1.setup(Game.p1_char, 0, P1_START.x, P1_START.y)
	p2.setup(Game.p2_char, 1, P2_START.x, P2_START.y)
	p1.opponent = p2
	p2.opponent = p1
	hud = BattleHUD.new()
	top.add_child(hud)
	hud.setup(_char_id(Game.p1_char), _char_id(Game.p2_char))
	_update_view()


func _char_id(code: String) -> int:
	for e in Assets.json("chara/table.json"):
		if String(e["code"]) == code:
			return int(e["id"])
	return 0


func _build_bottom() -> void:
	var sub := BattleSubScreen.new()
	bottom.add_child(sub)
	sub.setup(Game.p1_char)


func read_input() -> Dictionary:
	if Pilot.active:
		return Pilot.input_state()
	return {
		"left": Input.is_action_pressed("ds_left"), "right": Input.is_action_pressed("ds_right"),
		"up": Input.is_action_pressed("ds_up"), "down": Input.is_action_pressed("ds_down"),
		"a_pressed": Input.is_action_just_pressed("ds_a"), "b_pressed": Input.is_action_just_pressed("ds_b"),
		"x_pressed": Input.is_action_just_pressed("ds_x"), "y_pressed": Input.is_action_just_pressed("ds_y"),
		"l_pressed": Input.is_action_just_pressed("ds_l"), "r_pressed": Input.is_action_just_pressed("ds_r"),
	}


func _physics_process(_delta: float) -> void:
	tick += 1
	p1.step(read_input())
	p2.step({})   # CPU AI not ported yet: P2 idles
	_update_camera()
	_update_view()


func _update_camera() -> void:
	# Stand-in: centre between fighters (camera code not ported yet; on the DS it eases, see 0x021003D8)
	var tx: int = ((p1.x >> 8) + (p2.x >> 8)) >> 1
	var ty: int = ((p1.y >> 8) + (p2.y >> 8)) >> 1
	cam_x += signi(tx - cam_x) * mini(absi(tx - cam_x), 8)
	cam_y += signi(ty - cam_y) * mini(absi(ty - cam_y), 8)


func _update_view() -> void:
	stage.update_camera(cam_x, cam_y)
	sky_y += 64
	(bg3.material as ShaderMaterial).set_shader_parameter("ref", Vector2(16448, sky_y))
	(bg2.material as ShaderMaterial).set_shader_parameter("ref", Vector2(((cam_x >> 3) & 511) * 256, (((cam_y * 3) >> 7) - 64) * 256))
	p1.update_sprite(cam_x, cam_y)
	p2.update_sprite(cam_x, cam_y)
	if hud:
		if tick > 0 and tick % 20 in [0, 7, 13]:
			timer_value = maxi(0, timer_value - 1)
		hud.set_timer(timer_value)
		hud.set_life(0, p1.hp, 13000)
		hud.set_life(1, p2.hp, 13000)
		hud.set_ki(0, p1.ki_percent)
		hud.set_ki(1, p2.ki_percent)
