class_name QoLLanMenu
extends Control
# ---- LAN MENU (part 30)
## LAN MULTIPLAYER pages (docs/LAN_DESIGN.md 6), drawn by the port over the game's VS BATTLE screen (scene 0x11,
## state 2, only BG1's hexagons kept) after LAN was chosen on the LOCAL / LAN screen (QoLMpMenu relabel overlay):
## - "lan": HOST / JOIN (+ BACK = the LOCAL / LAN screen). Each opens a warning popup first (YES / NO, NO first):
##   the room uses the HOST's cheats and weird options, settings stay each player's own; trust who you play with.
## - "name": the room setup page with the on-screen keyboard (QoLKeyboard): DISPLAY NAME (HOST: + this PC's
##   address, read only; JOIN: + the host's IP[:PORT]). OK / START / ENTER -> "ARE YOU SURE?" popup -> YES:
##   HOST opens the room (QoLLan.host) -> "lobby"; JOIN connects (QoLLan.join) -> "connecting".
## - "connecting": countdown; no answer in 15 s (CONNECT_FRAMES) or connect_failed -> "UNABLE TO CONNECT" popup ->
##   back to "name"; rejected -> the reason (other version / other ROM / room full).
## - "lobby": both names on the upper screen (HOST red / GUEST blue plates), ping, status (WAITING FOR PLAYER /
##   CONNECTED / DECLINED). HOST: START (or the CHARACTER SELECT button) sends the proposal; the guest gets an
##   ACCEPT / DENY popup; DENY -> both stay in the lobby (host: "<GUEST> SAID NO", status DECLINED); ACCEPT -> QoLLan
##   state SELECT (phase 3: QoLGame.f_0207b778 returns 1 on both machines -> scene 4). B -> "LEAVE THE ROOM?".
##   The other player leaving / the connection lost -> a notice.
## Input: QoLController.filter_input hands every frame's buttons / taps here (the DS sees nothing while a page is
## open); real keyboard typing arrives through key_event (QoLController.raw_input). The session itself is QoLLan
## (QoLController.lan, phase 1), read through `qol.get("lan")` (null = not available).

const TRIM := QoLMenu.TRIM
const HEX_EDGE := QoLMenu.HEX_EDGE
const HEX_TEXT := QoLMenu.HEX_TEXT
const HEX_RED := QoLMenu.HEX_RED
const CURSOR := QoLMenu.CURSOR
const PCOL := QoLMpMenu.PCOL                 ## HOST red, GUEST blue (the P1 / P2 colours)
const DIM := QoLKeyboard.DIM
const TITLE_BAR := QoLMpMenu.TITLE_BAR
const BOX_STRIPES := QoLMpMenu.BOX_STRIPES
const BOX := QoLMpMenu.BOX
const TEXT := QoLMpMenu.TEXT
const YELLOW := Color8(255, 206, 0)
const CONNECT_FRAMES := 897                  ## 15 s of game frames (59.83 per second)
const DEFAULT_PORT := 8082
const BACK_RECT := Rect2(211, 4, 41, 20)
const HOST_RECT := Rect2(12, 58, 112, 50)
const JOIN_RECT := Rect2(132, 58, 112, 50)
const START_RECT := Rect2(36, 122, 184, 30)
const CANCEL_RECT := Rect2(88, 140, 80, 24)
const POPUP_Y := 46
## DS buttons (KEYINPUT layout) of the ds_* actions, to keep keys typed on a real keyboard out of the D-pad / A / B
const DS_BITS := {"ds_a": 0x1, "ds_b": 0x2, "ds_select": 0x4, "ds_start": 0x8, "ds_right": 0x10, "ds_left": 0x20,
	"ds_up": 0x40, "ds_down": 0x80, "ds_r": 0x100, "ds_l": 0x200}
const B_A := 0x1
const B_B := 0x2
const B_SELECT := 0x4
const B_START := 0x8
const B_RIGHT := 0x10
const B_LEFT := 0x20
const B_UP := 0x40
const B_DOWN := 0x80
const B_R := 0x100
const B_L := 0x200

var qol                                      ## QoLController (or the preview tool's stand-in)
var font: QoLFont:
	set(v):
		font = v
		if kb != null:
			kb.font = v
var top: Control                             ## the upper-screen part (own modulate: engine B's brightness)
var kb: QoLKeyboard
var overlay: Control                         ## popups, drawn over the keyboard
var page := ""                               ## "" closed, "lan", "name", "connecting", "lobby"
var role := ""                               ## "host" / "join" (chosen on the "lan" page)
var popup := {}                              ## {} or {kind, title, lines, buttons [[id, text]], col, b, then, desc}
var row := 0
var col := 0
var status := ""                             ## lobby: "", "ASKING", "DECLINED", "STARTING"
var address := ""                            ## JOIN: "ip:port" being connected to / connected to
var _rows: Array = []
var _ignore := 0
var _kb_held := {}                           ## real keys typed (consumed): keycode -> DS bits kept from the menu
var _kb_mask := 0
var _held_frames := {}
var _flash := {}
var _frames := 0                             ## "connecting": game frames since the attempt started
var _dbg := false


func _init() -> void:
	position = Vector2(0, 192)
	size = Vector2(256, 192)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # taps arrive through the game's touch input (frame_input)
	visible = false
	top = Control.new()
	top.position = Vector2(0, -192)
	top.size = Vector2(256, 192)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.draw.connect(_draw_top)
	add_child(top)
	kb = QoLKeyboard.new()
	kb.visible = false
	add_child(kb)
	overlay = Control.new()
	overlay.size = Vector2(256, 192)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_popup)
	add_child(overlay)
	_dbg = Game.args.has("lanmenudbg")


func is_open() -> bool:
	return page != ""


## the LAN session (QoLController.lan, phase 1) or null
func _lan():
	return qol.get("lan") if qol != null else null


func lan_state() -> String:
	var l = _lan()
	return l.state_name() if l != null else "IDLE"


## the other player is in the room (handshake done)
func peer_in() -> bool:
	return not lan_state() in ["IDLE", "HOSTING", "CONNECTING"]


func _log(s: String) -> void:
	if _dbg:
		print("LANMENU f%d %s" % [qol.game.frames if qol != null and qol.get("game") != null else 0, s])


# ------------------------------------------------------------------------------------------------ pages
## LAN chosen on the LOCAL / LAN screen
func open_lan() -> void:
	_set_page("lan")                         # cursor on the last choice (HOST / JOIN; part 31)
	_ignore = 0xFFF


## back on the VS screen while the session still runs (phase 3: back from the character select): the lobby again
func open_lobby() -> void:
	var l = _lan()
	role = "host" if l != null and l.role == "host" else "join"
	status = ""
	var prop := false
	for guard in 64:                             # events from while the pages were closed: the state says it all
		var e: Dictionary = l.pop_event() if l != null else {}
		if e.is_empty():
			break
		if e.get("type", "") == "proposal":      # part 30 phase 3: the host asked before this page was back (still open)
			prop = true
	_set_page("lobby")
	_ignore = 0xFFF
	if prop and role == "join" and lan_state() == "LOBBY":
		_event({"type": "proposal"})


func close() -> void:
	page = ""
	popup = {}
	kb.visible = false
	_kb_held = {}
	_kb_mask = 0
	_update()


func _set_page(p: String) -> void:
	page = p
	popup = {}
	if p != "lobby":
		status = ""
	_build()
	row = 0
	col = 0
	match p:
		"lan":
			row = 1
			col = 0 if role != "join" else 1
		"name":
			row = kb.fields.size() + 1          # the first key row
		"lobby":
			row = _rows.size() - 1                # host with a guest: CHARACTER SELECT; else LEAVE
		"connecting":
			row = 0
	_log("page %s role %s" % [p, role])
	_update()


func _update() -> void:
	if page == "lobby":                          # the START button comes / goes with the guest
		var had := _rows.size()
		_build()
		if _rows.size() != had:
			row = _rows.size() - 1
			col = 0
	visible = page != ""
	kb.visible = page == "name"
	kb.cursor_id = "" if not popup.is_empty() else cur_id()
	kb.flash = _flash
	kb.queue_redraw()
	queue_redraw()
	overlay.queue_redraw()
	top.queue_redraw()


func _build() -> void:
	_rows = [[{"id": "back", "rect": BACK_RECT}]]
	match page:
		"lan":
			_rows.append([{"id": "host", "rect": HOST_RECT}, {"id": "join", "rect": JOIN_RECT}])
		"name":
			_rows += kb.rows()
		"connecting":
			_rows = [[{"id": "cancel", "rect": CANCEL_RECT}]]
		"lobby":
			_rows = [[{"id": "leave", "rect": BACK_RECT}]]
			if role == "host" and peer_in():     # (no guest yet: a WAITING band, no button)
				_rows.append([{"id": "start", "rect": START_RECT}])


## the name page for HOST / JOIN: boxes from the last session (settings [lan])
func _open_name() -> void:
	var s = qol.settings
	var nm: String = str(s.get("lan_name")) if s.get("lan_name") != null else ""
	var ip: String = str(s.get("lan_ip")) if s.get("lan_ip") != null else ""
	var f := [{"label": "NAME", "text": nm.to_upper().left(QoLKeyboard.NAME_MAX), "max": QoLKeyboard.NAME_MAX, "ip": false, "hint": "DISPLAY NAME"}]
	if role == "join":
		f.append({"label": "IP", "text": ip.left(QoLKeyboard.IP_MAX), "max": QoLKeyboard.IP_MAX, "ip": true, "hint": "192.168.1.23"})
		kb.info = ""
	else:
		kb.info_label = "THIS PC"
		kb.info = _addr_line()
	kb.setup(f, 0 if nm == "" or role == "host" or ip != "" else 1)
	_set_page("name")


## this PC's first LAN address and the port (HOST): "192.168.1.5 : 8082"
func _addr_line() -> String:
	var a := _addresses()
	var port := _port()
	return ("%s : %d" % [a[0], port]) if not a.is_empty() else "NO NETWORK FOUND"


func _addresses() -> Array:
	var l = _lan()
	return Array(l.local_addresses()) if l != null else Array(QoLLanNet.local_addresses())


func _port() -> int:
	var l = _lan()
	if l != null and int(l.port) > 0 and lan_state() != "IDLE":
		return int(l.port)
	return DEFAULT_PORT


func cur_id() -> String:
	if row < 0 or row >= _rows.size() or col < 0 or col >= _rows[row].size():
		return ""
	return _rows[row][col]["id"]


# ------------------------------------------------------------------------------------------------ popups
func _popup(kind: String, title: String, lines: Array, buttons: Array, c: int, b: String, then := "", desc := "") -> void:
	popup = {"kind": kind, "title": title, "lines": lines, "buttons": buttons, "col": c, "b": b, "then": then, "desc": desc}
	_ignore = 0xFFF                            # buttons still held (ENTER, A) do not answer it at once
	_log("popup %s %s" % [kind, title])
	_update()


## part 30 phase 3: a notice from QoLLan (`notice`: the session came back to the room from a select / battle)
func show_notice(n: Dictionary) -> void:
	qol.se(QoLController.SE_BACK)
	var then := str(n.get("then", ""))
	if then == "lobby" and page != "lobby":
		then = page
	_notice(str(n.get("title", "")), n.get("lines", []), then)


func _notice(title: String, lines: Array, then: String, desc := "") -> void:
	if desc == "" and not (page == "lobby" and then == "lobby"):   # (in the room: the room's names / status stay up)
		desc = "%s\n\nOK (A / START / ENTER / a tap):\n%s" % [title,
			{"lan": "back to HOST / JOIN.", "name": "back to the room setup.", "lobby": "back to the room."}.get(then if then != "" else page, "go on.")]
	_popup("notice", title, lines, [["notice_ok", "OK"]], 0, "notice_ok", then, desc)


func _popup_rects() -> Array:
	var bs: Array = popup["buttons"]
	var y := _popup_btn_y()
	if bs.size() == 1:
		return [Rect2(98, y, 60, 24)]
	return [Rect2(56, y, 66, 24), Rect2(134, y, 66, 24)]


func _popup_h() -> int:
	return 34 + popup["lines"].size() * 12 + 36


func _popup_btn_y() -> int:
	return POPUP_Y + _popup_h() - 31


# ------------------------------------------------------------------------------------------------ actions
func _press(id: String) -> void:
	if id == "":
		return
	_flash[id] = 0.15
	var l = _lan()
	var p := id.split(":")
	match p[0]:
		"back":
			qol.se(QoLController.SE_BACK)
			if page == "lan":
				qol.lan_menu_back()          # closes the pages: the LOCAL / LAN screen again
				return
			_set_page("lan")
		"host", "join":
			qol.se(QoLController.SE_DECIDE)
			role = id
			if id == "host":
				_popup("warn", "HOST A ROOM?", ["THE PLAYER WHO JOINS USES YOUR", "CHEATS AND WEIRD OPTIONS.",
					"THEIR SETTINGS (FPS, DISPLAY, SOUND,", "CONTROLS) ARE NOT CHANGED.", "ONLY INVITE PEOPLE YOU TRUST."],
					[["warn_yes", "YES"], ["warn_no", "NO"]], 1, "warn_no", "",
					"HOST: your cheats and weird\noptions are copied to the player\nwho joins (only while in your\nroom; never saved there).\nYES: on to your display name.")
			else:
				_popup("warn", "JOIN A ROOM?", ["YOU WILL USE THE HOST'S CHEATS", "AND WEIRD OPTIONS (YOURS COME",
					"BACK WHEN YOU LEAVE). YOUR SETTINGS", "(FPS, DISPLAY, SOUND, CONTROLS)", "ARE NOT CHANGED. ONLY JOIN", "PEOPLE YOU TRUST."],
					[["warn_yes", "YES"], ["warn_no", "NO"]], 1, "warn_no", "",
					"JOIN: while in the host's room\nyou play with THEIR cheats and\nweird options. Yours are kept\nand come back when you leave\n(even after a crash).")
		"warn_yes":
			qol.se(QoLController.SE_DECIDE)
			_open_name()
			_ignore = 0xFFF
		"warn_no":
			qol.se(QoLController.SE_BACK)
			popup = {}
		"field":
			qol.se(QoLController.SE_MOVE)
			kb.active = int(p[1])
			kb.blink = 0
			row = kb.fields.size() + 1               # on to the keys
			col = 0
		"key":                                   # (id.substr: the ":" key's id is "key::")
			var ok := kb.type(id.substr(4))
			_log("key '%s' %s box %d" % [id.substr(4), "typed" if ok else "refused", kb.active])
			qol.se(QoLController.SE_MOVE if ok else QoLController.SE_BACK)
		"space":
			qol.se(QoLController.SE_MOVE if kb.type(" ") else QoLController.SE_BACK)
		"del":
			qol.se(QoLController.SE_MOVE if kb.backspace() else QoLController.SE_BACK)
		"ok":
			_ok()
		"sure_yes":
			qol.se(QoLController.SE_DECIDE)
			popup = {}
			_start()
		"sure_no":
			qol.se(QoLController.SE_BACK)
			popup = {}
		"cancel":
			qol.se(QoLController.SE_BACK)
			if l != null:
				l.leave()
			_set_page("name")
			kb.active = 1
		"start":
			if role != "host":
				return
			if not peer_in() or status == "ASKING" or status == "STARTING":
				qol.se(QoLController.SE_BACK)
				return
			qol.se(QoLController.SE_DECIDE)
			status = "ASKING"
			l.propose_select()
		"leave":
			qol.se(QoLController.SE_DECIDE)
			_popup("leave", "LEAVE THE ROOM?", ["THE OTHER PLAYER GOES BACK" if role == "host" else "YOU GO BACK TO THE LAN PAGE.",
				"TO THE LAN PAGE." if role == "host" else ""] if peer_in() else ["THE ROOM CLOSES."],
				[["leave_yes", "YES"], ["leave_no", "NO"]], 1, "leave_no")
		"leave_yes":
			qol.se(QoLController.SE_BACK)
			if l != null:
				l.leave()
			_set_page("lan")
		"leave_no":
			qol.se(QoLController.SE_BACK)
			popup = {}
		"accept":
			qol.se(QoLController.SE_DECIDE)
			popup = {}
			status = "STARTING"
			l.accept_select()                    # phase 3: QoLLan state SELECT -> QoLGame.f_0207b778 returns 1
		"deny":
			qol.se(QoLController.SE_BACK)
			popup = {}
			status = "DECLINED"
			l.deny_select()
		"notice_ok":
			qol.se(QoLController.SE_DECIDE)
			var then: String = popup.get("then", "")
			var fld: int = popup.get("field", -1)
			popup = {}
			if then != "" and then != page:
				_set_page(then)
			if fld >= 0 and fld < kb.fields.size():
				kb.active = fld
	_update()


## OK / START / ENTER on the name page: the boxes checked, then "ARE YOU SURE?"
func _ok() -> void:
	var nm := kb.text(0).strip_edges()
	_log("ok name '%s' ip '%s'" % [kb.text(0), kb.text(1)])
	if nm == "":
		qol.se(QoLController.SE_BACK)
		kb.active = 0
		_notice("NO DISPLAY NAME", ["TYPE A NAME FOR THE OTHER PLAYER", "TO SEE (UP TO 10 LETTERS)."], "")
		return
	if role == "join":
		var a := QoLLanNet.parse_address(kb.text(1))
		if a.is_empty():
			qol.se(QoLController.SE_BACK)
			kb.active = 1
			_notice("WRONG IP ADDRESS", ["TYPE THE HOST'S ADDRESS, LIKE", "192.168.1.23 OR 192.168.1.23:8082", "(THE HOST'S ROOM SHOWS IT)."], "")
			return
		qol.se(QoLController.SE_DECIDE)
		_popup("sure", "CONNECT?", ["NAME   " + nm, "HOST   %s:%d" % [a[0], a[1]]], [["sure_yes", "YES"], ["sure_no", "NO"]], 0, "sure_no", "",
			"Your display name and the host's\naddress. YES: connect now.\nNO: change them.")
		return
	qol.se(QoLController.SE_DECIDE)
	_popup("sure", "USE THIS NAME?", [nm], [["sure_yes", "YES"], ["sure_no", "NO"]], 0, "sure_no", "",
		"The other player sees this name.\nYES: open the room and wait.\nNO: change it.")


## YES on "ARE YOU SURE?": the room is opened / the connection attempt starts
func _start() -> void:
	var nm := kb.text(0).strip_edges()
	var s = qol.settings
	if s.get("lan_name") != null:
		s.set("lan_name", nm)
		if role == "join":
			s.set("lan_ip", kb.text(1).strip_edges())
		s.save_file()
	var l = _lan()
	if l == null:
		_notice("LAN NOT AVAILABLE", ["THIS VERSION CANNOT OPEN", "NETWORK ROOMS YET."], "lan")
		return
	status = ""
	if role == "host":
		if not l.host(nm, int(Game.flag("lanport", str(DEFAULT_PORT)))):   # (debug `lanport=N`: tests next to other rooms)
			_notice("CAN'T OPEN THE ROOM", ["PORTS 8082-8091 ARE IN USE (ANOTHER", "PROGRAM OR ANOTHER COPY OF THE", "GAME). CLOSE IT AND TRY AGAIN."], "name")
			return
		_set_page("lobby")
		return
	var a := QoLLanNet.parse_address(kb.text(1))
	address = "%s:%d" % [a[0], a[1]]
	_frames = 0
	l.join(nm, a[0], a[1])
	_set_page("connecting")


# ------------------------------------------------------------------------------------------------ per frame
## once per game frame while a page is open (QoLController): the network, its events, the connect timeout
func tick() -> void:
	if page == "":
		return
	if page == "name":
		kb.blink += 1
		if kb.blink % 30 == 0:
			kb.queue_redraw()
	var l = _lan()
	if l == null:
		return
	for guard in 32:                             # (QoLLan.poll runs every Godot frame: QoLController.lan_poll)
		var e: Dictionary = l.pop_event()
		if e.is_empty():
			break
		_event(e)
	if page == "connecting" and popup.is_empty():
		_frames += 1
		if _frames % 20 == 0:
			queue_redraw()
			top.queue_redraw()
		if _frames >= CONNECT_FRAMES and lan_state() == "CONNECTING" and not l.has_method("connect_left"):   # (QoLLan: its own 15 s)
			l.leave()
			_unable()
	if page == "lobby" and popup.is_empty() and lan_state() == "IDLE":   # ended without an event
		_set_page("lan")
	if page == "lobby" and Engine.get_process_frames() % 30 == 0:
		top.queue_redraw()                       # ping
		queue_redraw()


## seconds left of the 15 s connect attempt (QoLLan's real-time timer; else counted in game frames)
func _left() -> int:
	var l = _lan()
	if l != null and l.has_method("connect_left") and lan_state() == "CONNECTING":
		return ceili(l.connect_left())
	return maxi(0, ceili((CONNECT_FRAMES - _frames) / 59.83))


func _unable(reason := "") -> void:
	qol.se(QoLController.SE_BACK)
	_notice("UNABLE TO CONNECT", ["NO ROOM ANSWERED AT", address, "CHECK THE IP AND THAT THE HOST IS", "IN ITS ROOM (AND ITS FIREWALL)."], "name",
		"Nobody answered%s.\nThe HOST must be waiting in its\nroom; Windows: the host allows\nthe firewall prompt (Private\nnetworks). Same network?" % ("" if reason == "" else " (" + reason.left(18) + ")"))
	popup["field"] = 1


func _event(e: Dictionary) -> void:
	var t: String = e.get("type", "")
	var l = _lan()
	_log("event %s" % [e])
	match t:
		"connected":
			if page == "connecting":
				qol.se(QoLController.SE_DECIDE)
				status = ""
				_set_page("lobby")
		"connect_failed":
			if page == "connecting":
				_unable(str(e.get("reason", "")))
		"rejected":
			var r := str(e.get("reason", "")).to_upper()
			qol.se(QoLController.SE_BACK)
			if r.begins_with("VERSION"):
				_notice("DIFFERENT GAME VERSION", ["THE HOST RUNS ANOTHER VERSION OF", "THIS PORT. BOTH PLAYERS NEED THE", "SAME VERSION."], "name")
			elif r.begins_with("ROM"):
				_notice("DIFFERENT ROM", ["THE HOST'S GAME FILE (ROM) IS NOT", "THE SAME AS YOURS. BOTH PLAYERS", "NEED THE SAME ROM."], "name")
			elif r.begins_with("FULL"):
				_notice("ROOM IS FULL", ["THIS ROOM ALREADY HAS A", "SECOND PLAYER."], "name")
			else:
				_notice("CONNECTION REFUSED", [r.left(34)], "name")
		"peer_joined":
			if role == "host":
				qol.se(QoLController.SE_DECIDE)
				status = ""
		"peer_left", "lost":
			var who: String = str(l.peer_name) if l != null and str(l.peer_name) != "" else ("THE GUEST" if role == "host" else "THE HOST")
			if l != null and str(l.peer_name) == "" and l.get("last_peer") != null and str(l.last_peer) != "":
				who = str(l.last_peer)                   # (phase 4: QoLLan clears peer_name before the event is read)
			var ended := lan_state() == "IDLE"
			var then := "lobby" if role == "host" and not ended else "lan"
			status = ""
			if page == "lobby" or page == "connecting":
				qol.se(QoLController.SE_BACK)
				if t == "lost":
					_notice("CONNECTION LOST", ["NO ANSWER FROM %s." % who.to_upper()], then)
				else:
					_notice("%s LEFT" % who.to_upper(), ["THE ROOM IS OPEN AGAIN." if then == "lobby" else "THE ROOM WAS CLOSED."], then)
		"proposal":
			if role == "join" and page == "lobby" and lan_state() != "LOBBY":   # already accepted (debug `lanauto`)
				status = "STARTING"
			elif role == "join" and page == "lobby":
				qol.se(QoLController.SE_DECIDE)
				var host_name := str(l.peer_name).to_upper() if l != null else "THE HOST"
				_popup("proposal", "CHARACTER SELECT?", ["%s WANTS TO GO TO THE" % host_name, "CHARACTER SELECT."],
					[["accept", "ACCEPT"], ["deny", "DENY"]], 0, "deny", "",
					"%s asks to start: both go\nto the character select.\nDENY: you both stay in the room\n(the host can ask again)." % str(l.peer_name if l != null else "The host"))
		"proposal_denied":
			if role == "host":
				status = "DECLINED"
				qol.se(QoLController.SE_BACK)
				_notice("%s SAID NO" % str(l.peer_name).to_upper(), ["YOU BOTH STAY IN THE ROOM.", "PRESS START TO ASK AGAIN."], "lobby")
		"proposal_accepted":
			if role == "host":
				status = "STARTING"
				qol.se(QoLController.SE_DECIDE)
	_update()


# ------------------------------------------------------------------------------------------------ input
## once per game frame while a page is open (QoLController.filter_input): KEYINPUT bits (1 = pressed) of the
## frame's new presses / held buttons, `tap` = where a touch began (lower-screen pixels) or (-1, -1)
func frame_input(newly: int, down: int, tap: Vector2i) -> void:
	if page == "":
		return
	var dn := down & ~_kb_mask
	_ignore &= dn
	var nw := newly & ~_ignore & ~_kb_mask
	dn &= ~_ignore
	if status == "STARTING" and popup.is_empty():   # accepted: waiting for the scene change (phase 3); B still leaves
		if nw & B_B:
			_press("leave")
		return
	if tap.x >= 0:
		_tap(Vector2(tap))
		return
	var moved := false
	for b in [B_UP, B_DOWN, B_LEFT, B_RIGHT]:
		if (dn & b) == 0:
			_held_frames.erase(b)
			continue
		var f: int = _held_frames.get(b, -1) + 1
		_held_frames[b] = f
		if f == 0 or (f >= 21 and (f - 21) % 6 == 0):
			moved = _move(b) or moved
	if moved:
		qol.se(QoLController.SE_MOVE)
		_update()
	if not popup.is_empty():
		if nw & (B_A | B_START):
			_press(popup["buttons"][popup["col"]][0])
		elif nw & B_B:
			_press(popup["b"])
		return
	if nw & B_START and page == "name":
		_press("ok")
	elif nw & B_START and page == "lobby" and role == "host":
		_press("start")
	elif nw & B_A:
		_press(cur_id())
	elif nw & B_B:
		_back()
	elif nw & (B_L | B_R | B_SELECT) and page == "name" and kb.fields.size() > 1:
		_switch_field()


func _switch_field() -> void:
	qol.se(QoLController.SE_MOVE)
	kb.next_field()
	if row >= 1 and row <= kb.fields.size():   # the cursor on a box follows
		row = 1 + kb.active
	_update()


func _back() -> void:
	match page:
		"lan":
			_press("back")
		"name":
			if kb.text(kb.active) != "":           # B deletes; on an empty box it goes back
				_press("del")
			else:
				_press("back")
		"connecting":
			_press("cancel")
		"lobby":
			_press("leave")


func _move(b: int) -> bool:
	if not popup.is_empty():
		var n: int = popup["buttons"].size()
		if b == B_LEFT or b == B_RIGHT:
			var c := clampi(popup["col"] + (1 if b == B_RIGHT else -1), 0, n - 1)
			if c != popup["col"]:
				popup["col"] = c
				return true
		return false
	if _rows.size() <= 1 and _rows[0].size() <= 1:
		return false
	if b == B_LEFT or b == B_RIGHT:
		var n: int = _rows[row].size()
		if n <= 1:
			return false
		col = posmod(col + (1 if b == B_RIGHT else -1), n)
		return true
	var x: float = _rows[row][col]["rect"].get_center().x
	row = posmod(row + (1 if b == B_DOWN else -1), _rows.size())
	col = _nearest(row, x)
	if page == "name" and row >= 1 and row <= kb.fields.size():
		kb.active = row - 1                       # on a box: that box gets the typing
	return true


## the button of row r whose centre is nearest to x
func _nearest(r: int, x: float) -> int:
	var best := 0
	var bd := 1e9
	for i in _rows[r].size():
		var d := absf(_rows[r][i]["rect"].get_center().x - x)
		if d < bd:
			bd = d
			best = i
	return best


func _tap(p: Vector2) -> void:
	if not popup.is_empty():
		var rs := _popup_rects()
		for i in rs.size():
			if rs[i].grow(1).has_point(p):
				popup["col"] = i
				_press(popup["buttons"][i][0])
				return
		return
	for r in _rows.size():
		for i in _rows[r].size():
			var b: Dictionary = _rows[r][i]
			if b["rect"].grow(1).has_point(p):
				row = r
				col = i
				if b["id"].begins_with("field:"):     # a tap on a box: it gets the typing, the cursor stays there
					qol.se(QoLController.SE_MOVE)
					kb.active = int(b["id"].substr(6))
					kb.blink = 0
					_update()
					return
				_press(b["id"])
				return
	if page == "name":                           # a tap on a box's label
		for i in kb.fields.size():
			if Rect2(0, QoLKeyboard.FIELD_Y[i], 58, 20).has_point(p):
				row = 1 + i
				col = 0
				kb.active = i
				qol.se(QoLController.SE_MOVE)
				_update()
				return


## a raw key event (QoLController.raw_input): on the name page printable keys type, BACKSPACE deletes, ENTER is
## OK, TAB switches the box, ESC goes back; ESC anywhere = B. Returns true when the event was used (it then does
## not reach the game's input map: its DS buttons are kept from the page until the key is released).
func key_event(e: InputEvent) -> bool:
	if page == "" or not e is InputEventKey:
		return false
	var k: InputEventKey = e
	var code := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if not k.pressed:
		if _kb_held.has(code):
			_kb_held.erase(code)
			_kb_mask = 0
			for v in _kb_held.values():
				_kb_mask |= v
			return true
		return false
	if code == KEY_F3 or code == KEY_F11:
		return false
	var used := false
	var typing := page == "name" and popup.is_empty() and status != "STARTING"
	if code == KEY_ESCAPE:
		if not k.echo:
			if not popup.is_empty():
				_press(popup["b"])
			elif page == "name":
				_press("back")
			else:
				_back()
		used = true
	elif typing:
		var ch := _char_of(k)
		if code == KEY_BACKSPACE or code == KEY_DELETE:
			_press("del")
			used = true
		elif code == KEY_ENTER or code == KEY_KP_ENTER:
			if not k.echo:
				_press("ok")
			used = true
		elif code == KEY_TAB:
			if not k.echo:
				_switch_field()
			used = true
		elif ch != "":
			var ok := kb.type(ch)
			_log("key '%s' %s box %d" % [ch, "typed" if ok else "refused", kb.active])
			qol.se(QoLController.SE_MOVE if ok else QoLController.SE_BACK)
			_flash["key:" + ch.to_upper()] = 0.12
			_update()
			used = true
	if used:
		var bits := 0
		for a in DS_BITS:
			if InputMap.has_action(a) and e.is_action(a):
				bits |= DS_BITS[a]
		_kb_held[code] = bits
		_kb_mask |= bits
		_ignore |= bits
	return used


## the printable character of a key event ("" = none): its unicode, or for scripted keys (no unicode) the keycode
static func _char_of(k: InputEventKey) -> String:
	if k.unicode >= 32 and k.unicode < 127:
		return char(k.unicode)
	var c := k.keycode
	if c >= KEY_A and c <= KEY_Z:
		return char(c)
	if c >= KEY_0 and c <= KEY_9:
		return char(c)
	if c >= KEY_KP_0 and c <= KEY_KP_9:
		return char(KEY_0 + c - KEY_KP_0)
	match c:
		KEY_PERIOD, KEY_KP_PERIOD: return "."
		KEY_COLON: return ":"
		KEY_MINUS, KEY_KP_SUBTRACT: return "-"
		KEY_UNDERSCORE: return "_"
		KEY_SPACE: return " "
	return ""


## the game's fade (QoLController._mp_bright of each engine): 1 = full, 0 = black
func set_brightness(lower: float, upper: float) -> void:
	var cl := Color(lower, lower, lower)
	var cu := Color(upper, upper, upper)
	if self_modulate != cl:
		self_modulate = cl
		kb.modulate = cl
		overlay.modulate = cl
	if top.modulate != cu:
		top.modulate = cu


func _process(delta: float) -> void:
	if not visible or _flash.is_empty():
		return
	for k in _flash.keys():
		_flash[k] -= delta
		if _flash[k] <= 0.0:
			_flash.erase(k)
	queue_redraw()
	kb.queue_redraw()
	overlay.queue_redraw()


# ------------------------------------------------------------------------------------------------ texts
func focus_title() -> String:
	if not popup.is_empty() and popup["kind"] == "warn":
		return "WARNING"
	match page:
		"lan":
			match cur_id():
				"host": return "HOST"
				"join": return "JOIN"
				"back": return "BACK"
			return "LAN BATTLE"
		"name":
			return "HOST ROOM" if role == "host" else "JOIN ROOM"
		"connecting":
			return "CONNECTING"
		"lobby":
			return "LAN ROOM"
	return ""


func focus_desc() -> String:
	if not popup.is_empty() and popup.get("desc", "") != "":
		return popup["desc"]
	match page:
		"lan":
			match cur_id():
				"host":
					var a := _addresses()
					return "Open a room on this PC and wait\nfor a friend on your network.\nThey play with YOUR cheats and\nweird options while there.\nThis PC: %s" % (a[0] if not a.is_empty() else "no network found")
				"join":
					return "Join a friend's room: type the\nIP address their room shows.\nYou play with the HOST's cheats\nand weird options while there;\nyours come back when you leave."
				"back":
					return "Back to LOCAL / LAN.\n(B does the same.)"
		"name":
			if role == "host":
				return "Type your DISPLAY NAME (max 10):\nkeyboard, or D-pad + A / taps.\nB / BACKSPACE: delete a letter.\nSTART / ENTER: done.\nTell your friend: %s" % _addr_line().replace(" : ", ":")
			return "Your DISPLAY NAME and the HOST's\nIP (shown in the host's room),\ne.g. 192.168.1.23 or with :PORT.\nTAB / L / R / tap: other box.\nSTART / ENTER: connect."
		"connecting":
			return "Connecting to\n%s ...\nThe host must be in its room.\nGiving up in %d s. B: cancel." % [address, _left()]
	return ""


# ------------------------------------------------------------------------------------------------ drawing
func _draw() -> void:
	match page:
		"lan":
			_draw_lan()
		"name":
			_plate("HOST ROOM" if role == "host" else "JOIN ROOM")
			QoLKeyboard.hex(self, font, BACK_RECT, "BACK", popup.is_empty() and cur_id() == "back", _flash.has("back"))
		"connecting":
			_draw_connecting()
		"lobby":
			_draw_lobby()


func _plate(t: String) -> void:
	draw_rect(Rect2(0, 1, 127, 1), TRIM)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 2), Vector2(125, 2), Vector2(112, 26), Vector2(0, 26)]), Color.BLACK)
	draw_line(Vector2(125.5, 2), Vector2(112.5, 26), TRIM)
	draw_rect(Rect2(0, 26, 113, 1), TRIM)
	draw_colored_polygon(PackedVector2Array([Vector2(7, 6), Vector2(15, 6), Vector2(12, 21), Vector2(4, 21)]), CURSOR)
	font.draw(self, Vector2(19, 6), t, HEX_TEXT, QoLFont.BIG)
	draw_rect(Rect2(16, 21, 90, 1), CURSOR)


func _cur(id: String) -> bool:
	return popup.is_empty() and cur_id() == id


func _draw_lan() -> void:
	_plate("LAN BATTLE")
	QoLKeyboard.hex(self, font, BACK_RECT, "BACK", _cur("back"), _flash.has("back"))
	QoLKeyboard.band(self, HOST_RECT.position.y - 8, HOST_RECT.size.y + 40)
	for k in 2:
		var id := "host" if k == 0 else "join"
		var r: Rect2 = HOST_RECT if k == 0 else JOIN_RECT
		QoLKeyboard.hex(self, font, r, "", _cur(id), _flash.has(id))
		font.draw_centered(self, r, id.to_upper(), Color8(255, 230, 64) if _cur(id) else HEX_TEXT, QoLFont.HEAVY, Color.BLACK)
		font.draw_centered(self, Rect2(r.position.x - 4, r.end.y + 6, r.size.x + 8, 10), "OPEN A ROOM" if k == 0 else "JOIN A ROOM", HEX_EDGE, QoLFont.BOLD)
		font.draw_centered(self, Rect2(r.position.x - 4, r.end.y + 19, r.size.x + 8, 10), "A FRIEND JOINS YOU" if k == 0 else "TYPE THE HOST'S IP", HEX_TEXT, QoLFont.REGULAR)
	font.draw(self, Vector2(8, 172), "B: BACK", HEX_TEXT, QoLFont.BOLD, Color.BLACK)


func _draw_connecting() -> void:
	_plate("JOIN ROOM")
	QoLKeyboard.band(self, 44, 84)
	font.draw_centered(self, Rect2(0, 52, 256, 12), "CONNECTING TO", HEX_EDGE, QoLFont.BOLD)
	font.draw_centered(self, Rect2(0, 70, 256, 14), address, HEX_TEXT, QoLFont.BIG)
	var left := _left()
	var dots := ".".repeat(1 + (_frames / 20) % 3)
	font.draw_centered(self, Rect2(0, 92, 256, 14), "%d%s" % [left, ""], YELLOW, QoLFont.HEAVY, Color.BLACK)
	font.draw_centered(self, Rect2(0, 110, 256, 10), "PLEASE WAIT" + dots, HEX_TEXT, QoLFont.REGULAR)
	QoLKeyboard.hex(self, font, CANCEL_RECT, "CANCEL", _cur("cancel"), _flash.has("cancel"))
	font.draw(self, Vector2(8, 172), "B: CANCEL", HEX_TEXT, QoLFont.BOLD, Color.BLACK)


func _draw_lobby() -> void:
	var l = _lan()
	_plate("LAN ROOM")
	QoLKeyboard.hex(self, font, BACK_RECT, "LEAVE", _cur("leave"), _flash.has("leave"))
	var host := role == "host"
	if host:
		var a := _addresses()
		var n := clampi(a.size(), 1, 3)
		QoLKeyboard.band(self, 36, 22 + n * 16)
		font.draw(self, Vector2(8, 41), "THIS PC (TELL YOUR FRIEND):", HEX_EDGE, QoLFont.BOLD)
		for i in n:
			var t := ("%s : %d" % [a[i], _port()]) if i < a.size() else "NO NETWORK FOUND"
			font.draw(self, Vector2(16, 57 + i * 16), t, HEX_TEXT, QoLFont.BIG)
		if not peer_in():                       # no button yet: the room waits
			QoLKeyboard.band(self, START_RECT.position.y, START_RECT.size.y)
			font.draw_centered(self, START_RECT, "WAITING FOR PLAYER" + ".".repeat(1 + (Engine.get_process_frames() / 30) % 3), YELLOW, QoLFont.BIG)
		else:
			var can := status != "ASKING" and status != "STARTING"
			var t2 := "CHARACTER SELECT"
			if status == "ASKING":
				t2 = "ASKING..."
			elif status == "STARTING":
				t2 = "STARTING..."
			QoLKeyboard.hex(self, font, START_RECT, t2, _cur("start") and can, _flash.has("start") or not can, HEX_TEXT, QoLFont.BOLD)
		font.draw(self, Vector2(8, 172), "START: GO   B: LEAVE" if peer_in() else "B: LEAVE", HEX_TEXT, QoLFont.BOLD, Color.BLACK)
	else:
		QoLKeyboard.band(self, 36, 38)
		font.draw(self, Vector2(8, 41), "IN THE ROOM OF:", HEX_EDGE, QoLFont.BOLD)
		font.draw(self, Vector2(16, 57), "%s  (%s)" % [str(l.peer_name).to_upper() if l != null else "?", address], HEX_TEXT, QoLFont.BOLD)
		QoLKeyboard.band(self, 112, 30)
		var t3 := "STARTING..." if status == "STARTING" else ("YOU SAID NO - WAITING" if status == "DECLINED" else "WAITING FOR THE HOST")
		font.draw_centered(self, Rect2(0, 113, 256, 30), t3, YELLOW, QoLFont.BIG)
		font.draw(self, Vector2(8, 172), "B: LEAVE", HEX_TEXT, QoLFont.BOLD, Color.BLACK)


func _draw_popup() -> void:
	if popup.is_empty() or page == "":
		return
	var o := overlay
	o.draw_rect(Rect2(0, 28, 256, 164), Color(0, 0, 0, 0.6))
	var y := POPUP_Y
	var h := _popup_h()
	QoLKeyboard.band(o, y, h)
	var warn: bool = popup["kind"] == "warn"
	font.draw_centered(o, Rect2(0, y + 8, 256, 13), popup["title"], HEX_RED if warn else HEX_TEXT, QoLFont.BIG)
	var lines: Array = popup["lines"]
	for i in lines.size():
		var big: bool = popup["kind"] == "sure" and role == "host"
		font.draw_centered(o, Rect2(0, y + 30 + i * 12, 256, 10), lines[i], HEX_TEXT if big else HEX_EDGE, QoLFont.BOLD if big else QoLFont.REGULAR)
	var rs := _popup_rects()
	var bs: Array = popup["buttons"]
	for i in bs.size():
		QoLKeyboard.hex(o, font, rs[i], bs[i][1], popup["col"] == i, _flash.has(bs[i][0]))


## the upper screen: the VS BATTLE frame's title bar and its message box (the lobby: names, ping, status)
func _draw_top() -> void:
	if page == "":
		return
	var title := focus_title()
	top.draw_rect(Rect2(0, 25, 199, 16), TITLE_BAR)
	font.draw(top, Vector2(43, 28), title, Color.BLACK, QoLFont.HEAVY)
	for y in range(int(BOX.position.y), int(BOX.end.y)):
		top.draw_rect(Rect2(BOX.position.x, y, BOX.size.x, 1), BOX_STRIPES[y % 3])
	if page == "lobby" and (popup.is_empty() or popup.get("desc", "") == ""):
		_draw_top_lobby()
		return
	var lines := focus_desc().split("\n")
	var y0 := 66 if lines.size() >= 6 else 70
	for i in mini(lines.size(), 6):
		font.draw(top, Vector2(22, y0 + i * 13), lines[i], TEXT)


## lobby: HOST (red) and GUEST (blue) plates with the names, YOU marked; ping; the room's status
func _draw_top_lobby() -> void:
	var l = _lan()
	var me := str(l.my_name).to_upper() if l != null else ""
	var other := str(l.peer_name).to_upper() if l != null else ""
	var host := role == "host"
	var names := [me if host else other, other if host else me]
	for k in 2:
		var y := 64 + k * 21
		var x := 16
		top.draw_colored_polygon(PackedVector2Array([Vector2(x + 5, y), Vector2(x + 54, y), Vector2(x + 49, y + 16), Vector2(x, y + 16)]), PCOL[k])
		font.draw_centered(top, Rect2(x + 2, y + 3, 50, 10), "HOST" if k == 0 else "GUEST", HEX_TEXT, QoLFont.BOLD)
		var nm: String = names[k]
		var connected := k == 0 or peer_in() or not host
		if nm == "" or not connected:
			font.draw(top, Vector2(x + 62, y + 3), "- - -", Color8(200, 190, 170), QoLFont.BOLD)
		else:
			font.draw(top, Vector2(x + 62, y + 3), nm, HEX_TEXT, QoLFont.BOLD, Color.BLACK)
		if (k == 0) == host:
			font.draw(top, Vector2(204, y + 4), "YOU", YELLOW, QoLFont.BOLD, Color.BLACK)
	var ping: int = int(l.ping_ms) if l != null and peer_in() else -1
	var pc := TEXT
	if ping >= 80:
		pc = Color8(255, 80, 60)
	elif ping >= 30:
		pc = YELLOW
	var st := ""
	var st2 := ""
	if lan_state() == "IDLE":
		st = "NOT CONNECTED"
	elif status == "STARTING":
		st = "GOING TO THE CHARACTER SELECT"
	elif host and not peer_in():
		st = "WAITING FOR PLAYER"
		var a := _addresses()
		st2 = "This PC: %s  port %d" % [a[0] if not a.is_empty() else "-", _port()]
	elif status == "ASKING":
		st = "ASKING %s..." % other
		st2 = "Waiting for ACCEPT / DENY."
	elif status == "DECLINED":
		st = "DECLINED"
		st2 = "START: ask again." if host else "Waiting for the host to ask again."
	else:
		st = "CONNECTED"
		st2 = "START: go to the character select." if host else "Waiting for %s to start." % (other if other != "" else "the host")
	font.draw(top, Vector2(22, 109), "PING  " + ("%d ms" % ping if ping >= 0 else "--"), pc, QoLFont.BOLD)
	font.draw(top, Vector2(22, 122), st, YELLOW, QoLFont.BOLD)
	if st2 != "":
		font.draw(top, Vector2(22, 135), st2, TEXT)
