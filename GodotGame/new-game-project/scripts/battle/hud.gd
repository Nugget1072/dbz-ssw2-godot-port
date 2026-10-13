class_name BattleHUD
extends Node2D
## Top-screen battle HUD, rebuilt from the DS layers (DATA_NOTES "Battle HUD"):
##   - BG1 text layer (priority 0): frame, timer, ki % digits. Digits are copied inside the map from the
##     glyph library stored off-screen in map rows 24/25 (exactly what the game does).
##   - orthographic 3D quads: life bars (palette gauge), red damage bars, face icons.

const BAR_FIRST_INDEX := 16      ## bar texture row 2: colour index per column, 16..86 (71 columns)
const BAR_COLUMNS := 71
const COL_LIFE := 0x033F          ## BGR555 yellow (0x033E is the shaded row)
const COL_LOST := 0x3484          ## dark blue

var bg1: DSTextBG
var bars: Array[Sprite2D] = []
var bar_pal_img: Array[Image] = []
var bar_pal_tex: Array[ImageTexture] = []
var faces: Array[Sprite2D] = []
var shown_cols: PackedInt32Array = [BAR_COLUMNS, BAR_COLUMNS]


func setup(p1_char_id: int, p2_char_id: int) -> void:
	var dir := "ui/battle/"
	# life bars (3D quads at y 8..24; P1 0..128, P2 mirrored 127..255)
	for p in 2:
		var img := Assets.image(dir + "bar_life_pal.png").duplicate() as Image
		var tex := ImageTexture.create_from_image(img)
		bar_pal_img.append(img)
		bar_pal_tex.append(tex)
		var s := Sprite2D.new()
		s.texture = Assets.texture(dir + "bar_life_idx.png")
		s.centered = false
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/palette_sprite.gdshader")
		m.set_shader_parameter("palette", tex)
		s.material = m
		if p == 0:
			s.position = Vector2(0, 8)
		else:
			s.position = Vector2(255, 8)
			s.scale = Vector2(-1, 1)
		add_child(s)
		bars.append(s)
	# face icons (32x32 at 0,0 and 232,0 - the right one is cut by the screen edge)
	for p in 2:
		var f := Sprite2D.new()
		f.texture = Assets.texture(dir + "face_%02d.png" % (p1_char_id if p == 0 else p2_char_id))
		f.centered = false
		f.position = Vector2(0, 0) if p == 0 else Vector2(232, 0)
		add_child(f)
		faces.append(f)
	bg1 = DSTextBG.new()
	bg1.setup(dir + "bg1_tiles.png", dir + "bg1_pal.png", dir + "bg1_map.bin", 4)
	add_child(bg1)
	set_life(0, 13000, 13000)
	set_life(1, 13000, 13000)


## Timer: 4 digits at map (14..17, 0..1); glyph d = library column 21 + d, rows 24 (top) / 25 (bottom).
func set_timer(v: int) -> void:
	var s := "%04d" % clampi(v, 0, 9999)
	for i in 4:
		var d := s.unicode_at(i) - 48
		bg1.set_entry(14 + i, 0, bg1.get_entry(21 + d, 24))
		bg1.set_entry(14 + i, 1, bg1.get_entry(21 + d, 25))
	bg1.flush()


## Ki %: 3 digits at (1..3, 21..22) for P1 and (28..30, 21..22) for P2; glyph d = library column d, rows 24/25.
func set_ki(player: int, pct: int) -> void:
	var s := "%3d" % clampi(pct, 0, 999)
	var x0 := 1 if player == 0 else 28
	for i in 3:
		var c := s.unicode_at(i)
		if c == 32:
			bg1.set_entry(x0 + i, 21, 0xF000)
			bg1.set_entry(x0 + i, 22, 0xF000)
		else:
			bg1.set_entry(x0 + i, 21, bg1.get_entry(c - 48, 24))
			bg1.set_entry(x0 + i, 22, bg1.get_entry(c - 48, 25))
	bg1.flush()


## Life gauge. visible columns = floor(hp * 71 / 12480) fits 8 emulator samples exactly (confidence M);
## the shown value drains 1 column per ~3 frames toward the target like the original.
func set_life(player: int, hp: int, _max_hp: int) -> void:
	var target := clampi(int(floor(float(hp) * BAR_COLUMNS / 12480.0)), 0, BAR_COLUMNS)
	if target < shown_cols[player]:
		shown_cols[player] -= 1 if Engine.get_physics_frames() % 3 == 0 else 0
	else:
		shown_cols[player] = target
	var img := bar_pal_img[player]
	for c in BAR_COLUMNS:
		var idx := BAR_FIRST_INDEX + c
		var col := COL_LIFE if c < shown_cols[player] else COL_LOST
		img.set_pixel(idx & 15, idx >> 4, _bgr(col))
	bar_pal_tex[player].update(img)


static func _bgr(c: int) -> Color:
	return Color8((c & 31) * 255 / 31, ((c >> 5) & 31) * 255 / 31, ((c >> 10) & 31) * 255 / 31)
