class_name Fighter
extends Node2D
## One fighter. Position/velocity use the DS units (24.8 fixed-point pixels, fighter+0x38/+0x3C).
##
## The animation side is the real behaviour bytecode run by CharVM. The *controller* that picks
## actions from input is a stand-in until the C state machine (state handlers at 0x020D785C, fighter+5)
## is ported: the action ids below were read from the emulator for gkn (fighter+6 after each input),
## movement constants from fighter RAM traces. Confidence M — see HANDOFF.md "Fighter controller".

const ACT_IDLE := 0
const ACT_MOVE := 3          # held direction (fighter+6 = 3 while flying)
const ACT_KI_BLAST := 36     # A
const ACT_MELEE := 24        # B
const ACT_Y := 28            # Y
const ACT_DASH := 17         # L
const MOVE_SPEED := 664      # fighter+0x22/+0x24 while holding a direction (1/256 px per frame)
const MOVE_DECEL := 21       # per-frame velocity decay after release (fighter+0x26/+0x30)

var data: CharData
var vm: CharVM
var player: int = 0
var x: int = 0               # 24.8
var y: int = 0
var vx: int = 0
var vy: int = 0
var facing: int = 0          # fighter+7: 0 = right, 128 = left
var action: int = -1
var busy: int = 0            # frames left in a non-interruptible action (stand-in)
var opponent: Fighter
var hp: int = 13000          # fighter+0x24A (13000 at start for gkn/vgn)
var ki_percent: int = 100    # HUD ki % (field not located yet)
var pal_row: int = 0

var _sprite: Sprite2D
var _mat: ShaderMaterial


func setup(code: String, p: int, start_x: int, start_y: int) -> void:
	data = CharData.load_code(code)
	vm = CharVM.new(data)
	player = p
	x = start_x << 8
	y = start_y << 8
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/palette_sprite.gdshader")
	_mat.set_shader_parameter("palette", data.palette)
	_mat.set_shader_parameter("pal_row", pal_row)
	_sprite = Sprite2D.new()
	_sprite.texture = data.atlas
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.material = _mat
	add_child(_sprite)
	set_action(ACT_IDLE)


func set_action(a: int) -> void:
	action = a
	vm.start_action(a)


## One game tick (60 Hz). `input` = Dictionary of DS buttons held / pressed this frame.
func step(input: Dictionary) -> void:
	if opponent:
		facing = 0 if opponent.x >= x else 128
	var dir := Vector2i.ZERO
	if input.get("right", false): dir.x += 1
	if input.get("left", false): dir.x -= 1
	if input.get("up", false): dir.y -= 1
	if input.get("down", false): dir.y += 1
	if busy > 0:
		busy -= 1
	if busy == 0 or vm.action_ended:
		if input.get("a_pressed", false):
			set_action(ACT_KI_BLAST); busy = 46
		elif input.get("b_pressed", false):
			set_action(ACT_MELEE); busy = 15
		elif input.get("y_pressed", false):
			set_action(ACT_Y); busy = 15
		elif input.get("l_pressed", false):
			set_action(ACT_DASH); busy = 21
		elif dir != Vector2i.ZERO:
			if action != ACT_MOVE:
				set_action(ACT_MOVE)
		elif action != ACT_IDLE:
			set_action(ACT_IDLE)
	if busy == 0 and dir != Vector2i.ZERO:
		var v := Vector2(dir).normalized() * MOVE_SPEED
		vx = int(v.x)
		vy = int(v.y)
	else:
		vx = _decay(vx)
		vy = _decay(vy)
	x += vx
	y += vy
	vm.tick(facing)


func _decay(v: int) -> int:
	if v > 0:
		return maxi(0, v - MOVE_DECEL)
	if v < 0:
		return mini(0, v + MOVE_DECEL)
	return 0


## Place the sprite for camera centre (cam_x, cam_y) in pixels; screen centre = (128, 96).
func update_sprite(cam_x: int, cam_y: int) -> void:
	if vm.frame_id < 0 or vm.frame_id >= data.frames.size():
		_sprite.visible = false
		return
	var fr: Dictionary = data.frames[vm.frame_id]
	var img: Dictionary = data.images[int(fr["image"])]
	var crop: Array = img["crop"]
	var at: Array = img["atlas"]
	_sprite.visible = int(at[2]) > 0
	_sprite.region_rect = Rect2(at[0], at[1], at[2], at[3])
	var ox: int = int(fr["origin"][0])
	var oy: int = int(fr["origin"][1])
	# screen position of the frame origin (fighter+0x140/+0x142 on the DS)
	var sx: int = (x >> 8) - cam_x + 128
	var sy: int = (y >> 8) - cam_y + 96
	position = Vector2(sx, sy)
	if vm.flip_h:
		scale = Vector2(-1, 1)
	else:
		scale = Vector2(1, 1)
	_sprite.position = Vector2(int(crop[0]) - ox, int(crop[1]) - oy)
