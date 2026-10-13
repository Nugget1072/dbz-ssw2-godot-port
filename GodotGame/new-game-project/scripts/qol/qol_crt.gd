class_name QoLCrt
extends Node
## WEIRD STUFF 3 "CRT TV" (part 25, picture only): shaders/ds_fx_crt.gdshader over the whole picture (both screens),
## after GAME BOY. With DSPresenter (normal play, windowed 1X-8X or full screen) the presenter draws the 256x384
## SubViewport through it at the window's resolution (DSPresenter.set_crt): scanlines exactly one per DS pixel row
## at every size. Without the presenter (frame-exact captures, `snap=`, `present=0`) a rect on CanvasLayer 65 (above
## GAME BOY's 64) runs the CRT_SCREEN variant on the 256x384 picture (one window pixel per DS pixel: glow, vignette
## and corners, no scanlines). The port's own settings menu stays sharp: while it is open the lower screen and the top
## screen's title / description box (QoLTopInfo, y 24..147) are left untouched (only the rounded corners). Off: one
## test per displayed frame, nothing else (no material, no layer).

const SHADER := "res://shaders/ds_fx_crt.gdshader"
const TOP_INFO := Vector4(0, 24, 256, 124)
const LOWER := Vector4(0, 192, 256, 192)

var qol                               ## QoLController
var _on := false
var _mat: ShaderMaterial = null       ## presenter variant
var _layer: CanvasLayer = null        ## no-presenter variant
var _lmat: ShaderMaterial = null


func _process(_d: float) -> void:
	var on: bool = qol.settings.crt_tv
	if not on and not _on:
		return
	if on != _on:
		_on = on
		_switch(on)
	if not on:
		return
	var s0 := LOWER if qol.menu.visible else Vector4.ZERO
	var s1 := TOP_INFO if qol.top.visible else Vector4.ZERO
	for m in [_mat, _lmat]:
		if m != null:
			m.set_shader_parameter("sharp0", s0)
			m.set_shader_parameter("sharp1", s1)


func _switch(on: bool) -> void:
	var presenter: DSPresenter = qol.game.presenter
	if not on:
		if presenter != null:
			presenter.set_crt(null)
		if _layer != null:
			_layer.queue_free()
		_layer = null
		_lmat = null
		_mat = null
		return
	var sh: Shader = load(SHADER)
	if presenter != null:
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		presenter.set_crt(_mat)
		return
	var v := Shader.new()   # the screen-texture variant (same code, CRT_SCREEN defined)
	v.code = sh.code.replace("shader_type canvas_item;\n", "shader_type canvas_item;\n#define CRT_SCREEN\n")
	_lmat = ShaderMaterial.new()
	_lmat.shader = v
	_lmat.set_shader_parameter("scale", 1.0)
	_layer = CanvasLayer.new()
	_layer.layer = 65
	var r := ColorRect.new()
	r.size = Vector2(256, 384)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = _lmat
	_layer.add_child(r)
	qol.game.screen_root.add_child(_layer)
