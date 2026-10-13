class_name DSDisplay
extends Control
## Draws the two DS screens from the emulated hardware (DSMachine): each 2D engine is one quad with
## shaders/ds_engine2d.gdshader reading VRAM, palettes, OAM and the per-line registers.
## Engine A is on the top screen when POWCNT1 (0x04000304) bit 15 is set, else on the bottom one.

const W := 256
const H := 192

var machine: DSMachine
var screens: Array[ColorRect] = []
var mats: Array[ShaderMaterial] = []
var texs: Array = [{}, {}]          ## per engine: name -> ImageTexture
var layer3d: Texture2D = null       ## engine A BG0 3D layer (set by the 3D renderer)
var r3d: DSRender3D
var single_screen: bool = false
var t_3d: int = 0                     ## profiling (usec): 3D command interpretation + mesh + texture upload
## QoL smooth motion: keep the previous frame's OAM and per-line registers for in-between frames (set_interp)
var smooth: bool = false
var _last_oam: Array = [null, null]
var _last_regs: Array = [null, null]


func _init() -> void:
	r3d = DSRender3D.new()
	add_child(r3d)
	layer3d = r3d.get_texture()
	var shader: Shader = load("res://shaders/ds_engine2d.gdshader")
	for i in 2:
		var r := ColorRect.new()
		r.size = Vector2(W, H)
		r.position = Vector2(0, H * i)
		var m := ShaderMaterial.new()
		m.shader = shader
		r.material = m
		add_child(r)
		screens.append(r)
		mats.append(m)


var _sigs: Array = [{}, {}]
var _nocache: bool = Game.args.has("nocache")   ## debug: rebuild every VRAM texture every frame


## texture from a lazily built byte view: rebuilt and uploaded only when `sig` (bank write counters +
## mapping generation) changed since the last frame
func _tex_cached(engine: int, name: String, w: int, h: int, sig: String, build: Callable) -> ImageTexture:
	var t: ImageTexture = texs[engine].get(name)
	if t != null and _sigs[engine].get(name, "") == sig and not _nocache:
		return t
	_sigs[engine][name] = sig
	return _tex(engine, name, w, h, build.call())


func _tex(engine: int, name: String, w: int, h: int, data: PackedByteArray) -> ImageTexture:
	if data.size() < w * h:
		data.resize(w * h)
	elif data.size() > w * h:
		data = data.slice(0, w * h)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_R8, data)
	var t: ImageTexture = texs[engine].get(name)
	if t == null or t.get_width() != w or t.get_height() != h:
		t = ImageTexture.create_from_image(img)
		texs[engine][name] = t
	else:
		t.update(img)
	return t


## Upload the current frame's state (call while the game thread is parked).
## Part 32: in two halves. refresh_read() reads everything the picture needs from the emulated machine (VRAM views
## when they changed, palettes, OAM, per-line registers, 3D registers / textures / command queue; must run while the
## game thread is parked); refresh_apply() does the Godot side (texture uploads, 3D mesh, shader parameters) and may
## run while the game thread already runs the next frame (GameDS PERFORMANCE MODE starts it in between).
func refresh() -> void:
	refresh_read()
	refresh_apply()


var _rd: Array = []                   ## refresh_read() -> refresh_apply(): per engine [name, w, h, sig or null, bytes or null]...
var _rd_swap := false
var _rd_oam: Array = [null, null]
var _rd_regs: Array = [null, null]
var read_pending := false             ## refresh_read() ran, refresh_apply() not yet


## the texture `name` needs new bytes unless its signature is unchanged (then null)
func _need(e: int, name: String, sig: String) -> bool:
	return texs[e].get(name) == null or _sigs[e].get(name, "") != sig or _nocache


func refresh_read() -> void:
	var core = machine.core
	var hw: DSHardware = core.hw
	if _fx_any or core.get("cheats") != null:   # QoLGame: WEIRD SETTINGS (picture effects, part 21)
		_fx_update(core)
	var t0 := Time.get_ticks_usec()
	r3d.render_read(core)
	t_3d += Time.get_ticks_usec() - t0
	_rd_swap = (core.IO.decode_u16(0x304) & 0x8000) != 0
	_rd = [[], []]
	for e in 2:
		var a := e == 0
		var bgb := 0x6000000 if a else 0x6200000
		var bgn := 0x80000 if a else 0x20000
		var obb := 0x6400000 if a else 0x6600000
		var obn := 0x40000 if a else 0x20000
		var bx: Array = hw.bgext_a if a else hw.bgext_b
		var ox: Array = [hw.objext_a if a else hw.objext_b]
		var sig := hw.region_sig(bgb, bgn)
		_rd[e].append(["bgvram", "bg", 1024, 512 if a else 128, sig, hw.region_view(bgb, bgn) if _need(e, "bg", sig) else null])
		sig = hw.region_sig(obb, obn)
		_rd[e].append(["objvram", "obj", 1024, 256 if a else 128, sig, hw.region_view(obb, obn) if _need(e, "obj", sig) else null])
		_rd[e].append(["pal", "pal", 1024, 1, null, hw.pal.slice(0 if a else 0x400, 0x400 if a else 0x800)])
		_rd_oam[e] = hw.oam.slice(0 if a else 0x400, 0x400 if a else 0x800)
		_rd[e].append(["oam", "oam", 1024, 1, null, _rd_oam[e]])
		sig = hw.slots_sig(bx)
		_rd[e].append(["bgext", "bgext", 1024, 32, sig, hw.slots_view(bx, 0x2000) if _need(e, "bgext", sig) else null])
		sig = hw.slots_sig(ox)
		_rd[e].append(["objext", "objext", 1024, 8, sig, hw.slots_view(ox, 0x2000) if _need(e, "objext", sig) else null])
		_rd_regs[e] = machine.line_regs(e)
		_rd[e].append(["regs", "regs", 128, 192, null, _rd_regs[e]])
	read_pending = true


func refresh_apply() -> void:
	if not read_pending:
		return
	read_pending = false
	var t0 := Time.get_ticks_usec()
	r3d.render_apply()
	t_3d += Time.get_ticks_usec() - t0
	var swap := _rd_swap
	for e in 2:
		var m := mats[e]
		var a := e == 0
		m.set_shader_parameter("engine_a", a)
		for t: Array in _rd[e]:
			var name: String = t[1]
			if t[4] != null:   # a cached VRAM view: rebuilt only when its signature changed
				if t[5] == null:
					m.set_shader_parameter(t[0], texs[e][name])
					continue
				_sigs[e][name] = t[4]
			m.set_shader_parameter(t[0], _tex(e, name, t[2], t[3], t[5]))
		var oam: PackedByteArray = _rd_oam[e]
		var regs: PackedByteArray = _rd_regs[e]
		if smooth:
			if _last_oam[e] != null:
				m.set_shader_parameter("oam_prev", _tex(e, "oam_prev", 1024, 1, _last_oam[e]))
				m.set_shader_parameter("regs_prev", _tex(e, "regs_prev", 128, 192, _last_regs[e]))
			_last_oam[e] = oam
			_last_regs[e] = regs.duplicate()
		else:
			_last_oam[e] = null
		m.set_shader_parameter("has3d", a and layer3d != null)
		if a and layer3d != null:
			m.set_shader_parameter("layer3d", layer3d)
			m.set_shader_parameter("premul3d", r3d.clear_alpha == 0)
		# screen placement: engine A top when POWCNT1 bit 15
		var on_top := a == swap
		screens[e].position = Vector2(0, 0 if on_top else H)
		screens[e].visible = not single_screen or on_top
	_rd = []
	if _fx_rect != null:
		_fx_rect.material.set_shader_parameter("a_y0", int(screens[0].position.y))
		for e in 2:   # the per-line registers of each screen's engine: the bevel pass applies the fades (part 22)
			_fx_rect.material.set_shader_parameter("regs_top" if screens[e].position.y == 0 else "regs_bot", texs[e]["regs"])
		_fx_rect.material.set_shader_parameter("has_ids", r3d.idvp != null)
		if r3d.idvp != null:
			_fx_rect.material.set_shader_parameter("ids", r3d.idvp.get_texture())
		if Game.args.has("fxdump") and machine.syncs % int(Game.flag("cap_every", "1")) == 0 and machine.syncs >= int(Game.flag("cap_from", "0")):
			_fx_dump(machine.syncs)   # debug: the bevel inputs (picture + layer codes, 3D ids) next to the captures
	if _mirror or _mirrored:   # MIRROR MODE (part 22): the top (battle) screen drawn flipped left-right
		_mirrored = _mirror
		for e in 2:
			var flip := _mirror and screens[e].position.y == 0
			screens[e].scale = Vector2(-1.0 if flip else 1.0, 1.0)
			screens[e].position.x = W if flip else 0
	if _fx_rect != null:
		_fx_rect.material.set_shader_parameter("a_flip", screens[0].scale.x < 0.0)


## QoL: only these layers of the screen's engine are drawn (DISPCNT bits 8-12: BG0-3, OBJ; 0x1F00 = all), e.g. the
## Mode Select background behind the settings menu. `bottom`: the engine shown on the lower screen.
func set_layer_keep(bottom: bool, mask: int) -> void:
	var swap: bool = (machine.core.IO.decode_u16(0x304) & 0x8000) != 0
	for e in 2:
		var on_top := (e == 0) == swap
		mats[e].set_shader_parameter("layer_keep", mask if on_top != bottom else 0x1F00)
		_layer_keep[e] = mask if on_top != bottom else 0x1F00


## QoL smooth motion: show the current frame moved back toward the previous one by (1 - a) (a = 1: the frame
## itself). The 3D layer only moves when its polygon list is new this frame (no SWAP_BUFFERS = same picture).
func set_interp(a: float) -> void:
	var a2 := a if smooth and _last_oam[0] != null else 1.0
	if a2 != _interp2d:   # global shader uniform (both screens' materials), only when it changes (part 20)
		_interp2d = a2
		RenderingServer.global_shader_parameter_set("ds_interp_2d", a2)
	r3d.set_interp(a if smooth else 1.0)
	if _fx_any:
		_fx_push(a if smooth else 1.0)


var _interp2d := 1.0


# ---- WEIRD SETTINGS (part 21): BEVEL EMBOSS / TOUCH FUZZY, picture effects only -----------------------------------
# Read from QoLSettings (QoLGame.cheats) every refresh; with both off nothing here runs (the plain shaders, no extra
# viewport: output byte-identical). BEVEL EMBOSS: the two engine quads (+ the 3D renderer, so it is drawn first) move
# into a 256x384 RGBA SubViewport (`_fx_vp`), drawn with the FX_BEVEL engine shader (alpha = top layer code), and a
# rect with shaders/ds_fx_bevel.gdshader puts the bevelled picture where the screens were; the 3D layer adds an
# object-id render (DSRender3D.idvp). The QoL menu / top info / FPS counter are siblings drawn after DSDisplay, so the
# port's own settings menu stays flat (readable; the game's menus and their backgrounds are bevelled).
# TOUCH FUZZY: only in battles (battle_on_screen(): every mode, part 22), faded in / out over 45 frames: engine A (the battle screen) uses the FX_FUZZY engine shader (BG2 / BG3 warp,
# rainbow tint) and the 3D renderer the FX_FUZZY polygon shaders (stage zoom pulse + texture wave; sprites untouched).
# Time = game frames (+ the smooth-motion fraction) / 59.83, global shader uniform ds_fx (x time, y strength).
const FX_HZ := 59.8261
var _fx_any := false                  ## some effect in use (else the plain path, no work)
var _fx_bevel := false
var _fz := 0.0                        ## TOUCH FUZZY strength 0..1 (fades)
var _fz_sync := -1
var _fx_vp: SubViewport = null
var _fx_rect: ColorRect = null
var _sh_plain: Shader = null
var _sh_var: Dictionary = {}          ## flags (1 bevel, 2 fuzzy) -> engine shader variant
var _mat_flags: Array = [0, 0]
var _layer_keep: Array = [0x1F00, 0x1F00]
static var _fx_global := false


func _engine_shader(flags: int) -> Shader:
	if _sh_plain == null:
		_sh_plain = mats[0].shader
	if flags == 0:
		return _sh_plain
	if not _sh_var.has(flags):
		var defs := ("#define FX_BEVEL\n" if flags & 1 else "") + ("#define FX_FUZZY\n" if flags & 2 else "") \
			+ ("#define FX_SHAKE\n" if flags & 4 else "")
		var sh := Shader.new()
		sh.code = _sh_plain.code.replace("shader_type canvas_item;\n", "shader_type canvas_item;\n" + defs)
		_sh_var[flags] = sh
	return _sh_var[flags]


func _fx_update(core) -> void:
	var st = core.get("cheats")
	var bevel: bool = st != null and st.bevel_emboss
	var fuzzy: bool = st != null and st.touch_fuzzy
	var syncs: int = machine.syncs
	var gb: bool = st != null and st.get("game_boy") == true
	var battle := battle_on_screen()
	var target := 1.0 if fuzzy and battle else 0.0
	_mirror = mirror_active()
	_set_gameboy(gb)
	var steps := clampi(syncs - _fz_sync, 0, 60) if _fz_sync >= 0 else 60
	_fz_sync = syncs
	_fz = move_toward(_fz, target, steps / 45.0)
	# SCREEN SHAKE (part 23): QoLGame.shake_dmg = the biggest hit since the last look (FUN_020293A4 hook)
	_shake = st != null and st.get("screen_shake") == true and battle and (core.IO.decode_u16(0x304) & 0x8000) != 0
	var dmg = core.get("shake_dmg")
	if dmg != null and dmg > 0:
		core.set("shake_dmg", 0)
		if _shake:
			_shake_hit(dmg)
	_fx_any = bevel or _fz > 0.0 or _shake
	if _fx_any and not _fx_global:
		_fx_global = true
		RenderingServer.global_shader_parameter_add(&"ds_fx", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_set_bevel(bevel)
	for e in 2:
		var f := (1 if bevel else 0) | (2 if e == 0 and _fz > 0.0 else 0) | (4 if e == 0 and _shake else 0)
		if f != _mat_flags[e]:
			_mat_flags[e] = f
			mats[e].shader = _engine_shader(f)
			mats[e].set_shader_parameter("layer_keep", _layer_keep[e])
	r3d.set_fx(_fz > 0.0, bevel)
	if _fx_any:
		_fx_push(1.0)


func _fx_push(a: float) -> void:
	RenderingServer.global_shader_parameter_set(&"ds_fx", Vector4((machine.syncs - 1 + a) / FX_HZ, _fz, 0.0, 0.0))
	if _shake:
		var off := _shake_offset(a)
		mats[0].set_shader_parameter("fx_shake", off)
		if _fx_rect != null:
			_fx_rect.material.set_shader_parameter("a_shift", off)
	elif _fx_rect != null:
		_fx_rect.material.set_shader_parameter("a_shift", Vector2i.ZERO)


func _set_bevel(on: bool) -> void:
	if on == _fx_bevel:
		return
	_fx_bevel = on
	if on:
		_fx_vp = SubViewport.new()
		_fx_vp.size = Vector2i(W, H * 2)
		_fx_vp.transparent_bg = true
		_fx_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_fx_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		add_child(_fx_vp)
		r3d.reparent(_fx_vp, false)   # a SubViewport inside renders first: the 3D layer is ready for the engines
		for r in screens:
			r.reparent(_fx_vp, false)
		_fx_rect = ColorRect.new()
		_fx_rect.size = Vector2(W, H * 2)
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/ds_fx_bevel.gdshader")
		m.set_shader_parameter("src", _fx_vp.get_texture())
		_fx_rect.material = m
		add_child(_fx_rect)
	else:
		r3d.reparent(self, false)
		for r in screens:
			r.reparent(self, false)
		_fx_rect.queue_free()
		_fx_rect = null
		_fx_vp.queue_free()
		_fx_vp = null


func _fx_dump(f: int) -> void:
	await RenderingServer.frame_post_draw
	var dir := Game.flag("capture", "/tmp")
	if _fx_vp != null:
		_fx_vp.get_texture().get_image().save_png(dir.path_join("fxa%d.png" % f))
	if r3d.idvp != null:
		r3d.idvp.get_texture().get_image().save_png(dir.path_join("fxi%d.png" % f))



# ---- WEIRD SETTINGS (part 22): battle signal, GAME BOY, MIRROR MODE ------------------------------------------------
# A battle is on screen in every mode (Free / VS battle, Z-Battle, Story, Maximum, Practice) when the VBlank IRQ
# handler (OS IRQ table, DTCM 0x027E0004) is the battle's FUN_02013030 (installed by the battle scene FUN_02013064,
# which every mode runs: as scene 0, or wrapped by Practice's scene 0x13 FUN_0202FDB8; every scene change
# FUN_02001014 puts back the default 0x02000FD0) and the battle state u8 0x020DD4C5 is >= 4 (4-6 fighters enter /
# READY, 7 fight, 8 / 0xA-0xE events inside the fight, 9 pause, 0xF-0x11 time-up / KO / win sequences, 0x12-0x14 the
# fade out; 1-2 = VS screen and 3 = loading are excluded). The scene byte 0x020DD4C4 alone (part 21) missed Practice.
# GAME BOY: a CanvasLayer (layer 64, above the QoL menu, FPS counter and markers) with a rect that re-colours the
# whole 256x384 picture (screen texture) into the 4 DMG greens by luminance with a light 4x4 ordered dither.
# MIRROR MODE: the top screen's engine quad drawn with scale x = -1 while a battle is on screen (picture only; the
# main agent swaps Left / Right input while mirror_active() is true). The bottom (touch) screen is never flipped.
const BATTLE_VBLANK := 0x02013030
var _mirror := false                  ## flip the top screen this frame
var _mirrored := false                ## a flip was applied (undo it when _mirror goes off)
var _gb_layer: CanvasLayer = null


## true while a battle is on screen (any mode); reads RAM, so it can be asked at any time
func battle_on_screen() -> bool:
	if machine == null or machine.core == null:
		return false
	var mem: PackedByteArray = machine.core.M
	if mem.size() < 0x7E0008 or mem.decode_u32(0x7E0004) != BATTLE_VBLANK:
		return false
	return mem.decode_u8(0xDD4C5) >= 4


## MIRROR MODE in effect: the setting is on and a battle is on screen (the top screen is drawn flipped)
func mirror_active() -> bool:
	var st = machine.core.get("cheats") if machine != null and machine.core != null else null
	# not while the battle is paused (state 9): the pause menu's text must stay readable (part 24 QA)
	return st != null and st.get("mirror_mode") == true and battle_on_screen() and machine.core.M.decode_u8(0xDD4C5) != 9


func _set_gameboy(on: bool) -> void:
	if on == (_gb_layer != null):
		return
	if on:
		_gb_layer = CanvasLayer.new()
		_gb_layer.layer = 64
		var r := ColorRect.new()
		r.size = Vector2(W, H * 2)
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/ds_fx_gameboy.gdshader")
		r.material = m
		_gb_layer.add_child(r)
		add_child(_gb_layer)
	else:
		_gb_layer.queue_free()
		_gb_layer = null



# ---- SCREEN SHAKE (part 23): the battle screen shakes when a fighter is hit (picture only) -------------------------
# While the setting is on and a battle is on screen (engine A on top), engine A uses the FX_SHAKE shader variant: the
# whole top picture (stage, fighters, HUD) is sampled moved by `fx_shake` whole DS px, the edge rows / columns repeated
# (no black gap, nothing spills onto the bottom screen). A hit (QoLGame.shake_dmg) starts a shake of amplitude
# 6 * (damage / 2000)^0.75 px (1..6) lasting 8 + amplitude game frames, decaying quadratically; a hit
# only replaces a running shake when it is at least as strong as what is left of it. Time = game frames + the
# smooth-motion fraction, so in-between frames move smoothly.
var _shake := false
var _sk_amp := 0.0
var _sk_start := -1000
var _sk_len := 1.0


func _shake_env(t: float) -> float:
	if t < 0.0 or t >= _sk_len:
		return 0.0
	var e := 1.0 - t / _sk_len
	return e * e


func _shake_hit(dmg: int) -> void:
	var amp := clampf(6.0 * pow(dmg / 2000.0, 0.75), 1.0, 6.0)   # 200 damage (a ki blast / punch) ~1 px, 2000 = 6 px
	var left := _sk_amp * _shake_env(float(machine.syncs - _sk_start))
	if amp >= left:
		_sk_amp = amp
		_sk_start = machine.syncs
		_sk_len = 8.0 + amp
	if _dbg_fx:
		print("SHAKE f%d damage %d amplitude %.1f (left %.1f)" % [machine.syncs, dmg, amp, left])


## the picture offset (DS px) at the in-between fraction a of the current game frame
func _shake_offset(a: float) -> Vector2i:
	var t := float(machine.syncs - _sk_start) - 1.0 + a   # 0 = the frame the hit landed
	var e := _sk_amp * _shake_env(t)
	if e <= 0.0:
		return Vector2i.ZERO
	return Vector2i(roundi(e * cos(t * 2.83)), roundi(e * 0.6 * sin(t * 2.2 + 1.0)))   # x flips side almost every frame


var _dbg_fx: bool = Game.args.has("fxdbg")
