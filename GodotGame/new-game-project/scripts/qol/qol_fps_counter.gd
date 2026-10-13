class_name QoLFpsCounter
extends Control
## Small frame-rate readout in the top-left corner (QoL setting "FPS COUNTER", F3 toggles it anywhere): pictures
## shown per second (Godot's display frame rate, averaged over the last second), in the game's font.

var font: QoLFont
var _shown := -1
var _t := 0.0


func _init() -> void:
	position = Vector2.ZERO
	size = Vector2(64, 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	var f := roundi(Engine.get_frames_per_second())
	if f != _shown:
		_shown = f
		queue_redraw()


func _draw() -> void:
	var n := str(maxi(_shown, 0))
	var w := font.width(n, QoLFont.BOLD) + font.width("FPS", QoLFont.BOLD) + 12
	draw_rect(Rect2(0, 0, w, 14), Color(0, 0, 0, 0.75))
	font.draw(self, Vector2(3, 2), n, Color.WHITE, QoLFont.BOLD)
	font.draw(self, Vector2(w - 3 - font.width("FPS", QoLFont.BOLD), 2), "FPS", Color8(255, 166, 0), QoLFont.BOLD)
