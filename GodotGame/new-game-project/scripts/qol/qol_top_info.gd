class_name QoLTopInfo
extends Control
## Top screen while Mode Select's cursor is on the Dragon Ball tile or the settings menu is open. The game has no
## title / description for that tile, so the port writes its own into the game's header bar and description box,
## the way the game's Option screen does: the header names the option under the cursor and the box explains it.
## Measured on the game's screens (DATA_NOTES part 12): the orange header bar's text area is y 25..40 between
## two black lines (y 24 and 41), title text black bold, capitals y 28..37 from x 32; the description box is
## x 12..243, y 61..147 (brown stripes) with white text from x 26, lines every 14 px from y 77.

const ORANGE := Color8(235, 150, 0)
const STRIPES := [Color8(121, 89, 52), Color8(113, 81, 44), Color8(105, 81, 36)]   ## box rows, y % 3 from y = 60
const TEXT := Color8(235, 235, 235)
## part 34: the same header / box on a screen shown at full brightness (Maximum's COURSE SELECT upper screen, used by
## the NEW GAMEMODES Gamemode menu): colours measured there (as34/max2 p3300), stripes y % 3 from y = 60
const ORANGE_FULL := Color8(251, 162, 0)
const STRIPES_FULL := [Color8(130, 97, 56), Color8(113, 89, 40), Color8(121, 89, 48)]
const TEXT_FULL := Color8(251, 251, 251)

var full := false                    ## part 34: use the *_FULL colours

var font: QoLFont
var title := "SETTINGS"
var desc := "Change the game's settings."


func _init() -> void:
	position = Vector2.ZERO
	size = Vector2(256, 192)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func show_text(t: String, d: String) -> void:
	if t != title or d != desc:
		title = t
		desc = d
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 25, 190, 16), ORANGE_FULL if full else ORANGE)   # the previous tile's title, between the bar's lines
	font.draw(self, Vector2(31, 28), title, Color.BLACK, QoLFont.HEAVY)
	for y in range(61, 148):
		draw_rect(Rect2(12, y, 232, 1), (STRIPES_FULL if full else STRIPES)[(y - 60) % 3])
	var text_col := TEXT_FULL if full else TEXT
	var lines := desc.split("\n")
	if desc.contains("\t"):   # a table (BOSS LIST): columns of 76 px, up to 6 lines from y 66
		for i in mini(lines.size(), 6):
			var cols := lines[i].split("\t")
			for k in cols.size():
				font.draw(self, Vector2(18 + k * 74, 64 + i * 13), cols[k], text_col)
		return
	for i in mini(lines.size(), 5):
		font.draw(self, Vector2(26, 77 + i * 14), lines[i], text_col)
