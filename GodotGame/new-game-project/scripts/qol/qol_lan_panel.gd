class_name QoLLanPanel
extends Node2D
# ---- LAN PANEL (part 30, phase 3)
## LAN MULTIPLAYER battle screens (docs/LAN_DESIGN.md 3; DATA_NOTES "Session 1 part 30 findings (LAN select / stage /
## battle)"). Drawn by the port over the game's picture; with no LAN session nothing is drawn (frame(): one test).
## - The GUEST's lower screen in a LAN battle = its own team (side 1) in the game's single-player panel layout. The game
##   draws the lower-screen panel for side 0 only (G+0x1BCA9 = 0 on both machines), so the port covers the game's three
##   portrait slots (80 x 128 at x 8 + 80·k, y 8) and the Team Arts / Touch! strip (y 136..191) with side 1's: portraits =
##   SubScrNBFC/NBFS member = character id (QoLMpPanel's ROM decoding) through the game's own lower-screen BG palette as it
##   is in palette RAM this frame (engine B BG rows: 0 normal, k + 1 the active slot k -- the white frame --, 4 KO'd /
##   support without assists, 7 bench below 20 % ki (no tag), 5 / 6 Team Arts lit / dim), empty slots the `nul1` frame (37),
##   the strip = game_subbg.bin `e_pairatk` (the game's Team Arts bar map) with row 5 (side 1 ki >= 200 % and its active
##   fighter has a Team Arts partner, rec +0x274 & 0x100) or 6, its red diamond (index 11) in P2 blue. The slot geometry is
##   the same for both sides (records' touch rects), so the guest's taps are side 1's panel coordinates as they are.
##   VS intro (team blocks not loaded yet): side 1's ids from the party block. Fades: the lower engine's MASTER_BRIGHT.
##   Debug `lanpanel=0`: draw side 0 the same way in any battle (pixel check against the game's own panel).
## - Both machines in a LAN battle: "PING xx ms" under the Team Arts plate (phase 4: game font BOLD, "PING" in the game's
##   yellow, the value white, black outline; a 3-bar signal icon in front as the only colour hint: 3 green bars < 30 ms,
##   2 yellow < 80 ms, else 1 red); top-screen bands (QoLMpSelect look): WAITING FOR PLAYER (a lockstep stall over 0.5 s),
##   CONNECTION LOST / <NAME> LEFT / DESYNC while the battle is being left alone (6.1).
## - Team select (scene 4): "WAITING FOR <NAME>…" while this machine is ready and the other is not; "<NAME> IS READY" when
##   the other one is — phase 4: written in the top screen's own name strip (black, x 8..247, y 138..160, under the three
##   portraits) instead of a band across the portraits.

const TEAMS := 0x020DE3D0
const SCENE := 0x020DD4C4
const SUP_MIN := 26
const NUL := 37
const STRIP_Y := 136
const PING_POS := Vector2(8, 179)        ## the signal icon's left edge / the text's cap top (free strip y 177..191 under the plate)
const PING_LABEL := Color8(251, 203, 0)  ## the game's yellow (DRAGONPOWER box, HUD)
const PING_TEXT := Color8(251, 251, 251)
const PING_HINT := [Color8(56, 224, 72), Color8(251, 203, 0), Color8(255, 56, 40)]   ## < 30 ms, < 80 ms, more
const PING_OFF := Color8(40, 40, 72)
const NAME_STRIP := Rect2(8, 138, 240, 23)    ## scene 4 top screen: the black strip with the team's names
const TRIM := QoLMenu.TRIM
const TEXT := QoLMenu.HEX_TEXT
const PCOL := QoLMpMenu.PCOL
const BLUE := [0x7C00, 0x4000]           ## the diamond in P2 blue (lit / dim) instead of red (row 5 / 6 index 11)

var qol                                  ## QoLController
var lan: QoLLan
var art: QoLMpPanel                      ## ROM art helpers (portrait indices, e_pairatk)
var font: QoLFont
var shown := false                       ## the guest's side-1 panel covers the game's this frame
var low: Node2D                          ## lower screen (panel, ping)
var top: Node2D                          ## upper screen (bands)
var pan: Node2D                          ## the panel: palette-index picture drawn through the live palette (shader)
var txt: Node2D                          ## the ping text
var _idx := PackedByteArray()            ## 256 x 192 indices: row * 16 + colour, 255 = not covered
var _itex: ImageTexture
var _pimg: Image                         ## 16 x 9 palette: game rows 0-7, row 8 = the strip's row (diamond recoloured)
var _ptex: ImageTexture
var _pal_key := PackedByteArray()
var _key := []
var _fade := 0.0
var _ping := ""
var _band := ""
var _band_col := TEXT
var _sel_band := ""
var _side := 1
var _dbg_side := -1
var _recs: Array = []                    ## side shown: [rec, k] of each record (skull markers)
var _sup_seen := false                   ## the support had assists in this battle (greyed only after they ran out)


func _init() -> void:
	z_index = 80
	low = Node2D.new()
	low.position = Vector2(0, 192)
	pan = Node2D.new()
	pan.draw.connect(_draw_pan)
	txt = Node2D.new()
	txt.draw.connect(_draw_low)
	low.add_child(pan)
	low.add_child(txt)
	top = Node2D.new()
	top.z_index = 6
	top.draw.connect(_draw_top)
	add_child(low)
	add_child(top)
	_dbg_side = int(Game.flag("lanpanel", "-1"))


func setup(q) -> void:
	qol = q
	lan = q.lan
	art = q.mp_panel
	font = q.font
	_idx.resize(256 * 192)
	_idx.fill(255)
	_itex = ImageTexture.create_from_image(Image.create_from_data(256, 192, false, Image.FORMAT_R8, _idx))
	_pimg = Image.create(16, 9, false, Image.FORMAT_RGBA8)
	_ptex = ImageTexture.create_from_image(_pimg)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D pal : filter_nearest;
uniform float mul = 1.0;
void fragment() {
	int v = int(round(texelFetch(TEXTURE, ivec2(UV * vec2(256.0, 192.0)), 0).r * 255.0));
	if (v == 255) { discard; }
	COLOR = vec4(texelFetch(pal, ivec2(v % 16, v / 16), 0).rgb * mul, 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("pal", _ptex)
	pan.material = mat


## after every game frame (QoLController.after_step)
func frame(core) -> void:
	var sess: bool = lan != null and (lan.state != QoLLan.IDLE or lan.in_battle or lan.aborting)
	if not sess and _dbg_side < 0:
		if visible:
			visible = false
			shown = false
			_ping = ""
			_band = ""
			_sel_band = ""
		return
	visible = true
	var sc: int = core.r8(SCENE)
	var st: int = core.r8(SCENE + 1)
	var disp: DSDisplay = qol.game.display
	var on_battle: bool = disp.battle_on_screen()
	var lan_b: bool = lan.in_battle or lan.aborting
	# ---- the guest's side-1 panel
	# part 32: the side of the battle on screen (the guest's role is cleared when the session ends while the battle is
	# still being left: it showed the host's panel then), and in EVERY battle state incl. the pause (9): the game's pause
	# menu is on the upper screen, its lower screen keeps the side-0 panel (the guest saw the host's team / red Touch!)
	var side := (1 if lan.battle_side == 1 else -1) if lan_b else (1 if lan.role == "guest" else -1)
	if _dbg_side >= 0 and not lan_b:
		side = _dbg_side
	var show_panel: bool = art != null and art._ok and side >= 0 and sc == 0 and (lan_b or _dbg_side >= 0) \
		and (on_battle or (st >= 2 and st <= 3))
	if show_panel:
		_side = side
		var key := _read(core, side)
		if key != _key:
			_key = key
			_compose(key)
		_palette(core, key)
	if show_panel or (lan_b and sc == 0 and on_battle):
		var mb: int = core.IO.decode_u16(0x106C if (core.IO.decode_u16(0x304) & 0x8000) != 0 else 0x6C)
		var f := minf((mb & 31) / 16.0, 1.0)
		var mode := (mb >> 14) & 3
		var fade := f if mode == 1 else (-f if mode == 2 else 0.0)
		if fade != _fade:
			_fade = fade
			pan.queue_redraw()
			txt.queue_redraw()
	if show_panel != shown:
		shown = show_panel
		pan.queue_redraw()
		if not shown:
			_key = []
			_sup_seen = false
	# ---- ping (both machines, battle screen)
	var ping := ""
	if lan_b and sc == 0 and on_battle and lan.connected():   # (part 32: also while paused)
		ping = "PING %s ms" % (str(lan.ping_ms) if lan.ping_ms >= 0 else "--")
	if ping != _ping:
		_ping = ping
		txt.queue_redraw()
	# ---- top bands
	_sc = sc
	update_bands()
	if _band != "" or _sel_band != "":
		var swap: bool = (core.IO.decode_u16(0x304) & 0x8000) != 0
		var bu := QoLController._mp_bright(core, 0 if swap else 0x1000)
		if top.modulate.r != bu:
			top.modulate = Color(bu, bu, bu)


var _sc := -1


## the top-screen bands; also every Godot frame while a LAN session runs (QoLController.lan_poll): a lockstep stall
## shows WAITING FOR PLAYER although no game frame (and no after_step) comes
func update_bands() -> void:
	if lan == null or (lan.state == QoLLan.IDLE and not lan.in_battle and not lan.aborting):
		if _band != "" or _sel_band != "":
			_band = ""
			_sel_band = ""
			top.queue_redraw()
		return
	var sc := _sc
	var band := ""
	var bcol := TEXT
	if lan.aborting:
		match lan.abort_reason:
			"DESYNC": band = "DESYNC"
			"LOST": band = "CONNECTION LOST"
			"LEFT": band = "%s LEFT" % (lan.peer_name if lan.peer_name != "" else (lan.last_peer if lan.last_peer != "" else "THE OTHER PLAYER"))
			_: band = "CONNECTION LOST"
		bcol = Color8(255, 90, 90)
	elif lan.waiting():
		band = "WAITING FOR PLAYER"
	var sb := ""
	if lan.sel_on() and sc == 4 and not lan.force_leave:
		var nm: String = lan.peer_name if lan.peer_name != "" else "PLAYER"
		if lan.loc_ready and not lan.remote_ready():
			sb = "WAITING FOR %s" % nm
		elif not lan.loc_ready and lan.remote_ready():
			sb = "%s IS READY" % nm
	if band != _band or sb != _sel_band or bcol != _band_col:
		_band = band
		_band_col = bcol
		_sel_band = sb
		top.queue_redraw()


## what side `side`'s panel shows: [lit, [id, row] x 3]
func _read(core, side: int) -> Array:
	var teams: int = core.r32(TEAMS)
	var slots := []
	var lit := false
	_recs = []
	var ok := teams >= 0x02000000 and teams < 0x02400000
	if ok:
		var n: int = core.r8(teams + side * 0x8E8 + 0x8C9)
		ok = n >= 1 and n <= 3 and core.r8(teams + side * 0x8E8 + 5) < NUL
	if ok:
		var tb: int = teams + side * 0x8E8
		var cnt: int = clampi(core.r8(tb + 0x8C9), 0, 3)
		var act: int = core.r8(tb + 0x8C8)
		var assists: int = core.r8(tb + 0x8CA)
		var ki: int = core.r16(tb + 0x8D0)
		var act0: int = core.r8(teams + 0x8C8)          # the game's own panel (side 0): its active slot's row is the
		var arow: int = clampi(act0, 0, 2) + 1           # one the game keeps lit (same contents for every slot)
		for k in 3:
			if k >= cnt:
				slots.append([NUL, 0])
				continue
			var r := tb + k * 0x2D8
			var id: int = core.r8(r + 5)
			var hp: int = core.r16(r + 0x24A)
			if hp >= 0x8000:
				hp -= 0x10000
			var row := 0
			if hp <= 0 and id < SUP_MIN:
				row = 4
			elif k == act:
				row = arow if side == 1 else k + 1
			elif id >= SUP_MIN:                          # (FUN_0201CDCC: greyed when the assists drop to 0)
				if assists > 0:
					_sup_seen = true
				row = 4 if assists == 0 and _sup_seen else 0
			elif ki < 0x1400:
				row = 7
			slots.append([id if id < 38 else NUL, row])
			_recs.append([r, k])
		var ar: int = tb + act * 0x2D8
		lit = ki >= 0xC800 and cnt > 1 and (core.r32(ar + 0x274) & 0x100) != 0
	else:                                                # VS intro: the party block, first member active
		var cnt: int = clampi(core.r8(0x020DD548 + side), 0, 3)
		for k in 3:
			var id: int = core.r32(0x020DD524 + side * 0xC + k * 4) if k < cnt else NUL
			if id < 0 or id >= 38:
				id = NUL
			slots.append([id, 1 if k == 0 and id != NUL else 0])
	return [lit, slots]


## the index picture: three portraits (row * 16 + colour) and the strip (row 8 = rows 5 / 6 with the diamond recoloured)
var compose_us := 0                      ## part 32 debug (lanpace): time spent composing the index picture
var composes := 0


func _compose(key: Array) -> void:
	var t0 := Time.get_ticks_usec()
	_idx.fill(255)
	var slots: Array = key[1]
	for k in 3:
		var id: int = slots[k][0]
		var base: int = int(slots[k][1]) * 16
		var px: PackedByteArray = art._portrait_px(id)
		var x0 := 8 + 80 * k
		for y in 128:
			var o := (8 + y) * 256 + x0
			var i := y * 80
			for x in 80:
				_idx[o + x] = base + px[i + x]
	var pair: PackedByteArray = art._pair
	if pair.size() >= 256 * (192 - STRIP_Y):          # (the bar's map rows 0.. sit at tile row 17 of the game's BG)
		for i in range(0, (192 - STRIP_Y) * 256):
			_idx[STRIP_Y * 256 + i] = 128 + (pair[i] & 15)
	_itex.update(Image.create_from_data(256, 192, false, Image.FORMAT_R8, _idx))
	_pal_key = PackedByteArray()                     # the strip's row may have changed (lit / dim)
	pan.queue_redraw()
	compose_us += Time.get_ticks_usec() - t0
	composes += 1


## the game's lower-screen BG palette rows 0-7 (palette RAM, engine B) -> the shader's palette (only when it changed)
func _palette(core, key: Array) -> void:
	var pal: PackedByteArray = core.hw.pal.slice(0x400, 0x400 + 8 * 32)
	var k2 := pal.duplicate()
	k2.append(1 if key[0] else 0)
	k2.append(_side)
	if k2 == _pal_key:
		return
	_pal_key = k2
	for r in 9:
		var sr: int = r if r < 8 else (5 if key[0] else 6)
		for c in 16:
			var v: int = pal.decode_u16(sr * 32 + c * 2)
			if r == 8 and c == 11 and _side == 1:
				v = BLUE[0] if key[0] else BLUE[1]
			_pimg.set_pixel(c, r, _lcd(v))
	_ptex.update(_pimg)
	pan.queue_redraw()


## a BGR555 colour as the port's 2D renderer shows it (6-bit LCD: c6 = c5 << 1, out = c6 << 2 | c6 >> 4)
static func _lcd(v: int) -> Color:
	var r := (v & 31) * 2
	var g := ((v >> 5) & 31) * 2
	var b := ((v >> 10) & 31) * 2
	return Color8(r * 4 + (r >> 4), g * 4 + (g >> 4), b * 4 + (b >> 4))


func _draw_pan() -> void:
	if shown and _itex != null:
		(pan.material as ShaderMaterial).set_shader_parameter("mul", 1.0 + minf(_fade, 0.0))
		pan.draw_texture(_itex, Vector2.ZERO)


func _draw_low() -> void:
	if _ping != "" and font != null:
		_draw_ping(1.0 + minf(_fade, 0.0))
	if _fade > 0.0 and (shown or _ping != ""):       # (a fade to white: only over what the port covers; part 32: the
		if shown:                                    # PING too -- it stayed on a white screen in the VS intro)
			for k in 3:
				txt.draw_rect(Rect2(8 + 80 * k, 8, 80, 128), Color(1, 1, 1, _fade))
		txt.draw_rect(Rect2(0, STRIP_Y, 256, 192 - STRIP_Y), Color(1, 1, 1, _fade))


## "▮▮▮ PING 12 ms": signal bars (the colour hint) + the text in the game's font, white / yellow on a black outline
func _draw_ping(m2: float) -> void:
	var p := lan.ping_ms
	var q := -1 if p < 0 else (0 if p < 30 else (1 if p < 80 else 2))
	var lit := 0 if q < 0 else 3 - q
	var bottom := PING_POS.y + QoLFont.CAP[QoLFont.BOLD]
	var blk := Color(0, 0, 0, m2)
	for k in 3:
		var h := 4.0 + 3.0 * k
		var r := Rect2(PING_POS.x + 4 * k, bottom - h, 3, h)
		txt.draw_rect(r.grow(1), blk)
		var c: Color = PING_HINT[q] if k < lit else PING_OFF
		txt.draw_rect(r, Color(c.r * m2, c.g * m2, c.b * m2))
	var x := PING_POS.x + 16
	var lab := "PING"
	var val := (" %d ms" % p) if p >= 0 else " -- ms"
	font.draw(txt, Vector2(x, PING_POS.y), lab, Color(PING_LABEL.r * m2, PING_LABEL.g * m2, PING_LABEL.b * m2), QoLFont.BOLD, blk)
	x += font.width(lab, QoLFont.BOLD) + 1
	font.draw(txt, Vector2(x, PING_POS.y), val, Color(PING_TEXT.r * m2, PING_TEXT.g * m2, PING_TEXT.b * m2), QoLFont.BOLD, blk)


## a black band with orange trim and centred text (QoLMpSelect look)
func _band_at(ci: CanvasItem, r: Rect2, text: String, col: Color) -> void:
	ci.draw_rect(r, Color.BLACK)
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), TRIM)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), TRIM)
	font.draw_centered(ci, r, text, col, QoLFont.BIG)


func _draw_top() -> void:
	if font == null:
		return
	if _band != "":
		_band_at(top, Rect2(0, 84, 256, 23), _band, _band_col)
	if _sel_band != "" and _band == "":
		# phase 4: in the team select's own name strip (the band at y 84 covered the portraits)
		top.draw_rect(NAME_STRIP, Color.BLACK)
		var waiting := _sel_band.begins_with("WAITING")
		font.draw_centered(top, NAME_STRIP, _sel_band + ("..." if waiting else ""), TEXT if waiting else PING_LABEL, QoLFont.BIG)


## BOSS CHARACTERS skulls on the guest's panel: where record `rec` (side 1) is shown ((-1, -1) = not on this panel)
func mark_at(rec: int) -> Vector2:
	if not shown:
		return Vector2(-1, -1)
	for e in _recs:
		if e[0] == rec:
			return Vector2(8 + 80 * int(e[1]) + 2, 192 + 10)
	return Vector2(-1, -1)
