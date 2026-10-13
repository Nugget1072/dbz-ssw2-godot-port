class_name DSPresenter
extends Node2D
## Puts the DS picture (rendered at 256x384 in a SubViewport) on the window (part 15). Windowed: the largest whole
## multiple that fits (pixel-exact). Full screen: the largest size that fits with the DS aspect ("fit"), scaled
## "sharp bilinear": every DS pixel becomes an equal block and only the 1-px seams between blocks are blended, so no
## pixel column is wider than its neighbours (plain nearest scaling by e.g. 2.81 makes uneven columns and broken
## letters). Captures do not use this path (GameDS draws straight into the 256x384 root then).

const SHADER := """
shader_type canvas_item;
uniform vec2 src = vec2(256.0, 384.0);
uniform float scale = 1.0;
void fragment() {
	vec2 texel = UV * src;
	vec2 c = fract(texel) - 0.5;
	float r = max(0.5 - 0.5 / scale, 0.0);
	vec2 g = (c - clamp(c, -r, r)) * scale + 0.5;
	COLOR = texture(TEXTURE, (floor(texel) + g) / src);
}
"""

var vp: SubViewport
var rect := Rect2()
var scale_f := 1.0
var _mat: ShaderMaterial
var _pic := Node2D.new()   ## draws the picture (with the shader at fractional scales)
                           ## (part 16: the margins were drawn through the same shader, which sampled draw_rect's
                           ## white default texture, so full screen had white bars)


func _init(viewport: SubViewport) -> void:
	vp = viewport
	RenderingServer.set_default_clear_color(Color.BLACK)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_pic.material = _mat
	_pic.draw.connect(func(): _pic.draw_texture_rect(vp.get_texture(), rect, false))
	add_child(_pic)


## part 32: DisplayServer.window_get_mode() asks the window system (X11: a server round trip, ~1 ms per frame on the
## test VM); it is read again only when the window size changed and twice a second otherwise
var _fs := false
var _fs_win := Vector2(-1, -1)
var _fs_n := 0


## the window mode was just changed (F11, settings): read it again next frame
func recheck() -> void:
	_fs_n = 0


func _process(_d: float) -> void:
	var win := Vector2(get_viewport().get_visible_rect().size)
	var src := Vector2(vp.size)
	var s := minf(win.x / src.x, win.y / src.y)
	_fs_n -= 1
	if win != _fs_win or _fs_n <= 0:
		_fs_win = win
		_fs_n = 30
		var mode := DisplayServer.window_get_mode()
		_fs = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var fs := _fs
	if not fs and not Game.args.has("presentfit"):   # presentfit: debug, the full-screen scaling in a window
		s = maxf(1.0, floorf(s + 0.001))
	var size := (src * s).floor()
	var r := Rect2(((win - size) / 2.0).floor(), size)
	if r != rect:
		rect = r
		scale_f = s
		_mat.set_shader_parameter("src", src)
		_mat.set_shader_parameter("scale", s)
		_apply()
		if Game.args.has("presentfit"):
			print("PRESENT window %s rect %s scale %.3f" % [win, rect, s])


func _apply() -> void:
	if _crt != null:   # CRT TV (part 25): the CRT shader at every scale (sharp-bilinear sampling inside it)
		_crt.set_shader_parameter("src", Vector2(vp.size))
		_crt.set_shader_parameter("scale", scale_f)
		_pic.material = _crt
		_pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		# whole multiples (windows): sharp bilinear gives exactly nearest sampling there, so the picture is drawn
		# without the shader and with nearest filtering, a little less work per frame (part 20)
		var whole := absf(scale_f - roundf(scale_f)) < 0.0001
		_pic.material = null if whole else _mat
		_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if whole else CanvasItem.TEXTURE_FILTER_LINEAR
	_pic.queue_redraw()


## WEIRD STUFF 3 "CRT TV" (part 25, QoLCrt): the picture drawn through shaders/ds_fx_crt.gdshader at the window's
## resolution (scanlines one per DS row at any size); `mat` null = off (the plain path above, nothing extra)
var _crt: ShaderMaterial = null


func set_crt(mat: ShaderMaterial) -> void:
	if mat != _crt:
		_crt = mat
		if rect.size.x > 0.0:
			_apply()


## (part 20: the black margins come from the window's clear colour, black since part 16; the full-window black
## rect this node drew every frame is gone)


## window position -> DS pixel (256x384 space)
func to_ds(p: Vector2) -> Vector2:
	if rect.size.x <= 0.0:
		return Vector2(-1, -1)
	return (p - rect.position) / scale_f
