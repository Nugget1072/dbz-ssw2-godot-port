class_name QoLKeyboard
extends Control
# ---- LAN MENU (part 30)
## On-screen keyboard of the LAN pages (docs/LAN_DESIGN.md 6; QoLLanMenu owns it and routes every input to it):
## one or two text boxes (DISPLAY NAME, the host's IP[:PORT]) over a 10x4 grid of keys A-Z 0-9 . : - _ and a row
## SPACE | DEL | OK, drawn in the settings menu's style (black bands with orange trim, Option-screen hexagons, the
## game's font). Keys are pressed by D-pad + A, taps (mouse / gamepad cursor) or typed on a real keyboard
## (QoLLanMenu.key_event). Lower-screen coordinates (the control sits at the lower screen's origin).

const TRIM := QoLMenu.TRIM
const HEX_EDGE := QoLMenu.HEX_EDGE
const HEX_FILL := QoLMenu.HEX_FILL
const HEX_TEXT := QoLMenu.HEX_TEXT
const CURSOR := QoLMenu.CURSOR
const DIM := Color8(120, 104, 80)
const KEYS := ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ0123", "456789.:-_"]
const KEY_X := 3
const KEY_W := 24
const KEY_PITCH := 25
const KEY_H := 22
const KEY_Y := 78                        ## first key row; rows every 23 px, SPACE / DEL / OK below the 4 letter rows
const ROW_PITCH := 23
const FIELD_Y := [31, 54]                ## the two boxes' bands
const FIELD_BOX := Rect2(58, 0, 194, 20) ## x / width / height of a box (y from FIELD_Y)
const NAME_MAX := 10                     ## fits the HOST / GUEST plates on the upper screen
const IP_MAX := 21                       ## "255.255.255.255:65535"
const IP_CHARS := "0123456789.:"
const NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-_ "

var font: QoLFont
## the boxes: [{label, text, max, ip}], `active` = the one typed into
var fields: Array = []
var active := 0
var info := ""                           ## a read-only second line (HOST page: this PC's address) when one box
var info_label := ""
var cursor_id := ""                      ## the id under the menu cursor ("" = none: a popup is open)
var flash := {}
var blink := 0                           ## game frames (caret blink)


func _init() -> void:
	position = Vector2.ZERO
	size = Vector2(256, 192)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(f: Array, act: int = 0) -> void:
	fields = f
	active = act
	queue_redraw()


func text(i: int) -> String:
	return fields[i]["text"] if i < fields.size() else ""


## the characters the active box takes (the IP box: digits, dot, colon)
func allowed(ch: String) -> bool:
	if fields.is_empty():
		return false
	var cs := IP_CHARS if fields[active]["ip"] else NAME_CHARS
	return ch.length() == 1 and cs.contains(ch)


## one character into the active box: false when it does not fit / is not allowed there
func type(ch: String) -> bool:
	ch = ch.to_upper()
	if not allowed(ch):
		return false
	var f: Dictionary = fields[active]
	if f["text"].length() >= f["max"]:
		return false
	if ch == " " and (f["text"] == "" or f["text"].ends_with(" ")):   # no leading / double spaces in names
		return false
	f["text"] += ch
	blink = 0
	queue_redraw()
	return true


func backspace() -> bool:
	var f: Dictionary = fields[active]
	if f["text"] == "":
		return false
	f["text"] = f["text"].left(-1)
	blink = 0
	queue_redraw()
	return true


func next_field() -> void:
	if fields.size() > 1:
		active = (active + 1) % fields.size()
		blink = 0
		queue_redraw()


## the buttons by row for the menu's cursor: boxes, 4 rows of 10 keys, SPACE / DEL / OK
func rows() -> Array:
	var r := []
	for i in fields.size():
		r.append([{"id": "field:%d" % i, "rect": field_rect(i)}])
	for k in KEYS.size():
		var row := []
		for c in 10:
			row.append({"id": "key:" + KEYS[k][c], "rect": Rect2(KEY_X + c * KEY_PITCH, KEY_Y + k * ROW_PITCH, KEY_W, KEY_H)})
		r.append(row)
	var y := KEY_Y + KEYS.size() * ROW_PITCH
	r.append([{"id": "space", "rect": Rect2(3, y, 96, KEY_H)}, {"id": "del", "rect": Rect2(104, y, 70, KEY_H)},
		{"id": "ok", "rect": Rect2(179, y, 74, KEY_H)}])
	return r


func field_rect(i: int) -> Rect2:
	return Rect2(FIELD_BOX.position.x, FIELD_Y[i], FIELD_BOX.size.x, FIELD_BOX.size.y)


# ------------------------------------------------------------------------------------------------ drawing helpers
## shared with QoLLanMenu: an Option-screen hexagon (orange rim, white = cursor, black line, brown face)
static func hex_points(r: Rect2, inset: float) -> PackedVector2Array:
	var s := r.size.y * 0.32
	var x0 := r.position.x + inset
	var x1 := r.end.x - inset
	var y0 := r.position.y + inset
	var y1 := r.end.y - inset
	var ym := r.position.y + r.size.y / 2.0
	var si := s - inset * 0.4
	return PackedVector2Array([Vector2(x0 + si, y0), Vector2(x1 - si, y0), Vector2(x1, ym), Vector2(x1 - si, y1), Vector2(x0 + si, y1), Vector2(x0, ym)])


static func hex(ci: CanvasItem, fnt: QoLFont, r: Rect2, t: String, cur: bool, fl: bool, col: Color = HEX_TEXT, style: int = -1) -> void:
	ci.draw_colored_polygon(hex_points(r, 0), CURSOR if cur else HEX_EDGE)
	ci.draw_colored_polygon(hex_points(r, 2), Color.BLACK)
	ci.draw_colored_polygon(hex_points(r, 3), HEX_EDGE if fl else HEX_FILL)
	if t != "":
		var st := style
		if st < 0:
			st = QoLFont.BOLD if fnt.width(t, QoLFont.BOLD) <= r.size.x - 10 else QoLFont.REGULAR
		fnt.draw_centered(ci, r, t, col, st, Color.BLACK if st == QoLFont.HEAVY else Color(0, 0, 0, 0))


static func band(ci: CanvasItem, y: float, h: float) -> void:
	ci.draw_rect(Rect2(0, y - 1, 256, 1), TRIM)
	ci.draw_rect(Rect2(0, y, 256, h), Color.BLACK)
	ci.draw_rect(Rect2(0, y + h, 256, 1), TRIM)


func _draw() -> void:
	if fields.is_empty():
		return
	for i in 2:                      # the box bands (the HOST page's second one: this PC's address, read only)
		var y: int = FIELD_Y[i]
		if i >= fields.size() and info == "":
			continue
		band(self, y + 1, 18)
		if i < fields.size():
			var f: Dictionary = fields[i]
			var on := i == active
			font.draw(self, Vector2(5, y + 4), f["label"], HEX_EDGE if on else HEX_TEXT, QoLFont.BIG)
			_box(field_rect(i), f, on, cursor_id == "field:%d" % i)
		else:
			font.draw(self, Vector2(5, y + 4), info_label, HEX_TEXT, QoLFont.BIG)
			font.draw(self, Vector2(FIELD_BOX.position.x + 7, y + 6), info, HEX_EDGE, QoLFont.BOLD)
	band(self, KEY_Y - 3, 192 - KEY_Y + 3)
	var ip: bool = fields[active]["ip"]
	for row in rows():
		for b in row:
			var id: String = b["id"]
			if id.begins_with("field:"):
				continue
			var t: String = id.substr(4) if id.begins_with("key:") else id.to_upper()
			var usable := true
			if id.begins_with("key:"):
				usable = allowed(t)
			elif id == "space":
				usable = not ip
			# keys in the game's heavy title capitals (": _" are not in it: bold)
			var st := QoLFont.HEAVY if id.begins_with("key:") and not t in [":", "_"] else -1
			hex(self, font, b["rect"], t, cursor_id == id, flash.has(id), HEX_TEXT if usable else DIM, st)


## a text box: a long hexagon with a black face, the text left-aligned and a blinking caret in the active box
func _box(r: Rect2, f: Dictionary, on: bool, cur: bool) -> void:
	draw_colored_polygon(hex_points(r, 0), CURSOR if cur else (HEX_EDGE if on else TRIM))
	draw_colored_polygon(hex_points(r, 2), Color.BLACK)
	var st := QoLFont.BOLD               # upright: 1 / I, O / 0 told apart
	var t: String = f["text"]
	var x := r.position.x + 9
	var y := r.position.y + floorf((r.size.y - QoLFont.CAP[st]) / 2.0)
	if t == "" and not on:
		font.draw(self, Vector2(x, y), f.get("hint", ""), DIM, QoLFont.REGULAR)
	else:
		font.draw(self, Vector2(x, y), t, HEX_TEXT, st)
	if on and (blink / 30) % 2 == 0:
		var cx := x + (font.width(t, st) + 2 if t != "" else 0)
		draw_rect(Rect2(cx, r.position.y + 4, 2, r.size.y - 8), CURSOR)
	if not f["ip"]:                      # letters left (the IP box is long enough without)
		var cnt := "%d/%d" % [t.length(), f["max"]]
		font.draw(self, Vector2(r.end.x - 11 - font.width(cnt), r.position.y + 6), cnt, DIM, QoLFont.REGULAR)
