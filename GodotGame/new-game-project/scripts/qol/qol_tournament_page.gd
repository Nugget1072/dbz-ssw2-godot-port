class_name QoLTournamentPage
extends Node2D
# ---- TOURNAMENT PAGE (part 43)
## The TOURNAMENT bracket page (docs/ALLSTAR_DESIGN.md 9), over both screens like the ALL-STAR records page and built
## from the same ROM art (QoLAllStarRecords: the scrolling hexagons, the face icons, the CharFace256 portraits; read from
## the player's ROM, nothing stored), lettered in the port's heavy capitals:
## - UPPER screen: the round ("QUARTER-FINAL" .. "FINAL", or "CHAMPION!" / "KNOCKED OUT") and the match: player 1's
##   portraits on the left, the opponent's on the right, VS between them; the tournament titles won so far.
## - LOWER screen: the bracket, 8 teams (3 face icons each) in two columns of 4, lines joining each match to the next
##   round, a won line yellow; player 1's team framed yellow, the match about to be fought blinking, beaten teams
##   dimmed. Buttons FIGHT! / QUIT (QUIT asks again: "CONFIRM"), or OK when the tournament is over.
## Keys: Left / Right move between the buttons, A / START press the one chosen; B goes to QUIT (pressed again: quit).
## Taps on a button press it. The page takes every key / tap while shown.
## Opened by QoLTournament.page_req (the game thread: a new bracket / a match ended). While it shows before a match,
## the battle scene waits (QoLTournament.hold, QoLGame f_02013064); FIGHT clears `hold` when the page has faded out.
## Tournament titles: `tournament_records.cfg` next to the exe (`tnrec=PATH`; captures without it: none), [records]
## titles = n, best = {"frames", "ids", "date"} (the fastest tournament won); nothing is written while cheats are on.

const FILE := "tournament_records.cfg"
const FADE := 16
const FPS := 59.8261
const ENTRY_W := 76                          ## a bracket entry: 3 face icons (24 px) + a 2-px frame
const ENTRY_H := 28
const COL_X := [4, 176]                      ## left / right column
const ROW_Y := [22, 56, 90, 124]             ## entry tops (lower screen)
const BTN_Y := 160
const BTN_H := 26
const FIGHT_RECT := Rect2i(28, 160, 104, 26)
const QUIT_RECT := Rect2i(144, 160, 84, 26)
const OK_RECT := Rect2i(78, 160, 100, 26)
const YELLOW := Color8(255, 205, 0)
const WHITE := Color8(248, 248, 248)
const GREY := Color8(120, 120, 120)
const PLATE := Color8(248, 208, 0)          ## the game's button plates (yellow, black letters)
const PLATE_DARK := Color8(176, 128, 0)

var qol                                      ## QoLController
var allstar: QoLAllStar
var font: QoLFont
var shown := false
var dbg := false
var tour: QoLTournament
var titles := 0                              ## tournaments won (file)
var best := {}                               ## the fastest tournament won (file)
var note := ""                               ## champion page: "" saved / "cheats" / "nofile"
var _phase := 0                              ## 0 fade in, 1 input, 2 fade out, 3 reveal
var _t := 0
var _ht := 0
var _focus := 0                              ## 0 FIGHT (or OK), 1 QUIT
var _sure := false                           ## QUIT pressed once
var _press := -1                             ## button held down by a touch
var _ports := {}                             ## id -> portrait texture (80 x 40)


func _init() -> void:
	z_index = 900
	visible = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func setup(q) -> void:
	qol = q
	allstar = q.allstar
	font = q.font
	dbg = Game.args.has("tndbg") or Game.args.has("asdbg")


# ------------------------------------------------------------------------------------------------ titles file
static func path() -> String:
	if Game.args.has("tnrec"):
		return Game.flag("tnrec")
	if Game.args.has("capture"):
		return ""
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join(FILE)
	return "user://" + FILE


static func load_titles() -> Array:
	var p := path()
	if p == "":
		return [0, {}]
	var c := ConfigFile.new()
	var err := c.load(p)
	if err != OK and OS.has_feature("template") and not Game.args.has("tnrec"):
		err = c.load("user://" + FILE)
	if err != OK:
		return [0, {}]
	var n: Variant = c.get_value("records", "titles", 0)
	var b: Variant = c.get_value("records", "best", {})
	var bd := {}
	if b is Dictionary and (b.get("frames") is int) and int(b.get("frames")) > 0:
		bd = b
	return [clampi(int(n) if (n is int or n is float) else 0, 0, 99999), bd]


static func save_titles(n: int, b: Dictionary) -> bool:
	var p := path()
	if p == "":
		return false
	var c := ConfigFile.new()
	c.set_value("records", "titles", n)
	if not b.is_empty():
		c.set_value("records", "best", b)
	var err := c.save(p)
	if err != OK and OS.has_feature("template") and not Game.args.has("tnrec"):
		err = c.save("user://" + FILE)
	return err == OK


## part 43 (settings HI-SCORES RESET): the titles file removed too
static func reset_file() -> void:
	var ps := [path()]
	if OS.has_feature("template") and not Game.args.has("tnrec"):
		ps.append("user://" + FILE)
	for p in ps:
		if p != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ------------------------------------------------------------------------------------------------ open / close
## after every game frame (QoLController.after_step)
func frame(_core) -> void:
	if not shown:
		if allstar != null and allstar.tour != null and allstar.tour.page_req:
			allstar.tour.page_req = false
			_open()
		return
	_t += 1
	_ht += 1
	if _phase == 0 and _t >= FADE:
		_phase = 1
	elif _phase == 2 and _t >= FADE:
		_phase = 3
		_t = 0
		if tour != null and tour.state == "on":
			tour.hold = false                    # FIGHT: the battle scene goes on (it fades in by itself)
			_log("FIGHT: the battle loads")
	elif _phase == 3 and _t >= FADE:
		shown = false
		visible = false
		_log("closed")
	queue_redraw()


func _open() -> void:
	tour = allstar.tour
	var art: QoLAllStarRecords = qol.as_records
	art._ensure_art()
	var tl := load_titles()
	titles = tl[0]
	best = tl[1]
	note = ""
	if tour.state == "champion":
		var cheats: int = qol.settings.cheats_on()
		var ids: Array = (tour.teams[tour.p1_slot] as Array).duplicate()
		if tour.p1_support < 37 and ids.size() < 3:
			ids.append(tour.p1_support)
		var e := {"frames": maxi(1, tour.battle_time), "ids": ids, "date": Time.get_datetime_string_from_system(false, true)}
		if cheats > 0:
			note = "cheats"
		else:
			titles += 1
			if best.is_empty() or int(e.frames) < int(best.get("frames", 1 << 30)):
				best = e
			if not save_titles(titles, best):
				note = "nofile"
	_ports.clear()
	if art._ok:
		for s in tour.teams.size():
			for id in tour.teams[s]:
				if not _ports.has(id) and art._face_px.has(id):
					_ports[id] = ImageTexture.create_from_image(art._face_px[id].image(art._face_pal))
	_focus = 0
	_sure = false
	_press = -1
	shown = true
	visible = true
	_phase = 0
	_t = 0
	_ht = 0
	_log("open: state %s round %d titles %d note '%s'" % [tour.state, tour.round, titles, note])
	queue_redraw()


func _over() -> bool:
	return tour == null or tour.state != "on"


func _press_button(b: int, how: String) -> void:
	if _phase != 1:
		return
	queue_redraw()
	if _over() or b == 0:
		_phase = 2
		_t = 0
		qol.se(QoLController.SE_DECIDE)
		_log("%s by %s" % ["OK" if _over() else "FIGHT", how])
		return
	if not _sure:                                # QUIT: asks once more
		_sure = true
		_focus = 1
		qol.se(QoLController.SE_MOVE)
		_log("QUIT? by %s" % how)
		return
	qol.se(QoLController.SE_BACK)
	tour.quit_req = true                         # the held battle scene goes back to the team select
	tour.hold = true
	_phase = 2
	_t = 0
	_log("QUIT by %s" % how)


## main thread, before each game frame while shown: every key / tap is the page's
func filter(newly: int, down: int, touch: Vector2i, new_touch: bool) -> Array:
	qol._block_keys = down
	qol._block_touch = touch.x >= 0
	_press = -1
	var rects := _rects()
	for i in rects.size():
		if touch.x >= 0 and (rects[i] as Rect2i).has_point(touch):
			_press = i
	if _phase == 1:
		if new_touch:
			for i in rects.size():
				if (rects[i] as Rect2i).has_point(touch):
					_press_button(i, "tap %d/%d" % [touch.x, touch.y])
		elif (newly & 9) != 0:                   # A / START
			_press_button(_focus, "A" if (newly & 1) != 0 else "START")
		elif (newly & 2) != 0:                   # B: QUIT (again: quit); over: OK
			_press_button(0 if _over() else 1, "B")
		elif (newly & 0x30) != 0 and not _over():
			_focus = 1 - _focus
			_sure = _sure and _focus == 1
			qol.se(QoLController.SE_MOVE)
	return [0x3FF, 0x2C00, Vector2i(-1, -1)]


func _rects() -> Array:
	return [OK_RECT] if _over() else [FIGHT_RECT, QUIT_RECT]


func _log(s: String) -> void:
	if dbg:
		print("TN f%d page %s" % [qol.game.frames if qol != null and qol.get("game") != null else -1, s])


# ------------------------------------------------------------------------------------------------ drawing
func _draw() -> void:
	if not shown or tour == null:
		return
	if tour.p1_slot < 0 or tour.teams.size() != QoLTournament.SIZE:   # (QUIT: the bracket is gone while the page fades)
		draw_rect(Rect2(0, 0, 256, 384), Color.BLACK)
		return
	var a := 0.0
	if _phase == 0:
		a = 1.0 - float(_t) / FADE
	elif _phase == 2:
		a = float(_t) / FADE
	elif _phase == 3:
		draw_rect(Rect2(0, 0, 256, 384), Color(0, 0, 0, 1.0 - float(_t) / FADE) if _over() else Color.BLACK)
		return
	draw_rect(Rect2(0, 0, 256, 384), Color.BLACK)
	var art: QoLAllStarRecords = qol.as_records
	if art._ok and art._hex is Texture2D:
		var off := QoLAllStarRecords.HEX_ORIGIN + QoLAllStarRecords.HEX_SPEED * float(_ht)
		var src := Rect2(Vector2(floorf(off.x), floorf(off.y)), Vector2(256, 192))
		draw_texture_rect_region(art._hex, Rect2(0, 0, 256, 192), src, Color(0.55, 0.55, 0.55))
		draw_texture_rect_region(art._hex, Rect2(0, 192, 256, 192), src, Color(0.55, 0.55, 0.55))
	_draw_top()
	_draw_low(art)
	if a > 0.0:
		draw_rect(Rect2(0, 0, 256, 384), Color(0, 0, 0, a))


func _blink() -> bool:
	return (_ht / 10) % 2 == 0


func _band(y: int, h: int) -> void:
	draw_rect(Rect2(0, y, 256, h), Color(0, 0, 0, 0.78))
	draw_rect(Rect2(0, y, 256, 1), YELLOW)
	draw_rect(Rect2(0, y + h - 1, 256, 1), YELLOW)


## upper screen: the round, the match (portraits + VS), the titles
func _draw_top() -> void:
	_band(6, 26)
	var title: String = "CHAMPION!" if tour.state == "champion" else ("KNOCKED OUT" if tour.state == "out" else
		QoLTournament.ROUND_NAMES[tour.round])
	font.draw_centered(self, Rect2(0, 6, 256, 26), title, YELLOW if tour.state != "out" else WHITE, QoLFont.HEAVY, Color.BLACK)
	var p1: Array = tour.teams[tour.p1_slot]
	var opp := -1
	if tour.state == "on":
		opp = tour.opponent()
	elif tour.state == "out":
		opp = tour.winners[tour.round][tour.p1_match(tour.round)]
	for k in 3:                                       # player 1 (left), the opponent / the beaten final (right)
		_portrait(p1[k] if k < p1.size() else -1, Vector2(8, 40 + 44 * k), false)
		if opp >= 0:
			_portrait(tour.teams[opp][k] if k < (tour.teams[opp] as Array).size() else -1, Vector2(168, 40 + 44 * k), true)
	if tour.state == "champion":
		font.draw_centered(self, Rect2(88, 70, 80, 20), "WINNER", YELLOW, QoLFont.HEAVY, Color.BLACK)
		font.draw_centered(self, Rect2(88, 96, 80, 14), "TITLES %d" % titles, WHITE, QoLFont.BOLD, Color.BLACK)
		font.draw_centered(self, Rect2(88, 112, 80, 14), "TIME %s" % _time(tour.battle_time), WHITE, QoLFont.BOLD, Color.BLACK)
		if note != "":
			font.draw_centered(self, Rect2(88, 128, 80, 14), "CHEATS ON" if note == "cheats" else "FILE ERROR", GREY, QoLFont.BOLD, Color.BLACK)
	elif opp >= 0:
		font.draw_centered(self, Rect2(88, 84, 80, 24), "VS", YELLOW, QoLFont.HEAVY, Color.BLACK)
		if tour.state == "on":
			font.draw_centered(self, Rect2(88, 112, 80, 14), "ROUND %d/3" % (tour.round + 1), WHITE, QoLFont.BOLD, Color.BLACK)
	_band(174, 16)
	var foot := "TITLES WON: %d" % titles
	if not best.is_empty():
		foot += "   BEST %s" % _time(int(best.get("frames", 0)))
	font.draw_centered(self, Rect2(0, 174, 256, 16), foot, WHITE, QoLFont.BOLD, Color.BLACK)


func _portrait(id: int, at: Vector2, flip: bool) -> void:
	draw_rect(Rect2(at - Vector2(2, 2), Vector2(84, 44)), Color.BLACK)
	draw_rect(Rect2(at - Vector2(2, 2), Vector2(84, 44)), YELLOW, false, 1.0)
	if _ports.has(id):
		var tx: Texture2D = _ports[id]
		if flip:                                     # the opponent faces left (as the game's VS screen)
			draw_set_transform(at + Vector2(80, 0), 0.0, Vector2(-1, 1))
			draw_texture(tx, Vector2.ZERO)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_texture(tx, at)


static func _time(frames: int) -> String:
	var s := mini(int(frames / FPS), 5999)
	return "%02d:%02d" % [s / 60, s % 60]


## lower screen: title band, bracket lines, entries, buttons
func _draw_low(art: QoLAllStarRecords) -> void:
	var o := 192
	_band(o + 2, 16)
	font.draw_centered(self, Rect2(0, o + 2, 256, 16), "TOURNAMENT", WHITE, QoLFont.HEAVY, Color.BLACK)
	# lines: the whole bracket grey first (a round-r path from every spot, any slot of that branch), then the won
	# paths yellow (a slot's round-r path: from its spot to the next round's)
	for r in QoLTournament.ROUNDS:
		for s in range(0, QoLTournament.SIZE, 1 << r):
			_path(s, r, o, Color(0.72, 0.72, 0.72))
	for r in QoLTournament.ROUNDS:
		for m in tour.winners[r].size():
			var w: int = tour.winners[r][m]
			if w >= 0:
				_path(w, r, o, YELLOW)
	var ch := tour.champion()
	if ch >= 0:                                       # the cup spot: the champion's leader face in the centre
		draw_rect(Rect2(114, o + 79, 28, 28), YELLOW)
		_face_at(art, tour.teams[ch][0], Vector2(116, o + 81), false)
	for s in QoLTournament.SIZE:
		_entry(art, s, o)
	# buttons
	if _over():
		_button(OK_RECT, "OK", true, _press == 0)
	else:
		_button(FIGHT_RECT, "FIGHT!", _focus == 0, _press == 0)
		_button(QUIT_RECT, "CONFIRM" if _sure else "QUIT", _focus == 1, _press == 1)


## the spot of slot s at the start of round r (r 0 = its entry's inner edge), x / y on the lower screen
func _spot(s: int, r: int, o: int) -> Vector2:
	var right := s >= 4
	var xs: Array = [80, 92, 106, 118] if not right else [176, 164, 150, 138]
	var cy: float
	if r == 0:
		cy = ROW_Y[s % 4] + ENTRY_H / 2.0
	elif r == 1:
		var p := (s % 4) >> 1
		cy = (ROW_Y[p * 2] + ROW_Y[p * 2 + 1]) / 2.0 + ENTRY_H / 2.0
	else:
		cy = (ROW_Y[0] + ROW_Y[3]) / 2.0 + ENTRY_H / 2.0
	return Vector2(xs[r], o + floorf(cy))


## slot s's line from round r's spot to round r+1's (horizontal out, vertical to the match's middle, on)
func _path(s: int, r: int, o: int, c: Color) -> void:
	var a := _spot(s, r, o)
	var b := _spot(s, r + 1, o)
	var w := 3.0 if c == YELLOW else 2.0
	var xm := floorf(lerpf(a.x, b.x, 0.5))
	if r == 2:                                       # the final: straight into the centre
		_seg(a, Vector2(b.x, a.y), c, w)
		return
	_seg(a, Vector2(xm, a.y), c, w)
	_seg(Vector2(xm, a.y), Vector2(xm, b.y), c, w)
	_seg(Vector2(xm, b.y), b, c, w)


## an axis-aligned line as a rect (crisp pixels), with a black edge so it reads on the hexagons
func _seg(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(floorf(w / 2), floorf(w / 2)),
		Vector2(absf(b.x - a.x) + w, absf(b.y - a.y) + w))
	draw_rect(r.grow(1), Color(0, 0, 0, 0.8))
	draw_rect(r, c)


func _face_at(art: QoLAllStarRecords, id: int, at: Vector2, dim: bool) -> void:
	if art._faces.has(id) and art._faces[id] is Texture2D:
		draw_texture(art._faces[id], at, Color(0.4, 0.4, 0.4) if dim else Color.WHITE)
	else:
		draw_rect(Rect2(at, Vector2(24, 24)), Color(0.2, 0.2, 0.2))


func _entry(art: QoLAllStarRecords, s: int, o: int) -> void:
	var x: int = COL_X[0 if s < 4 else 1]
	var y: int = o + ROW_Y[s % 4]
	var out: bool = tour.reached(s) < QoLTournament.ROUNDS and _played_out(s)
	var cur := tour.state == "on" and (s == tour.p1_slot or s == tour.opponent())
	var frame := Color(0.55, 0.55, 0.55)
	if s == tour.p1_slot:
		frame = YELLOW
	if cur and _blink() and _phase <= 1:
		frame = WHITE
	if tour.state == "champion" and s == tour.p1_slot:
		frame = YELLOW if _blink() else WHITE
	draw_rect(Rect2(x, y, ENTRY_W, ENTRY_H), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(x, y, ENTRY_W, ENTRY_H), frame, false, 2.0)
	var ids: Array = tour.teams[s]
	for k in 3:
		_face_at(art, ids[k] if k < ids.size() else -1, Vector2(x + 2 + 24 * k, y + 2), out)
	if s == tour.p1_slot:                             # "1P" tag on the frame
		var tx := x + (ENTRY_W - 14 if s < 4 else 0)
		draw_rect(Rect2(tx, y - 7, 14, 9), YELLOW)
		font.draw(self, Vector2(tx + 2, y - 6), "1P", Color.BLACK, QoLFont.REGULAR)


## slot s lost a match that was played
func _played_out(s: int) -> bool:
	for r in QoLTournament.ROUNDS:
		var w: int = tour.winners[r][s >> (r + 1)]
		if w < 0:
			return false
		if w != s:
			return true
	return false


func _button(rc: Rect2i, text: String, focus: bool, pressed: bool) -> void:
	var r := Rect2(rc)
	r.position.y += 192                              # (the rects are lower-screen touch coordinates)
	if pressed or (_phase == 2 and focus):
		r.position += Vector2(1, 1)
	draw_rect(r, Color.BLACK)
	draw_rect(r.grow(-1), PLATE_DARK if pressed else PLATE)
	draw_rect(Rect2(r.position + Vector2(1, r.size.y - 4), Vector2(r.size.x - 2, 3)), PLATE_DARK)
	font.draw_centered(self, Rect2(r.position, Vector2(r.size.x, r.size.y - 2)), text, Color.BLACK, QoLFont.HEAVY)
	if focus and (_blink() or _phase != 1):          # the cursor: a white frame, as the results' cursor
		draw_rect(r.grow(2), WHITE, false, 2.0)
