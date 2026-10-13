class_name QoLMpSelect
extends Node2D
# ---- MULTIPLAYER SELECT (part 27)
## LOCAL MULTIPLAYER marks on the game's own character select / stage select / battle (docs/MULTIPLAYER_DESIGN.md
## 3.5 / 3.6, phase 7). The screens themselves are the game's (QoLGame `# ---- MULTIPLAYER SELECT` drives them); this
## node only adds, in the look of the setup page (QoLMpMenu: black bands with orange trim, slanted player tags in the
## players' colours, QoLFont):
## - character select, upper screen: a "1P" tag at the PLAYER list and a "2P" tag at the ENEMY list; a READY plate
##   for each player who is done (START / full team).
## - stage select, lower screen: the chosen stage of each player gets its tag; upper screen: a band "1P / 2P"
##   with each player's state (CHOOSING / READY) and the 50/50 roulette's result.
## - battle end (scene 0, battle state 0x10-0x13 after a KO): a "PLAYER n WINS" band on the upper screen.
## Read from QoLMp / RAM after every game frame (frame()); faded with the game's MASTER_BRIGHT / BLDY of each screen.

const PCOL := QoLMpMenu.PCOL
const TRIM := QoLMenu.TRIM
const TEXT := QoLMenu.HEX_TEXT
const ST_XY := 0x020D0768                    ## stage icon positions u16 x, y (stride 8): top-left of the 72 x 32 icon

var qol                                      ## QoLController
var mp: QoLMp
var font: QoLFont
var top: Node2D
var low: Node2D
var mode := ""                               ## "", "select", "stage", "win"
var _state := []                             ## what is drawn (redraw only on change)
var _icons := []                             ## stage: [x, y] per icon
var _win := -1


func _init() -> void:
	z_index = 85                             # above the MP battle panel (80), below the boss skulls / cursors
	top = Node2D.new()
	low = Node2D.new()
	low.position = Vector2(0, 192)
	top.draw.connect(_draw_top)
	low.draw.connect(_draw_low)
	add_child(top)
	add_child(low)
	visible = false


## after every game frame (QoLController.after_step)
func frame(core) -> void:
	if mp == null:
		return
	var sc: int = core.r8(0x020DD4C4)
	var m := ""
	if mp.active and not mp.debug_battle:
		if sc == 3 and mp.stage == QoLMp.SELECT:
			m = "select"
		elif sc == 5 and mp.stage == QoLMp.STAGE:
			m = "stage"
		elif sc == 0 and mp.stage == QoLMp.BATTLE:
			var w := _winner(core)
			if w >= 0:
				m = "win"
				_win = w
	elif qol != null and qol.lan.state == QoLLan.STAGE and qol.lan.sel_on() and not qol.lan.force_leave and sc == 5:
		m = "stage"                              # part 30 phase 3: the LAN stage select (1P = host red, 2P = guest blue)
	var st := [m]
	match m:
		"select":
			st.append_array([mp.ready[0], mp.ready[1]])
		"stage":
			st.append_array([mp.chosen[0], mp.chosen[1], mp.cand, mp.winner])
			if _icons.is_empty():
				for i in 16:
					_icons.append(Vector2(core.r16(ST_XY + i * 8), core.r16(ST_XY + 2 + i * 8)))
		"win":
			st.append(_win)
	if st != _state:
		_state = st
		mode = m
		visible = m != ""
		top.queue_redraw()
		low.queue_redraw()
	if visible:
		var swap: bool = (core.IO.decode_u16(0x304) & 0x8000) != 0
		var bl := QoLController._mp_bright(core, 0x1000 if swap else 0)
		var bu := QoLController._mp_bright(core, 0 if swap else 0x1000)
		if low.modulate.r != bl:
			low.modulate = Color(bl, bl, bl)
		if top.modulate.r != bu:
			top.modulate = Color(bu, bu, bu)


## battle states 0x10-0x13 (u8 0x020DD4C5 in scene 0: KO → results) of a finished MP battle: the winning player
## (loser record u32 [teams + 0x11D4], its side byte +0x1A; FUN_0202921C), else -1
static func _winner(core) -> int:
	var st: int = core.r8(0x020DD4C5)
	if st < 0x10 or st > 0x13:
		return -1
	var teams: int = core.r32(0x020DE3D0)
	if teams < 0x02000000 or teams >= 0x02400000:
		return -1
	var loser: int = core.r32(teams + 0x11D4)
	if loser < teams or loser >= teams + 0x11D0:
		return -1
	return 1 - (core.r8(loser + 0x1A) & 1)


# ------------------------------------------------------------------------------------------------ drawing
## the player tag of the setup page: a slanted block in the player's colour with "1P" / "2P"
func _tag(ci: CanvasItem, x: float, y: float, p: int) -> void:
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x + 4, y), Vector2(x + 23, y), Vector2(x + 19, y + 13), Vector2(x, y + 13)]), Color.BLACK)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x + 5, y + 1), Vector2(x + 22, y + 1), Vector2(x + 18, y + 12), Vector2(x + 1, y + 12)]), PCOL[p])
	font.draw_centered(ci, Rect2(x + 2, y + 2, 19, 9), "%dP" % (p + 1), TEXT, QoLFont.BOLD)


## a black band with orange trim and a tag + text
func _band(ci: CanvasItem, r: Rect2, p: int, text: String, col: Color = TEXT) -> void:
	ci.draw_rect(r, Color.BLACK)
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), TRIM)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), TRIM)
	if p >= 0:
		_tag(ci, r.position.x + 3, r.position.y + (r.size.y - 13) / 2.0, p)
		font.draw(ci, Vector2(r.position.x + 30, r.position.y + (r.size.y - 13) / 2.0), text, col, QoLFont.BIG)
	else:
		font.draw_centered(ci, r, text, col, QoLFont.BIG)


func _draw_top() -> void:
	match mode:
		"select":
			_tag(top, 80, 21, 0)                 # at "■PLAYER" (under P1's D·P bar)
			_tag(top, 174, 157, 1)               # at "■ENEMY" (above P2's D·P bar)
			if mp.ready[0]:
				_band(top, Rect2(0, 164, 112, 19), 0, "READY")
			if mp.ready[1]:
				_band(top, Rect2(144, 5, 112, 19), 1, "READY")
		"stage":
			for p in 2:
				var t := "READY" if int(mp.chosen[p]) >= 0 else "CHOOSING"
				_band(top, Rect2(2 + p * 128, 174, 124, 17), p, t, TEXT if int(mp.chosen[p]) >= 0 else Color8(200, 200, 200))
		"win":                                   # under the fighters, above the life bars
			var t := "PLAYER %d WINS!" % (_win + 1)
			var w := font.width(t, QoLFont.HEAVY)
			var x := roundi((256 - w - 28) / 2.0)
			_band(top, Rect2(0, 150, 256, 23), -1, "")
			_tag(top, x, 155, _win)
			font.draw(top, Vector2(x + 28, 156), t, Color8(255, 230, 64), QoLFont.HEAVY, Color.BLACK)


func _draw_low() -> void:
	if mode != "stage" or _icons.is_empty():
		return
	# the chosen stage of each player: its tag at the icon's top edge (P1 left, P2 right; both on one: side by side)
	for p in 2:
		var ic: int = mp.chosen[p]
		if ic < 0 or ic >= 16:
			continue
		var c: Vector2 = _icons[ic]                  # the icon's top-left corner (72 x 32)
		_tag(low, c.x + 9 + p * 30, c.y - 5, p)
