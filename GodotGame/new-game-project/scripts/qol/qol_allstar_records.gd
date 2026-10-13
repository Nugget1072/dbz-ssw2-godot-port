class_name QoLAllStarRecords
extends Node2D
# ---- ALLSTAR RECORDS (part 34; page redesigned in part 35)
## ALL-STAR phase 4 (docs/ALLSTAR_DESIGN.md 1.10 / 2a; DATA_NOTES "part 34 findings (All-Star records)" and "part 35
## findings (All-Star records redesign)"): after a won All-Star battle the port shows its own records page over both
## screens, laid out like the game's Z-Battle results scene 10 and built only from that scene's own art, read from the
## player's ROM when the page first opens (nothing from the ROM is stored):
## - UPPER screen = the results' score panel (`result.bin` e_res_bg: three portrait frames, the yellow table, the
##   "WINNER" banner) over the scrolling hexagons (`scene/common/common_bg.bin` cstat_bg): the team's portraits
##   (`scene/common/CharFace256.bin`, empty slots = the game's nul1 panel) in the frames; the table re-titled "ALL-STAR"
##   (the tab's own white letters) with Enemies / Hearts Used / Rank / Best rows and a status row, all lettered with
##   glyphs cut from the game's own pre-lettered labels (all five languages of e_res_bg) and the numbers in the
##   table's own digit strip (yellow cells; the Total bar's orange cells); the Total bar = "TIME" + this run's time.
## - LOWER screen = the HI-SCORE RANKING (e_hi_score re-lettered "ALL-STAR RECORDS" with the plate's own italic capitals
##   taken from the five language versions of the plate; rows base1st..base5st 28 px apart instead of 32 so the
##   results' "Character Select" plate fits below): per row the clear time in the ranking's digits no0..no9 (+ a colon
##   drawn in their style), the team's face icons (game_faceicon.arc) and the hearts used in the difficulty word's
##   slot ("NO HEARTS" .. "3 HEARTS" in the e_easy / e_noaml / e_hard lettering); the new entry's row flashes lighter.
##   OK = the "Character Select" plate (e_charasele, rows 2-7 left out) with the results' cursor (cursol: white frame +
##   triangle) blinking on it; A / START / B, a tap or a gamepad-cursor click on it closes the page.
## - The page fades in from black, out to black, then the All-Star select (loaded behind the page meanwhile) is revealed.
## - File `allstar_records.cfg` next to the exe (editor: user://; `asrec=PATH`; captures without `asrec=` keep it in
##   memory only): [records] r1..r5 = {"frames", "ids", "hearts", "date"}, sorted by frames, then hearts, then date
##   (an equal time ranks below the older entry, as the game's own insert FUN_02002560). Damaged / hand-edited files
##   load what is valid (a file that does not parse is kept as .bak when the next record is written). Nothing is written
##   while cheats are on (as the game's ranking, QoLGame `# ---- LEADERBOARD`), nor for a debug run that did not fight
##   the whole roster (`asstart=` / `asorder=`). The game's save is never touched.
## Opened by QoLAllStar.records_req (QoLGame `# ---- ALLSTAR RECORDS`: the won battle asks for scene 10, rerouted to
## the All-Star select); runs on the main thread (QoLController.after_step / filter_input).
## Part 38 ENDLESS RECORDS (`endless`, set at open from QoLAllStar.endless): the same page after an ENDLESS battle was
## lost (Game Over, scene 0x14, rerouted to the select): tab "ENDLESS" (its D put together from the tab font's O and L),
## the "WINNER" banner re-lettered "GAME OVER" in the banner's own typeface (letters cut from the five languages'
## WINNER words, M put together from N's stem + V; `_banner_word`), table Enemies n / Hearts Used / Rank / Best (most
## enemies) / status, Total bar = the time; ranking "ENDLESS RECORDS" with per row the enemies beaten + "KO" in the
## ranking digits' own drawing and the time in the difficulty word's slot. All numbers on both pages are set from the
## digits' ink 1 px apart (`_packed`), the ranking titles are spaced by their outlines (GFont.contour), and the
## "Character Select" label has 3 px room before the plate's inner frame (`_label_room`). File `endless_records.cfg` (`esrec=PATH`), [records] r1..r5 = {"beaten",
## "frames", "ids", "hearts", "date"}, sorted by most enemies, then shorter time, fewer hearts, older entry; a run that
## beat nobody is not ranked; nothing is written while cheats are on.

const FILE := "allstar_records.cfg"
const FILE_ENDLESS := "endless_records.cfg"  ## part 38
const BEATEN_MAX := 99999                    ## part 38: ENDLESS enemies beaten (file check / display)
const MAX := 5
const FPS := 59.8261
const CAP_S := 5999                          ## 99:59
const FADE := 16                             ## frames per fade step (in, out, reveal)
## lower screen: the game's ranking layout (title plate at y 1, rows at 28 + 32 * i) moved up 3 px and the rows set
## 28 px apart (their 2-px borders overlap) so the OK plate fits under the 5th row
const TITLE_Y := -2
const ROW_Y0 := 22
const ROW_STEP := 28
const DIG_RIGHT := 122                       ## the game's score digits end at x 122 (row + 8)
const FACE_X := [128, 152, 176]              ## the game's face icons (24 x 24, row + 4)
const WORD_RIGHT := 252                      ## the difficulty word's slot: x 202..251 (after the 3rd face, 2 px off the
const WORD_W := 50                           ## row's right border), word rows row + 12..26, underline row + 27
const BTN_Y := 166                           ## the OK plate (e_charasele rows 0-1 + 8-31 = 26 rows)
const BTN_ROWS := [0, 1, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
const OK_RECT := Rect2i(0, 164, 256, 28)     ## touch coordinates (lower screen)
## upper screen: e_res_bg as the game shows it (BG1, no scroll); portraits (BG0) at y 14 + 40 k; table lines 16 apart
const PORTRAIT_Y := 14
const LINE_Y0 := 26                          ## table text band of line k: 26 + 16 k (13 rows); digit cells at 24 + 16 k
const LABEL_X := 88
const VALUE_RIGHT := 248
## the hexagons (BG2 of both screens): HOFS / VOFS 35 / 477 at f5320 of as34/rank3, +10 / +22 every 20 frames
const HEX_ORIGIN := Vector2(35, 477)
const HEX_SPEED := Vector2(0.5, 1.1)
## palette index -> strength of a glyph pixel (0 = background): black letters on the yellow table / word plates,
## white letters on black (the table's tab, the Total bar, the ranking's title plate)
const RANK_DARK := [0, 8, 7, 6, 5, 4, 3, 2, 0, 1, 0, 0, 0, 0, 0, 0]
const RANK_WHITE := [0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2, 4, 3, 5, 6]
## e_res_bg's own labels (language prefix, line or area, text, "dark" palette indices that make up the strokes): the
## glyphs are cut from these (first source of a character wins; a line whose strokes do not split into exactly its
## characters is skipped)
const TABLE_SRC := [["e", 0, "Battle Points", [1, 2, 3]], ["e", 1, "Time Bonus", [1, 2, 3]], ["e", 2, "Perfect", [1, 2, 3]],
	["e", 3, "Straight", [1, 2, 3]], ["e", 4, "Rank Bonus", [1, 2, 3]], ["g", 1, "ZEITBONUS", [1, 2, 3]],
	["g", 2, "PERFEKT", [1, 2, 3]], ["g", 3, "DIREKT", [1, 2, 3]], ["g", 4, "RANGBONUS", [1, 2, 3]],
	["i", 1, "BONUS TEMPO", [1, 2, 3]], ["s", 1, "BONIF. TIEMPO", [1, 2, 3]], ["s", 3, "DIRECTO", [1, 2, 3]],
	["s", 4, "BONIF. RANGO", [1, 2, 3]], ["f", 0, "POINTS COMBAT", [1, 2]], ["f", 1, "TEMPS BONUS", [1, 2]],
	["f", 4, "BONUS NIVEAU", [1, 2]], ["s", 0, "PTOS. BATALLA", [1, 2]]]
## white letters: [prefix, band top, x0, x1, text, dark]
const WHITE_SRC := [["e", 10, 140, 252, "SCORE", [12, 14, 15]], ["e", 111, 86, 174, "Total", [14, 15]],
	["f", 111, 86, 174, "TOTAL", [14, 15]], ["g", 10, 140, 252, "PUNKTE", [14, 15]], ["g", 111, 86, 174, "GESAMT", [14, 15]],
	["i", 10, 140, 252, "PUNTEGGIO", [14, 15]], ["i", 111, 86, 174, "TOTALE", [14, 15]], ["s", 10, 140, 252, "PUNTUACIÓN", [14, 15]]]
## the ranking title plates (italic capitals): [prefix, text]
const PLATE_SRC := [["e", "HI-SCORE RANKING"], ["f", "CLASSEMENT"], ["s", "RÉCORDS"], ["g", "HIGHSCORE-RANG"], ["i", "CLASSIFICA"]]
## part 38: the WINNER band of each language's e_res_bg (same heavy typeface): [prefix, word, leading letters to take
## when the word's letters touch (0 = all)]; the first source of a letter wins. VINCITORE's letters touch everywhere.
const BANNER_SRC := [["e", "WINNER", 0], ["s", "GANADOR", 0], ["g", "SIEGER", 0], ["f", "VAINQUEUR", 1]]
const BANNER_TEXT := "GAME OVER"
const PLATE_GAP := 1                         ## part 38: ranking title: columns between two letters' nearest strokes
const PLATE_SPACE := 5                       ## and extra columns for a space
const BANNER_W := 244                        ## the word's widest extent (the band is 256 wide)
## part 38: "KO" after the ENDLESS ranking's enemy count, in the ranking digits' own drawing (8 rows, core 1 + the
## digits' shades; O = the digit 0)
const KO_K := ["61...41", "61..417", "61.417.", "61417..", "6114...", "61.41..", "61..417", "74...74"]
## the difficulty words (64 x 16, word rows 0-14, underline row 15)
const WORD_SRC := [["f_noaml", "NORMAL"], ["g_easy", "LEICHT"], ["g_hard", "SCHWER"], ["f_easy", "FACILE"],
	["e_easy", "Easy"], ["e_noaml", "Normal"], ["e_hard", "Hard"], ["f_hard", "DIFFICILE"]]
## CharFace256.bin portrait per character id (= the select's member order)
const FACE_NAMES := ["gkn", "gks", "ghk", "gho", "crr", "pic", "vgn", "vgs", "trk", "gtk", "frz", "frm", "gnu", "drg",
	"egh", "cel", "bmr", "bmj", "col", "com", "brl", "vga", "trn", "gtn", "ghn", "cey", "tsh", "dnd", "stn", "1617",
	"bvd", "cej", "zbdd", "bdk", "dbr", "srn", "neko"]
const ORD := ["st", "nd", "rd", "th", "th"]
const HEART_WORDS := [["NO HEARTS", "0 HEARTS", "NONE"], ["1 HEART"], ["2 HEARTS"], ["3 HEARTS"]]
## the white italic title of a plate: 15 rows, slant 1 px per 4 rows, coverage -> 5 shades (see retitle(), also used by
## QoLAllStarMenu for the Gamemode menu's header)
const IT_ROWS := 15
const IT_SLANT := 0.25
const WHITE := Color8(248, 248, 248)
const YELLOW := Color8(255, 205, 0)

var qol                                      ## QoLController
var allstar: QoLAllStar
var font: QoLFont
var rom := PackedByteArray()
var shown := false
var dbg := false
var table: Array = []                        ## the records (best first), as on screen
var entry := {}                              ## this run
var new_rank := -1                           ## 0..4 = this run's row in `table`, -1 = not entered
var note := ""                               ## "" saved / "cheats" / "partial" / "out" (not in the top 5) / "nofile" (write failed)
var saved := false
var endless := false                         ## part 38: this page is the ENDLESS RECORDS page
var _ok := false                             ## ROM art found
var _built := false
var _task := -1                              ## WorkerThreadPool task building the art (started with the session)
var _tex_done := false
var _rows: Array = []                        ## base1st..base5st textures, + flash versions
var _rows_hi: Array = []
var _row_info: Array = []                    ## per row: content texture (time + hearts word) or null
var _plate_top                               ## the ranking's title plate, re-lettered (Image until _textures())
var _plate_top_e                             ## part 38: the same plate lettered "ENDLESS RECORDS"
var _button                                  ## OK plate (compact e_charasele)
var _cursor                                  ## the results' cursor (compact cursol)
var _faces := {}                             ## id -> 24 x 24 texture
var _hex                                     ## 64 x 64 hexagon tile
var _upper: Texture2D                        ## the results panel with this run's table (built at open)
var _portraits: Array = []                   ## 3 textures for the frames (built at open)
var _phase := 0                              ## 0 fade in, 1 shown (input), 2 fade out, 3 reveal the game
var _t := 0
var _ht := 0                                 ## frames since the page opened (hexagon scroll)
var _press := false
var _demo_at := -1
# ROM art kept between pages (index canvases + palettes; built on the first open)
var _pal16: Array = []                       ## result.bin palette (e_res_bg / rows / digits / words)
var _res: Canvas                             ## e_res_bg, 256 x 256 indices
var _no: Array = []                          ## no0..no9 (8 x 16 index canvases)
var _tfont: GFont                            ## the table's black letters
var _wfont: GFont                            ## the tab's / Total bar's white letters
var _rfont: GFont                            ## the difficulty words' letters (+ the ranking digits)
var _pfont: GFont                            ## the ranking title plate's italic capitals
var _bfont: GFont                            ## part 38: the WINNER banner's capitals (ENDLESS: "GAME OVER")
var _ydig: Array = []                        ## part 38: digit ink [Canvas, top row] of the table's yellow cells,
var _odig: Array = []                        ## the Total bar's orange cells
var _ndig: Array = []                        ## and the ranking's no0..no9
var _face_pal: Array = []                    ## CharFace256 256-colour palette
var _face_px := {}                           ## id -> 80 x 40 index canvas (-1 = empty slot)


## an image as palette indices (0 = transparent)
class Canvas:
	var w := 0
	var h := 0
	var px := PackedByteArray()

	func _init(w_: int = 0, h_: int = 0, v: int = 0) -> void:
		w = w_
		h = h_
		px.resize(w * h)
		if v != 0:
			px.fill(v)

	func g(x: int, y: int) -> int:
		return px[y * w + x] if x >= 0 and y >= 0 and x < w and y < h else 0

	func s(x: int, y: int, v: int) -> void:
		if x >= 0 and y >= 0 and x < w and y < h:
			px[y * w + x] = v

	func copy() -> Canvas:
		var c := Canvas.new(w, h)
		c.px = px.duplicate()
		return c

	func crop(x0: int, y0: int, cw: int, ch: int) -> Canvas:
		var c := Canvas.new(cw, ch)
		for y in ch:
			for x in cw:
				c.px[y * cw + x] = g(x0 + x, y0 + y)
		return c

	## a canvas of the listed rows
	func rows(list: Array) -> Canvas:
		var c := Canvas.new(w, list.size())
		for i in list.size():
			for x in w:
				c.px[i * w + x] = g(x, list[i])
		return c

	## src over this canvas: with a rank table the stronger pixel wins (rank 0 = not drawn), else every pixel but
	## 0 and `skip`
	func blit(src: Canvas, x0: int, y0: int, rank: Array = [], skip: int = -1) -> void:
		for y in src.h:
			for x in src.w:
				var v := src.px[y * src.w + x]
				if v == 0 or v == skip:
					continue
				if not rank.is_empty():
					if rank[v] == 0 or rank[v] <= rank[g(x0 + x, y0 + y)]:
						continue
				s(x0 + x, y0 + y, v)

	func image(pal: Array) -> Image:
		var img := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var v := px[y * w + x]
				if v != 0 and v < pal.size():
					img.set_pixel(x, y, pal[v])
		return img


## letters cut from the game's own pre-lettered art: char -> [Canvas, dy, lx, rx] (dy = glyph top relative to the
## line's reference row; lx..rx = the columns that count for the spacing: the whole box, or for the italic plate
## capitals their strokes in the middle rows), spaced by the median gaps measured in the source lines
class GFont:
	var glyphs := {}
	var rank: Array = []
	var gap := 0
	var space := 4
	var gaps: Array = []
	var spaces: Array = []

	func _init(r: Array) -> void:
		rank = r

	func has(c: String) -> bool:
		return glyphs.has(c)

	func add(c: String, cv: Canvas, dy: int, lx: int = 0, rx: int = -1) -> void:
		if not glyphs.has(c) and cv != null and cv.w > 0:
			glyphs[c] = [cv, dy, lx, rx if rx >= 0 else cv.w - 1]

	func finish(def_gap: int, def_space: int) -> void:
		gap = _median(gaps, def_gap)
		space = _median(spaces, def_space)

	static func _median(a: Array, d: int) -> int:
		if a.is_empty():
			return d
		var b := a.duplicate()
		b.sort()
		return b[b.size() / 2]

	func _adv(c: String) -> int:
		return int(glyphs[c][3]) - int(glyphs[c][2]) + 1 if glyphs.has(c) else 4

	## part 38 `contour`: letters spaced by their outlines (in every row, +-1 row for the slant, the nearest strokes of
	## two neighbours are `gap` px apart) instead of by fixed columns: the italic plate capitals' S / R / C stood too
	## far from or too close to their neighbours ("ENDLES S")
	var contour := false
	var _prof := {}

	func _profile(c: String) -> Dictionary:
		if not _prof.has(c):
			var cv: Canvas = glyphs[c][0]
			var dy := int(glyphs[c][1])
			var p := {}
			for y in cv.h:
				var l := -1
				var r := -1
				for x in cv.w:
					if rank[cv.g(x, y)] >= 3:
						if l < 0:
							l = x
						r = x
				if l >= 0:
					p[dy + y] = Vector2i(l, r)
			_prof[c] = p
		return _prof[c]

	## canvas-left of b minus canvas-left of a when their closest strokes touch (+1 = one empty column between)
	func _pair(a: String, b: String) -> int:
		var pa := _profile(a)
		var pb := _profile(b)
		var best := -99999
		for row in pa:
			for dr in [-1, 0, 1]:
				if pb.has(row + dr):
					best = maxi(best, (pa[row] as Vector2i).y - (pb[row + dr] as Vector2i).x + 1)
		if best == -99999:
			best = int(glyphs[a][3]) + 1 - int(glyphs[b][2])
		return best

	## [[char, canvas-left], ...] and the end x of `t` drawn with its first stroke at x
	func _layout(t: String, x: int, extra: int) -> Array:
		var out: Array = []
		var prev := ""
		var left := 0
		var sp := 0
		for c in t:
			if c == " ":
				sp += space
				continue
			if not glyphs.has(c):
				continue
			if prev == "":
				left = x - int(glyphs[c][2])
			else:
				left += _pair(prev, c) + gap + extra + sp
			out.append([c, left])
			prev = c
			sp = 0
		var end := x if prev == "" else left + int(glyphs[prev][3]) + 1
		return [out, end]

	func width(t: String, extra := 0) -> int:
		if contour:
			return int(_layout(t, 0, extra)[1])
		var x := 0
		var any := false
		for c in t:
			if c == " ":
				x += space - gap - extra
				continue
			x += _adv(c) + gap + extra
			any = true
		return x - gap - extra if any else 0

	func missing(t: String) -> String:
		var m := ""
		for c in t:
			if c != " " and not glyphs.has(c) and m.find(c) < 0:
				m += c
		return m

	## draws `t` from x (y = the line's reference row); returns the end x
	func draw(cv: Canvas, x: int, y: int, t: String, extra := 0) -> int:
		if contour:
			var lay := _layout(t, x, extra)
			for p in lay[0]:
				cv.blit(glyphs[p[0]][0], int(p[1]), y + int(glyphs[p[0]][1]), rank)
			return int(lay[1])
		for c in t:
			if c == " ":
				x += space - gap - extra
				continue
			if glyphs.has(c):
				cv.blit(glyphs[c][0], x - int(glyphs[c][2]), y + int(glyphs[c][1]), rank)
			x += _adv(c) + gap + extra
		return x


func _init() -> void:
	z_index = 900                            # over every port panel; the gamepad cursor (1000) stays on top
	visible = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # the hexagon tile scrolls


func setup(q, r: PackedByteArray) -> void:
	qol = q
	allstar = q.allstar
	font = q.font
	rom = r
	dbg = Game.args.has("asdbg")
	if Game.args.has("asrecdemo"):
		_demo_at = int(Game.flag("asrecdemo"))
	elif Game.args.has("esrecdemo"):
		_demo_at = int(Game.flag("esrecdemo"))


## the art is cut from the ROM in a worker thread as soon as an All-Star session is running (nothing otherwise; a
## page opened without a session, `asrecdemo=`, builds it at once) and turned into textures when the page opens
func _ensure_art() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if not _built:
		_built = true
		_load_art()
	if not _tex_done:
		_tex_done = true
		_textures()


func _start_art() -> void:
	if _built or _task >= 0:
		return
	_built = true
	_task = WorkerThreadPool.add_task(_load_art, false, "ALL-STAR records art")


## Images made by _load_art (any thread) -> textures (main thread)
func _textures() -> void:
	for a in [_rows, _rows_hi]:
		for i in a.size():
			if a[i] is Image:
				a[i] = ImageTexture.create_from_image(a[i])
	for k in _faces:
		if _faces[k] is Image:
			_faces[k] = ImageTexture.create_from_image(_faces[k])
	if _plate_top is Image:
		_plate_top = ImageTexture.create_from_image(_plate_top)
	if _plate_top_e is Image:
		_plate_top_e = ImageTexture.create_from_image(_plate_top_e)
	if _button is Image:
		_button = ImageTexture.create_from_image(_button)
	if _cursor is Image:
		_cursor = ImageTexture.create_from_image(_cursor)
	if _hex is Image:
		_hex = ImageTexture.create_from_image(_hex)


# ------------------------------------------------------------------------------------------------ records file
## the file's name / its debug flag per mode (part 38: ENDLESS has its own file)
static func _file(e: bool) -> String:
	return FILE_ENDLESS if e else FILE


static func _flag(e: bool) -> String:
	return "esrec" if e else "asrec"


## "" = no file (captures without `asrec=` / `esrec=`)
static func path(e := false) -> String:
	if Game.args.has(_flag(e)):
		return Game.flag(_flag(e))
	if Game.args.has("capture"):
		return ""
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join(_file(e))
	return "user://" + _file(e)


## part 38 (settings HI-SCORES RESET): both records files removed (and their user:// copies of a read-only exe folder)
static func reset_files() -> void:
	for e in [false, true]:
		var ps := [path(e)]
		if OS.has_feature("template") and not Game.args.has(_flag(e)):
			ps.append("user://" + _file(e))
		for p in ps:
			if p != "" and FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## the valid entries of the file, best first (at most MAX); [entries, damaged]
static func load_table(p: String, e := false) -> Array:
	var out: Array = []
	if p == "":
		return [out, false]
	var c := ConfigFile.new()
	var err := c.load(p)
	if err != OK and OS.has_feature("template") and not Game.args.has(_flag(e)):
		err = c.load("user://" + _file(e))   # (written there when the exe folder was read-only)
	if err != OK:
		return [out, err != ERR_FILE_NOT_FOUND and FileAccess.file_exists(p)]
	if c.has_section("records"):
		for k in c.get_section_keys("records"):
			var x := entry_from(c.get_value("records", k, null), e)
			if not x.is_empty():
				out.append(x)
	out.sort_custom(before_e if e else before)
	if out.size() > MAX:
		out.resize(MAX)
	return [out, false]


## a record from a file value, or {} when it is not one (any field missing / of a wrong type / out of range);
## part 38 ENDLESS records also need "beaten" (1..BEATEN_MAX)
static func entry_from(v: Variant, e := false) -> Dictionary:
	if not v is Dictionary:
		return {}
	var d: Dictionary = v
	var f := _int(d.get("frames"))
	var h := _int(d.get("hearts"))
	if f < 1 or f > int((CAP_S + 1) * FPS) or h < 0 or h > 3:
		return {}
	var bt := _int(d.get("beaten")) if e else 0
	if e and (bt < 1 or bt > BEATEN_MAX):
		return {}
	var ids: Array = []
	var raw: Variant = d.get("ids")
	if raw is Array or raw is PackedInt32Array or raw is PackedInt64Array:
		for x in raw:
			var i := _int(x)
			if i < 0 or i > 38:
				return {}
			if i < 37 and ids.size() < 3:
				ids.append(i)
	if ids.is_empty():
		return {}
	var date: Variant = d.get("date", "")
	var out := {"frames": f, "ids": ids, "hearts": h, "date": date if date is String else ""}
	if e:
		out["beaten"] = bt
	return out


static func _int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is String and (v as String).strip_edges().is_valid_int():
		return int(v)
	return -1


## sort order: shorter time, then fewer hearts, then the older entry
static func before(a: Dictionary, b: Dictionary) -> bool:
	if a.frames != b.frames:
		return a.frames < b.frames
	if a.hearts != b.hearts:
		return a.hearts < b.hearts
	return String(a.date) < String(b.date)


## part 38 ENDLESS sort order: more enemies beaten, then shorter time, fewer hearts, the older entry
static func before_e(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("beaten", 0)) != int(b.get("beaten", 0)):
		return int(a.get("beaten", 0)) > int(b.get("beaten", 0))
	return before(a, b)


## where `e` goes (0..MAX-1) in `t` (sorted), MAX = not in the top: below every entry that is not worse
static func rank_of(t: Array, e: Dictionary, endless_order := false) -> int:
	var r := 0
	for x in t:
		if (before_e(e, x) if endless_order else before(e, x)):
			break
		r += 1
	return mini(r, MAX)


static func save_table(p: String, t: Array, damaged: bool, e := false) -> bool:
	if p == "":
		return false
	if damaged and FileAccess.file_exists(p):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(p) + ".bak")
	var c := ConfigFile.new()
	for i in t.size():
		c.set_value("records", "r%d" % (i + 1), t[i])
	var err := c.save(p)
	if err != OK and OS.has_feature("template") and not Game.args.has(_flag(e)):
		err = c.save("user://" + _file(e))       # read-only folder: keep it in the user data folder (as settings.cfg)
	return err == OK


static func time_text(frames: int) -> String:
	var s := mini(int(frames / FPS), CAP_S)
	return "%02d:%02d" % [s / 60, s % 60]


# ------------------------------------------------------------------------------------------------ open / close
## after every game frame (QoLController.after_step)
func frame(_core) -> void:
	if not shown:
		if not _built and allstar != null and allstar.active:
			_start_art()
		if allstar != null and allstar.records_req:
			allstar.records_req = false
			_open(false)
		elif _demo_at >= 0 and qol.game.frames == _demo_at:   # (`esrecdemo=F`: the ENDLESS page, part 38)
			_open(true)                          # `asrecdemo=F`: the page as after a win, no battle needed
		return
	_t += 1
	_ht += 1
	if _phase == 0 and _t >= FADE:
		_phase = 1
	elif _phase == 2 and _t >= FADE:
		_phase = 3
		_t = 0
	elif _phase == 3 and _t >= FADE:
		shown = false
		visible = false
		if allstar != null and allstar.stage == QoLAllStar.RECORDS:
			allstar.stage = QoLAllStar.SELECT
		_log("closed")
	queue_redraw()


func _open(demo: bool) -> void:
	endless = (allstar != null and allstar.endless) or (demo and Game.args.has("esrecdemo"))
	if endless:
		_open_endless(demo)
		return
	var cheats: int = qol.settings.cheats_on()
	var full := allstar != null and allstar.start_index == 0 and allstar.order == QoLAllStar.ROSTER
	var ids: Array = []
	for i in ((allstar.p1_ids + [allstar.p1_support]) if allstar != null else []):   # fighters, then the support
		if int(i) >= 0 and int(i) < 37 and ids.size() < 3:
			ids.append(int(i))
	var e := {"frames": maxi(1, allstar.elapsed_frames if allstar != null else 1), "ids": ids,
		"hearts": clampi(allstar.hearts_used if allstar != null else 0, 0, 3),
		"date": Time.get_datetime_string_from_system(false, true)}
	if Game.args.has("asfakewin") or demo:     # debug: a cheat-free full run with this time / hearts / team
		var p := Game.flag("asfakewin").split(":") if Game.args.has("asfakewin") else PackedStringArray(["12", "34"])
		if p.size() >= 2:
			e.frames = int((int(p[0]) * 60 + int(p[1])) * FPS) + 1
		if p.size() >= 3:
			e.hearts = clampi(int(p[2]), 0, 3)
		if Game.args.has("asfakewin"):         # (a demo without it keeps the cheats rule: cheats=... -> not saved)
			cheats = 0
			full = true
	if e.ids.is_empty():
		e.ids = [0, 5, 6] if not Game.args.has("asp1") else Array(Array(Game.flag("asp1").split(",")).map(func(s): return clampi(int(s), 0, 36)))
	entry = e
	var ld := load_table(path())
	table = ld[0]
	new_rank = -1
	saved = false
	note = ""
	if cheats > 0:
		note = "cheats"
	elif not full:
		note = "partial"
	else:
		var r := rank_of(table, e)
		if r >= MAX:
			note = "out"
		else:
			table.insert(r, e)
			if table.size() > MAX:
				table.resize(MAX)
			new_rank = r
			saved = save_table(path(), table, ld[1])
			if not saved:
				note = "nofile"
	_log("open: time %s (%d frames) hearts %d ids %s cheats %d full %s -> rank %d saved %s note '%s' file '%s' damaged %s table %s" % [
		time_text(e.frames), e.frames, e.hearts, str(e.ids), cheats, full, new_rank + 1, saved, note, path(), ld[1],
		str(table.map(func(x): return "%s/%d/%s" % [time_text(x.frames), x.hearts, str(x.ids)]))])
	show_page()


## part 38: the ENDLESS RECORDS page after a lost ENDLESS battle: this run = {beaten, frames, ids, hearts, date}
func _open_endless(demo: bool) -> void:
	var cheats: int = qol.settings.cheats_on()
	var ids: Array = []
	for i in ((allstar.p1_ids + [allstar.p1_support]) if allstar != null else []):   # fighters, then the support
		if int(i) >= 0 and int(i) < 37 and ids.size() < 3:
			ids.append(int(i))
	var e := {"beaten": clampi(allstar.beaten if allstar != null else 0, 0, BEATEN_MAX),
		"frames": maxi(1, allstar.elapsed_frames if allstar != null else 1), "ids": ids,
		"hearts": clampi(allstar.hearts_used if allstar != null else 0, 0, 3),
		"date": Time.get_datetime_string_from_system(false, true)}
	if Game.args.has("esfake") or demo:      # debug: a cheat-free run with these enemies / time / hearts
		var p := Game.flag("esfake").split(":") if Game.args.has("esfake") else PackedStringArray(["12", "8", "21"])
		if p.size() >= 1:
			e.beaten = clampi(int(p[0]), 0, BEATEN_MAX)
		if p.size() >= 3:
			e.frames = int((int(p[1]) * 60 + int(p[2])) * FPS) + 1
		if p.size() >= 4:
			e.hearts = clampi(int(p[3]), 0, 3)
		if Game.args.has("esfake"):
			cheats = 0
	if e.ids.is_empty():
		e.ids = [0, 5, 6] if not Game.args.has("asp1") else Array(Array(Game.flag("asp1").split(",")).map(func(s): return clampi(int(s), 0, 36)))
	entry = e
	var ld := load_table(path(true), true)
	table = ld[0]
	new_rank = -1
	saved = false
	note = ""
	if cheats > 0:
		note = "cheats"
	else:
		var r := rank_of(table, e, true) if e.beaten > 0 else MAX
		if r >= MAX:
			note = "out"
		else:
			table.insert(r, e)
			if table.size() > MAX:
				table.resize(MAX)
			new_rank = r
			saved = save_table(path(true), table, ld[1], true)
			if not saved:
				note = "nofile"
	_log("open ENDLESS: beaten %d time %s (%d frames) hearts %d ids %s cheats %d -> rank %d saved %s note '%s' file '%s' damaged %s table %s" % [
		e.beaten, time_text(e.frames), e.frames, e.hearts, str(e.ids), cheats, new_rank + 1, saved, note, path(true), ld[1],
		str(table.map(func(x): return "%d/%s/%d/%s" % [x.beaten, time_text(x.frames), x.hearts, str(x.ids)]))])
	show_page()


## builds the page for `entry` / `table` / `new_rank` / `note` and shows it (also used by tools/qol_preview.gd)
func show_page() -> void:
	var t0 := Time.get_ticks_msec()
	_ensure_art()
	_build_page()
	_log("page built in %d ms" % (Time.get_ticks_msec() - t0))
	if allstar != null and allstar.active:
		allstar.stage = QoLAllStar.RECORDS
	shown = true
	visible = true
	_phase = 0
	_t = 0
	_ht = 0
	_press = false
	queue_redraw()


func _close(how: String) -> void:
	if _phase != 1:
		return
	_phase = 2
	_t = 0
	qol.se(QoLController.SE_DECIDE)
	_log("OK by %s" % how)


## main thread, before each game frame while shown: everything is kept from the game (held keys / touch stay blocked
## until released, so the A that closes the page cannot pick a character on the select behind it)
func filter(newly: int, down: int, touch: Vector2i, new_touch: bool) -> Array:
	qol._block_keys = down
	qol._block_touch = touch.x >= 0
	_press = touch.x >= 0 and OK_RECT.has_point(touch)
	if _phase == 1:
		if (newly & 1) != 0:
			_close("A")
		elif (newly & 8) != 0:
			_close("START")
		elif (newly & 2) != 0:
			_close("B")
		elif new_touch and OK_RECT.has_point(touch):
			_close("tap %d/%d" % [touch.x, touch.y])
	return [0x3FF, 0x2C00, Vector2i(-1, -1)]


func _log(s: String) -> void:
	if dbg:
		print("AS f%d records %s" % [qol.game.frames if qol != null and qol.get("game") != null else -1, s])


# ------------------------------------------------------------------------------------------------ ROM art
func _load_art() -> void:
	var t0 := Time.get_ticks_msec()
	var f := QoLFont.nitro_file(rom, "romdata/game/result.bin")
	var fi := QoLFont.nitro_file(rom, "romdata/game/game_faceicon.arc")
	var fc := QoLFont.nitro_file(rom, "romdata/scene/common/CharFace256.bin")
	var fb := QoLFont.nitro_file(rom, "romdata/scene/common/common_bg.bin")
	if f.x < 0 or fi.x < 0 or fc.x < 0 or fb.x < 0:
		print("ALL-STAR records: art not found in the ROM")
		return
	var pk := _pack(f)
	for n in ["base1st", "base2st", "base3st", "base4st", "base5st", "e_hi_score", "e_charasele", "e_continue",
			"no0", "e_res_bg", "cursol"]:
		if not pk.has(n + ".ntft") and not pk.has(n + ".ntfp") and not pk.has(n + ".nbfc"):
			print("ALL-STAR records: %s missing in result.bin" % n)
			return
	_pal16 = _pal(_member(pk, "base1st.ntfp"))
	# rank rows (+ the new row's flash: plate lighter)
	for i in 5:
		var n := "base%dst" % (i + 1)
		var img := lin4(_member(pk, n + ".ntft"), 256).image(_pal(_member(pk, n + ".ntfp")))
		_rows.append(img)
		var hi := img.duplicate() as Image
		for y in hi.get_height():
			for x in hi.get_width():
				var c := hi.get_pixel(x, y)
				if c.a > 0.0:
					hi.set_pixel(x, y, c.lerp(Color.WHITE, 0.45))
		_rows_hi.append(hi)
	for d in 10:
		_no.append(lin4(_member(pk, "no%d.ntft" % d), 8))
	# the results panel (all five languages: their labels are the letter sources)
	var res := {}
	for l in ["e", "f", "g", "i", "s"]:
		var ch := _member(pk, l + "_res_bg.nbfc")
		var mp := _member(pk, l + "_res_bg.nbfs")
		if ch.size() > 0 and mp.size() >= 2048:
			res[l] = tiles(ch, mp, 32, 32)
	_res = res.get("e")
	_tfont = GFont.new(RANK_DARK)
	_wfont = GFont.new(RANK_WHITE)
	for s in TABLE_SRC:
		if res.has(s[0]) and not harvest(_tfont, res[s[0]], LINE_Y0 + 16 * int(s[1]), 13, 86, 248, s[3], s[2]):
			_log("table letters: '%s' (%s) not split" % [s[2], s[0]])
	for s in WHITE_SRC:
		if res.has(s[0]) and not harvest(_wfont, res[s[0]], s[1], 13, s[2], s[3], s[5], s[4]):
			_log("white letters: '%s' (%s) not split" % [s[4], s[0]])
	_tfont.finish(0, 5)
	_wfont.finish(0, 5)
	_make_table_glyphs()
	# part 38: the WINNER banner's heavy capitals (one typeface in all five languages, the English just set wider)
	_bfont = GFont.new(RANK_WHITE)
	for s in BANNER_SRC:
		if res.has(s[0]):
			var bb := _banner_rows(res[s[0]])
			if bb.x < 0 or not harvest_cc(_bfont, res[s[0]], bb.x, bb.y - bb.x + 1, s[1], int(s[2])):
				_log("banner letters: '%s' (%s) not split" % [s[1], s[0]])
	_bfont.contour = true                              # (spaced by outlines like the kerned originals)
	_bfont.gap = 3
	_bfont.space = 10
	if not _bfont.has("M") and _bfont.has("N") and _bfont.has("V"):
		var mm := _make_m(_bfont)
		_bfont.add("M", mm[0], int(_bfont.glyphs["N"][1]) + int(mm[1]))
	# part 38: the digit strips as ink (packed 1 px apart instead of in 8-px cells: a "1" left gaps)
	_ydig = []
	_odig = []
	_ndig = []
	for d in 10:
		_ydig.append(_ink(_res.crop(d * 8, 192, 8, 16), 8) if _res != null else [Canvas.new(1, 1), 0])
		_odig.append(_ink(_res.crop(d * 8, 208, 8, 12), 10) if _res != null else [Canvas.new(1, 1), 0])
		_ndig.append(_ink(_no[d], 8))
	# the difficulty words' letters (+ the ranking digits for "1 HEART")
	_rfont = GFont.new(RANK_DARK)
	for s in WORD_SRC:
		var t := _member(pk, s[0] + ".ntft")
		if t.size() >= 512 and not harvest(_rfont, lin4(t, 64), 0, 15, 0, 64, [1], s[1]):
			_log("word letters: '%s' not split" % s[1])
	for d in 10:
		var gc := _ink(_no[d], 8)
		_rfont.add(str(d), gc[0], gc[1] + 1)     # digit ink rows 4-11 -> bottom on the words' row 12
	_rfont.finish(0, 4)
	# the ranking title (the plate's own italic capitals)
	var plate := lin4(_member(pk, "e_hi_score.ntft"), 256)
	var ppal := _pal(_member(pk, "e_hi_score.ntfp"))
	_pfont = GFont.new(RANK_WHITE)
	var base_y := -1
	for s in PLATE_SRC:
		var t := _member(pk, s[0] + "_hi_score.ntft")
		if t.size() < 4096:
			continue
		var b := harvest_plate(_pfont, lin4(t, 256), s[1])
		if b < 0:
			_log("plate letters: '%s' not split" % s[1])
		elif s[0] == "e":
			base_y = b
	_pfont.finish(0, 6)
	_pfont.contour = true                              # part 38: outline spacing (see GFont.contour)
	_pfont.gap = PLATE_GAP
	_pfont.space = PLATE_SPACE
	var top := plate.copy()
	if base_y < 0 or not plate_title(top, _pfont, base_y, "ALL-STAR RECORDS"):
		_log("plate title: the port's capitals (fallback)")
		var raw := _member(pk, "e_hi_score.ntft")
		retitle(raw, 256, 5, 1, [1, 0xB, 0xD, 0xC, 0xF], "ALL-STAR RECORDS")
		top = lin4(raw, 256)
	_plate_top = top.image(ppal)
	var top_e := plate.copy()                          # part 38: the ENDLESS RECORDS plate (same rules)
	if base_y < 0 or not plate_title(top_e, _pfont, base_y, "ENDLESS RECORDS"):
		var raw := _member(pk, "e_hi_score.ntft")
		retitle(raw, 256, 5, 1, [1, 0xB, 0xD, 0xC, 0xF], "ENDLESS RECORDS")
		top_e = lin4(raw, 256)
	_plate_top_e = top_e.image(ppal)
	# OK plate + the results' cursor (frame + triangle), rows 2-7 left out (plain plate yellow)
	var cpal := _pal(_member(pk, "e_continue.ntfp"))
	_button = _label_room(lin4(_member(pk, "e_charasele.ntft"), 256).rows(BTN_ROWS), 3).image(cpal)
	_cursor = lin4(_member(pk, "cursol.ntft"), 256).rows(BTN_ROWS).image(cpal)
	# face icons: GARC entries 2*id (32 x 32 4-bit, icon at 0..23) and 2*id+1 (palette)
	var n := rom.decode_u32(fi.x + 8)
	var base := fi.x + rom.decode_u32(fi.x + 12)
	for id in mini(37, n / 2):
		var go := rom.decode_u32(fi.x + 0x10 + 16 * id)
		var gs := rom.decode_u32(fi.x + 0x14 + 16 * id)
		var po := rom.decode_u32(fi.x + 0x18 + 16 * id)
		if gs < 512:
			continue
		var img := lin4(rom.slice(base + go, base + go + 512), 32).image(_pal(rom.slice(base + po, base + po + 32)))
		_faces[id] = img.get_region(Rect2i(0, 0, 24, 24))
	# portraits (80 x 40, 256 colours, one palette) and the empty slot
	var pf := _pack(fc)
	_face_pal = _pal(_member(pf, "gkn_face.nbfp"), 256)
	for id in FACE_NAMES.size() + 1:
		var nm: String = FACE_NAMES[id] if id < FACE_NAMES.size() else "nul1"
		var ch := _member(pf, nm + "_face.nbfc")
		var mp := _member(pf, nm + "_face.nbfs")
		if ch.size() > 0 and mp.size() >= 2048:
			_face_px[id if id < FACE_NAMES.size() else -1] = tiles(ch, mp, 10, 5, true)
	# the hexagons: the top-left 64 x 64 of cstat_bg (the pattern repeats every 64 x 32)
	var pb := _pack(fb)
	var hc := _member(pb, "cstat_bg.nbfc")
	var hm := _member(pb, "cstat_bg.nbfs")
	if hc.size() > 0 and hm.size() >= 2048:
		var hp := _pal(_member(pb, "cstat_bg.nbfp"))
		hp[0] = hp[1]
		var hx := tiles(hc, hm, 32, 32).crop(0, 0, 64, 64)
		_hex = hx.image(hp)
	_ok = _res != null and _hex != null
	if dbg:
		_log("letters: table '%s' gap %d space %d | white '%s' | words '%s' | plate '%s'" % [
			"".join(_tfont.glyphs.keys()), _tfont.gap, _tfont.space, "".join(_wfont.glyphs.keys()),
			"".join(_rfont.glyphs.keys()), "".join(_pfont.glyphs.keys())])
		_log("banner letters '%s'" % "".join(_bfont.glyphs.keys()))
		_log("art built in %d ms" % (Time.get_ticks_msec() - t0))
		_log("word gap %d space %d widths %s" % [_rfont.gap, _rfont.space, str(HEART_WORDS.map(func(o): return o.map(func(t): return _rfont.width(t))))])


## the table letters the labels lack, put together from the font's own strokes: d (o + the stem of l), H (two l stems +
## a bar), w (two u), ! (the top of l + .), - (a bar of the strokes' shades)
func _make_table_glyphs() -> void:
	var f := _tfont
	if f.has("o") and f.has("l") and not f.has("d"):
		var o: Canvas = f.glyphs["o"][0]
		var l: Canvas = f.glyphs["l"][0]
		var dx := _core_col(o, true) - _core_col(l, false)
		var u := _union([[o, 0, int(f.glyphs["o"][1])], [l, dx, int(f.glyphs["l"][1])]], f.rank)
		f.add("d", u[0], u[1])
	if f.has("l") and f.has("U") and not f.has("H"):
		var l: Canvas = f.glyphs["l"][0]
		var uc: Canvas = f.glyphs["U"][0]
		var du := _core_col(uc, true) - _core_col(uc, false)
		var ly := int(f.glyphs["l"][1])
		var u := _union([[l, 0, ly], [l, du, ly]], f.rank)
		var c: Canvas = u[0]
		var x0 := _core_col(l, false)
		var rows := _core_rows(l)
		var ym := (rows.x + rows.y + 1) / 2
		for x in range(x0 + 1, x0 + du):
			_put_max(c, x, ym, 1, f.rank)
			_put_max(c, x, ym - 1, 6, f.rank)
			_put_max(c, x, ym + 1, 4, f.rank)
		f.add("H", c, u[1])
	if f.has("u") and not f.has("w"):
		var uc: Canvas = f.glyphs["u"][0]
		var du := _core_col(uc, true) - _core_col(uc, false)
		var uy := int(f.glyphs["u"][1])
		var u := _union([[uc, 0, uy], [uc, du, uy]], f.rank)
		f.add("w", u[0], u[1])
	if f.has("l") and not f.has("!"):
		var l: Canvas = f.glyphs["l"][0]
		var rows := _core_rows(l)
		var top := l.crop(0, 0, l.w, rows.y - 2)          # the stem without its last 3 rows
		var parts := [[top, 0, int(f.glyphs["l"][1])]]
		if f.has("."):
			var dot: Canvas = f.glyphs["."][0]
			parts.append([dot, _core_col(l, false) - _core_col(dot, false), int(f.glyphs["."][1])])
		var u := _union(parts, f.rank)
		f.add("!", u[0], u[1])
	if not f.has("-"):
		f.add("-", _template(["766667", "411114", "766667"]), 5)
	if not _wfont.has("-"):
		_wfont.add("-", _template(["bccccb", "dffffd", "2dddd2"]), 5)
	if _wfont.has("O") and _wfont.has("L") and not _wfont.has("D"):   # part 38 (tab "ENDLESS")
		_wfont.add("D", _make_d(_wfont), int(_wfont.glyphs["O"][1]))


## part 38: the "Character Select" plate's label moved `dx` px left inside the plate: in the game's art (V e_charasele:
## plate 0xA, outer frame x 254-255, an inner frame line at x 250 rows 5-27 + row 27) the last "t" ends at x 248, one
## column from the inner line, and reads as cut off. Frame columns / rows (mostly not plate colour) stay; only the
## label's pixels (columns 48 .. its last column, rows that are not frame rows) move.
static func _label_room(c: Canvas, dx: int) -> Canvas:
	var fill := c.g(150, 3)                             # plate colour (top rows under the frame)
	var fcol: Array = []                                # frame column: not plate colour in >= 85 % of the rows
	for x in c.w:
		var n := 0
		for y in c.h:
			if c.g(x, y) != fill:
				n += 1
		fcol.append(n * 20 >= c.h * 17)
	var frow: Array = []                                # frame row: not plate colour in > 80 % of x 48..
	for y in c.h:
		var n := 0
		for x in range(48, c.w):
			if c.g(x, y) != fill:
				n += 1
		frow.append(n * 5 > (c.w - 48) * 4)
	var last := -1                                      # the label's last column
	for x in range(c.w - 1, 47, -1):
		if fcol[x]:
			continue
		for y in c.h:
			if not frow[y] and c.g(x, y) != fill:
				last = x
				break
		if last >= 0:
			break
	if last < 0:
		return c
	var out := c.copy()
	for y in c.h:
		if frow[y]:
			continue
		for x in range(48, last + 1):
			if not fcol[x]:
				out.s(x, y, fill)
		for x in range(48 + dx, last + 1):
			if not fcol[x] and c.g(x, y) != fill:
				out.s(x - dx, y, c.g(x, y))
	return out


## part 38: a capital M for the banner typeface (none of its five words has one): N's upright left stem, the V
## between, and the same stem mirrored on the right (|V|, the V's arms joining the stems' tops, its point on the
## baseline, as the typeface's heavy upright capitals)
static func _make_m(f: GFont) -> Array:
	var n: Canvas = f.glyphs["N"][0]
	var v: Canvas = f.glyphs["V"][0]
	var stem := 0                                       # N's left stem: columns full of core (15) pixels
	for x in n.w:
		var full := 0
		for y in n.h:
			if n.g(x, y) == 15:
				full += 1
		if full * 10 < n.h * 9:
			if stem > 0:
				break
			continue
		stem = x + 1
	stem = maxi(stem, 4)
	var left := n.crop(0, 0, stem, n.h)
	var right := Canvas.new(stem, n.h)
	for y in n.h:
		for x in stem:
			right.s(stem - 1 - x, y, left.g(x, y))
	var ov := 2                                         # the V's arms overlap the stems a little
	var dv := int(f.glyphs["V"][1]) - int(f.glyphs["N"][1])
	return _union([[left, 0, 0], [v, stem - ov, dv], [right, stem - ov + v.w - ov, 0]], f.rank)


## part 38: a capital D for a font that has O and L: L's stem on the left, O's right half, and between them O's
## middle column carried across (the top and bottom bars; the inside stays empty)
static func _make_d(f: GFont) -> Canvas:
	var o: Canvas = f.glyphs["O"][0]
	var l: Canvas = f.glyphs["L"][0]
	var dy := int(f.glyphs["L"][1]) - int(f.glyphs["O"][1])
	var mid := l.h / 2                                  # L's stem width: its strong columns half way down
	var stem := 0
	while stem < l.w and f.rank[l.g(stem, mid)] == 0:
		stem += 1
	while stem < l.w and f.rank[l.g(stem, mid)] > 0:
		stem += 1
	var c := o.copy()
	var half := o.w / 2
	for y in o.h:
		for x in half:
			c.s(x, y, l.g(x, y - dy) if x < stem else o.g(half, y))
	return c


## a small glyph from hex digits (palette indices; "." = none)
static func _template(rows: Array) -> Canvas:
	var c := Canvas.new((rows[0] as String).length(), rows.size())
	for y in rows.size():
		for x in (rows[y] as String).length():
			var ch: String = rows[y][x]
			if ch != ".":
				c.s(x, y, ("0x" + ch).hex_to_int())
	return c


## the rightmost (or leftmost) column with a black (index 1) pixel
static func _core_col(c: Canvas, right: bool) -> int:
	var xs := range(c.w - 1, -1, -1) if right else range(c.w)
	for x in xs:
		for y in c.h:
			if c.g(x, y) == 1:
				return x
	return c.w - 1 if right else 0


## first / last row with a black pixel
static func _core_rows(c: Canvas) -> Vector2i:
	var a := -1
	var b := -1
	for y in c.h:
		for x in c.w:
			if c.g(x, y) == 1:
				if a < 0:
					a = y
				b = y
				break
	return Vector2i(maxi(a, 0), maxi(b, 0))


static func _put_max(c: Canvas, x: int, y: int, v: int, rank: Array) -> void:
	if rank[v] > rank[c.g(x, y)]:
		c.s(x, y, v)


## [Canvas, dy] of glyph parts [[canvas, dx, dy], ...] drawn together (stronger pixel wins)
static func _union(parts: Array, rank: Array) -> Array:
	var x0 := 99999
	var y0 := 99999
	var x1 := -99999
	var y1 := -99999
	for p in parts:
		var c: Canvas = p[0]
		x0 = mini(x0, p[1])
		y0 = mini(y0, p[2])
		x1 = maxi(x1, int(p[1]) + c.w)
		y1 = maxi(y1, int(p[2]) + c.h)
	var out := Canvas.new(x1 - x0, y1 - y0)
	for p in parts:
		out.blit(p[0], int(p[1]) - x0, int(p[2]) - y0, rank)
	return [out, y0]


## [ink canvas, top row] of a digit cell (its pixels other than the cell colour 8)
static func _ink(c: Canvas, bgv: int) -> Array:
	var x0 := c.w
	var x1 := -1
	var y0 := c.h
	var y1 := -1
	for y in c.h:
		for x in c.w:
			var v := c.g(x, y)
			if v != 0 and v != bgv:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return [Canvas.new(1, 1), 0]
	var out := c.crop(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	for i in out.px.size():
		if out.px[i] == bgv:
			out.px[i] = 0
	return [out, y0]


## cuts the letters of `text` (spaces between words) out of a pre-lettered line: the columns holding a `dark` stroke
## pixel form one run per letter (false when they do not split into exactly the letters); every other glyph pixel of the
## band (font rank > 0) goes to the run whose strokes are horizontally nearest in its row +-1 (at most 3 px away)
static func harvest(f: GFont, cv: Canvas, y0: int, h: int, x0: int, x1: int, dark: Array, text: String) -> bool:
	var chars := text.replace(" ", "")
	var runs: Array = []
	var start := -1
	for x in range(x0, x1 + 1):
		var d := false
		if x < x1:
			for y in range(y0, y0 + h):
				if dark.has(cv.g(x, y)):
					d = true
					break
		if d and start < 0:
			start = x
		elif not d and start >= 0:
			runs.append([start, x - 1])
			start = -1
	if runs.size() != chars.length():
		return false
	var n := runs.size()
	var mn: Array = []
	var mx: Array = []
	for r in runs:
		var a := PackedInt32Array()
		var b := PackedInt32Array()
		a.resize(h)
		b.resize(h)
		a.fill(-1)
		b.fill(-1)
		for y in h:
			for x in range(r[0], int(r[1]) + 1):
				if dark.has(cv.g(x, y0 + y)):
					if a[y] < 0:
						a[y] = x
					b[y] = x
		mn.append(a)
		mx.append(b)
	var pix: Array = []
	for i in n:
		pix.append([])
	for y in h:
		for x in range(x0, x1):
			var v := cv.g(x, y0 + y)
			if f.rank[v] == 0:
				continue
			var best := -1
			var bd := 4
			for i in n:
				for yy in range(maxi(0, y - 1), mini(h, y + 2)):
					var a: int = mn[i][yy]
					if a < 0:
						continue
					var b: int = mx[i][yy]
					var dd := 0 if x >= a and x <= b else mini(absi(x - a), absi(x - b))
					if dd < bd:
						bd = dd
						best = i
			if best >= 0:
				pix[best].append(Vector3i(x, y, v))
	var word := 0
	var words: Array = []
	for c in text:
		if c == " ":
			word += 1
		else:
			words.append(word)
	var boxes: Array = []
	for i in n:
		var bx := Rect2i(runs[i][0], 0, int(runs[i][1]) - int(runs[i][0]) + 1, 1)
		var first := true
		for p in pix[i]:
			if first:
				bx = Rect2i(p.x, p.y, 1, 1)
				first = false
			else:
				bx = bx.expand(Vector2i(p.x, p.y)).expand(Vector2i(p.x + 1, p.y + 1))
		var g := Canvas.new(bx.size.x, bx.size.y)
		for p in pix[i]:
			g.s(p.x - bx.position.x, p.y - bx.position.y, p.z)
		boxes.append(bx)
		f.add(chars[i], g, bx.position.y)
	for i in n - 1:
		var gp: int = boxes[i + 1].position.x - boxes[i].end.x
		(f.gaps if words[i] == words[i + 1] else f.spaces).append(gp)
	return true


## part 38: the letters of `text` in rows y0..y0+h-1 as connected shapes of core pixels (index 15, 8-connected; pieces
## under 20 px dropped), left to right; every other glyph pixel (font rank > 0) goes to the shape it touches within
## 2 px. For kerned words (VAINQUEUR's V-A share columns, which harvest() cannot split). Glyph dy = top - y0. False
## when the shapes are not exactly the letters -- unless `lead` > 0: then only the first `lead` letters are taken from
## the first `lead` shapes (V: VAINQUEUR's A and I touch, its V stands alone).
static func harvest_cc(f: GFont, cv: Canvas, y0: int, h: int, text: String, lead := 0) -> bool:
	var chars := text.replace(" ", "")
	var lab := Canvas.new(cv.w, h)
	var comps: Array = []
	for y in h:
		for x in cv.w:
			if lab.g(x, y) != 0 or cv.g(x, y0 + y) != 15:
				continue
			var id := comps.size() + 1
			var st: Array = [Vector2i(x, y)]
			lab.s(x, y, id)
			var px: Array = []
			while not st.is_empty():
				var q: Vector2i = st.pop_back()
				px.append(q)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var r: Vector2i = q + d
					if r.y >= 0 and r.y < h and r.x >= 0 and r.x < cv.w and lab.g(r.x, r.y) == 0 \
							and cv.g(r.x, y0 + r.y) == 15:
						lab.s(r.x, r.y, id)
						st.append(r)
			comps.append(px)
	var keep: Array = []
	for i in comps.size():
		if comps[i].size() >= 20:
			keep.append(i)
	var minx := func(i: int) -> int:
		var m := 9999
		for p in comps[i]:
			m = mini(m, p.x)
		return m
	keep.sort_custom(func(a, b): return minx.call(a) < minx.call(b))
	if keep.size() != chars.length():
		if lead <= 0 or keep.size() < lead:
			return false
		keep.resize(lead)
		chars = chars.left(lead)
	var slot := {}
	for k in keep.size():
		slot[keep[k] + 1] = k
	var pix: Array = []
	for k in keep.size():
		pix.append([])
		for p in comps[keep[k]]:
			pix[k].append(Vector3i(p.x, p.y, 15))
	for y in h:
		for x in cv.w:
			var v := cv.g(x, y0 + y)
			if v == 15 or f.rank[v] == 0:
				continue
			var best := -1
			var bd := 3
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var id := lab.g(x + dx, y + dy)
					if slot.has(id) and maxi(absi(dx), absi(dy)) < bd:
						bd = maxi(absi(dx), absi(dy))
						best = slot[id]
			if best >= 0:
				pix[best].append(Vector3i(x, y, v))
	for k in keep.size():
		var bx := Rect2i(pix[k][0].x, pix[k][0].y, 1, 1)
		for p in pix[k]:
			bx = bx.expand(Vector2i(p.x, p.y)).expand(Vector2i(p.x + 1, p.y + 1))
		var g := Canvas.new(bx.size.x, bx.size.y)
		for p in pix[k]:
			g.s(p.x - bx.position.x, p.y - bx.position.y, p.z)
		f.add(chars[k], g, bx.position.y)
	return true


## the italic capitals of a ranking title plate (white strokes 14 / 15, 8-connected, rows 3-21 right of the square
## block; pieces under 5 px = accents, dropped); the grey edge pixels go to the nearest letter (<= 2 px). Glyph dy is
## relative to the plate's baseline (the median last white row of its letters), spacing by the white strokes of rows
## base-10..base-3 (the slant makes whole boxes overlap); returns the baseline row or -1
static func harvest_plate(f: GFont, cv: Canvas, text: String) -> int:
	var chars := text.replace(" ", "")
	var lab := Canvas.new(cv.w, cv.h)
	var comps: Array = []
	for y in range(3, 22):
		for x in range(16, 176):
			if lab.g(x, y) != 0 or (cv.g(x, y) != 15 and cv.g(x, y) != 14):
				continue
			var id := comps.size() + 1
			var st: Array = [Vector2i(x, y)]
			lab.s(x, y, id)
			var px: Array = []
			while not st.is_empty():
				var q: Vector2i = st.pop_back()
				px.append(q)
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var r := q + Vector2i(dx, dy)
						if r.y >= 3 and r.y < 22 and r.x >= 16 and r.x < 176 and lab.g(r.x, r.y) == 0:
							var v := cv.g(r.x, r.y)
							if v == 15 or v == 14:
								lab.s(r.x, r.y, id)
								st.append(r)
			comps.append(px)
	var keep: Array = []
	for i in comps.size():
		if comps[i].size() >= 5:
			keep.append(i)
	if keep.size() != chars.length():
		return -1
	keep.sort_custom(func(a, b):
		var ma := 9999
		var mb := 9999
		for p in comps[a]:
			ma = mini(ma, p.x)
		for p in comps[b]:
			mb = mini(mb, p.x)
		return ma < mb)
	var slot := {}
	for k in keep.size():
		slot[keep[k] + 1] = k
	var pix: Array = []
	var bottoms: Array = []
	for k in keep.size():
		pix.append([])
		var b := 0
		for p in comps[keep[k]]:
			pix[k].append(Vector3i(p.x, p.y, cv.g(p.x, p.y)))
			b = maxi(b, p.y)
		bottoms.append(b)
	for y in range(3, 22):
		for x in range(14, 180):
			var v := cv.g(x, y)
			if v == 15 or v == 14 or RANK_WHITE[v] == 0:
				continue
			var best := -1
			var bd := 3
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var id := lab.g(x + dx, y + dy)
					if slot.has(id):
						var dd := maxi(absi(dx), absi(dy))
						if dd < bd:
							bd = dd
							best = slot[id]
			if best >= 0:
				pix[best].append(Vector3i(x, y, v))
	var word := 0
	var words: Array = []
	for c in text:
		if c == " ":
			word += 1
		else:
			words.append(word)
	var sb := bottoms.duplicate()
	sb.sort()
	var base: int = sb[sb.size() / 2]
	var lefts: Array = []
	var rights: Array = []
	for k in keep.size():
		var bx := Rect2i(pix[k][0].x, pix[k][0].y, 1, 1)
		for p in pix[k]:
			bx = bx.expand(Vector2i(p.x, p.y)).expand(Vector2i(p.x + 1, p.y + 1))
		var g := Canvas.new(bx.size.x, bx.size.y)
		var lx := 9999
		var rx := -9999
		for p in pix[k]:
			g.s(p.x - bx.position.x, p.y - bx.position.y, p.z)
			if (p.z == 15 or p.z == 14) and p.y >= base - 10 and p.y <= base - 3:   # strokes in the middle rows
				lx = mini(lx, p.x)
				rx = maxi(rx, p.x)
		if rx < lx:
			lx = bx.position.x
			rx = bx.end.x - 1
		lefts.append(lx)
		rights.append(rx)
		f.add(chars[k], g, bx.position.y - base, lx - bx.position.x, rx - bx.position.x)
	for k in keep.size() - 1:
		var gp: int = int(lefts[k + 1]) - int(rights[k]) - 1
		(f.gaps if words[k] == words[k + 1] else f.spaces).append(gp)
	return base


## the ranking title plate (e_hi_score as indices) re-lettered: the old white title erased (rows 3-21 right of the
## square block, up to the plate's slanted end), `text` drawn from the old title's first column on the baseline; the
## spacing is tightened by up to 2 px when it would run into the plate's end. False = does not fit / letters missing
static func plate_title(c: Canvas, f: GFont, base: int, text: String) -> bool:
	if f.missing(text) != "":
		return false
	var x0 := 999                                       # the old title's first stroke column (middle rows, as GFont)
	for y in range(base - 10, base - 2):
		for x in range(15, 176):
			var v := c.g(x, y)
			if v == 15 or v == 14:
				x0 = mini(x0, x)
	var edge := PackedInt32Array()
	edge.resize(c.h)
	for y in c.h:
		var e := c.w
		for x in range(100, c.w):
			if c.g(x, y) == 4 or c.g(x, y) == 0:
				e = x
				break
		edge[y] = e
	for extra in [0, -1, -2]:
		var t := Canvas.new(c.w, c.h)
		f.draw(t, x0, base, text, extra)
		var fits := true
		for y in t.h:
			for x in range(t.w - 1, -1, -1):
				if t.g(x, y) != 0:
					if x > edge[y] - 3:
						fits = false
					break
		if not fits:
			continue
		for y in range(3, 22):
			for x in range(15, 176):
				if RANK_WHITE[c.g(x, y)] > 0:
					c.s(x, y, 1)
		c.blit(t, 0, 0)
		return true
	return false


## pack header (type 3 / 4): u16 count at +2, u32 data offset at +4, entries of 0x4C: name[64], unpacked size,
## packed size, offset (as QoLMpPanel._pack)
func _pack(f: Vector2i) -> Dictionary:
	var d := {}
	var n := rom.decode_u16(f.x + 2)
	var hs := rom.decode_u32(f.x + 4)
	for i in n:
		var e := f.x + 8 + i * 0x4C
		var nm := rom.slice(e, e + 64).get_string_from_ascii().replace("\\", "/").get_file()
		if not d.has(nm):
			d[nm] = [rom.decode_u32(e + 64), rom.decode_u32(e + 68), f.x + hs + rom.decode_u32(e + 72)]
	return d


func _member(d: Dictionary, name: String) -> PackedByteArray:
	if not d.has(name):
		return PackedByteArray()
	var v: Array = d[name]
	var raw := rom.slice(v[2], v[2] + v[1])
	return raw if v[0] == v[1] else QoLEpicImg._decompress(raw, v[0])


static func _pal(p: PackedByteArray, n: int = 16) -> Array:
	var out: Array = []
	for i in n:
		var c := p.decode_u16(i * 2) if p.size() >= i * 2 + 2 else 0
		out.append(Color8(((c & 31) * 255) / 31, (((c >> 5) & 31) * 255) / 31, (((c >> 10) & 31) * 255) / 31))
	return out


## a 4-bit linear texture as indices
static func lin4(t: PackedByteArray, w: int) -> Canvas:
	var h := maxi(1, t.size() * 2 / w)
	var c := Canvas.new(w, h)
	for i in mini(t.size() * 2, w * h):
		c.px[i] = (t[i >> 1] >> (4 * (i & 1))) & 15
	return c


## a tiled BG (4- or 8-bit characters, 32-wide map with flips) as indices, `tw` x `th` tiles from the map's top left
static func tiles(ch: PackedByteArray, mp: PackedByteArray, tw: int, th: int, bpp8 := false) -> Canvas:
	var c := Canvas.new(tw * 8, th * 8)
	var ts := 64 if bpp8 else 32
	for ty in th:
		for tx in tw:
			var e := mp.decode_u16((ty * 32 + tx) * 2)
			var t := e & 0x3FF
			var hf := (e >> 10) & 1
			var vf := (e >> 11) & 1
			for y in 8:
				for x in 8:
					var sx := 7 - x if hf else x
					var sy := 7 - y if vf else y
					var v := 0
					if bpp8:
						var o := t * ts + sy * 8 + sx
						v = ch[o] if o < ch.size() else 0
					else:
						var o := t * ts + sy * 4 + (sx >> 1)
						v = ((ch[o] >> (4 * (sx & 1))) & 15) if o < ch.size() else 0
					c.px[(ty * 8 + y) * c.w + tx * 8 + x] = v
	return c


# ------------------------------------------------------------------------------------------------ page content
## the upper screen (results panel with this run's table) and the ranking rows' content, built at open
func _build_page() -> void:
	_row_info.clear()
	_portraits.clear()
	_upper = null
	if not _ok:
		return
	# --- upper: e_res_bg with the table re-lettered
	var u := _res.crop(0, 0, 256, 192)
	for y in range(24, 110):                           # the table's labels / numbers
		for x in range(85, 252):
			if u.g(x, y) != 0:
				u.s(x, y, 8)
	for y in range(10, 23):                            # the tab's "SCORE"
		for x in range(150, 252):
			if u.g(x, y) != 0:
				u.s(x, y, 1)
	for y in range(111, 124):                          # the Total bar's "Total"
		for x in range(86, 175):
			if u.g(x, y) != 0:
				u.s(x, y, 1)
	var tab := "ENDLESS" if endless and _wfont.missing("ENDLESS") == "" else "ALL-STAR"
	_wfont.draw(u, 251 - _wfont.width(tab), 10, tab)
	var lines := _table_lines()
	for k in lines.size():
		var ln: Array = lines[k]
		_tfont.draw(u, LABEL_X, LINE_Y0 + 16 * k, ln[0])
		if ln[1] != "":
			_value(u, VALUE_RIGHT, k, ln[1])
	_wfont.draw(u, 172 - _wfont.width("TIME"), 111, "TIME")
	_orange(u, VALUE_RIGHT, 112, time_text(entry.frames))
	if endless:
		_banner_word(u, BANNER_TEXT)                   # part 38: "WINNER" -> "GAME OVER" in the banner's own letters
	_upper = ImageTexture.create_from_image(u.image(_pal16))
	var ids: Array = entry.get("ids", [])
	for k in 3:
		var id: int = ids[k] if k < ids.size() else -1
		var pc: Canvas = _face_px.get(id, _face_px.get(-1))
		_portraits.append(ImageTexture.create_from_image(pc.image(_face_pal)) if pc != null else null)
	# --- lower: per row the time in the ranking digits + the hearts word
	for i in MAX:
		var c := Canvas.new(256, 32)
		if endless:                                    # part 38: enemies beaten + KO, the time in the word slot
			_row_endless(c, table[i] if i < table.size() else {})
		elif i < table.size():
			var e: Dictionary = table[i]
			_no_time(c, DIG_RIGHT, 8, time_text(e.frames))
			_heart_word(c, int(e.hearts))
		else:
			_no_time(c, DIG_RIGHT, 8, "--:--")
		_row_info.append(ImageTexture.create_from_image(c.image(_pal16)))


## part 38: the banner's word replaced: its letters erased (band black), `text` set in the banner typeface (outline
## spacing, gap 3 like the kerned originals), scaled down as a whole when wider than BANNER_W (GAME OVER is 8
## letters, WINNER 6) and centred in the band. Nothing is drawn when a letter is missing (an empty band rather than a
## wrong word).
func _banner_word(u: Canvas, text: String) -> void:
	var band := _banner_rows(u)
	if band.x < 0 or _bfont == null:
		return
	for y in range(band.x, band.y + 1):
		for x in 256:
			if u.g(x, y) != 1:
				u.s(x, y, 1)
	if _bfont.missing(text) != "":
		_log("banner: letters '%s' missing" % _bfont.missing(text))
		return
	var h := band.y - band.x + 1
	var word := Canvas.new(_bfont.width(text) + 8, h)   # the word at the typeface's own size ...
	_bfont.draw(word, 4, 0, text)
	var box := Rect2i(word.w, word.h, 0, 0)
	for y in word.h:
		for x in word.w:
			if word.g(x, y) != 0:
				box = Rect2i(x, y, 1, 1) if box.size.x == 0 else box.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
	word = word.crop(box.position.x, box.position.y, box.size.x, box.size.y)
	var k := minf(1.0, float(BANNER_W) / word.w)        # ... then scaled down to fit the band (area average)
	if k < 1.0:
		word = _shrink(word, int(round(word.w * k)), int(round(word.h * k)))
	u.blit(word, (256 - word.w) / 2, band.x + (h - word.h) / 2, RANK_WHITE)


## part 38: a white-on-black glyph canvas resized to nw x nh by area averaging; each pixel's coverage (its palette
## brightness between the band's black 1 and white 15) mapped back to the nearest of the banner's own shades
func _shrink(c: Canvas, nw: int, nh: int) -> Canvas:
	var shades := [1, 2, 11, 12, 13, 14, 15]
	var lum := {}
	for v in shades:
		lum[v] = (_pal16[v] as Color).get_luminance() if v < _pal16.size() else 0.0
	var lo: float = lum[1]
	var hi: float = maxf(lum[15], lo + 0.01)
	var cov := func(v: int) -> float:
		return 0.0 if v == 0 else clampf((float(lum.get(v, lo)) - lo) / (hi - lo), 0.0, 1.0)
	var sx := float(c.w) / nw
	var sy := float(c.h) / nh
	var out := Canvas.new(nw, nh)
	for ty in nh:
		var y0 := ty * sy
		var y1 := y0 + sy
		for tx in nw:
			var x0 := tx * sx
			var x1 := x0 + sx
			var acc := 0.0
			for y in range(int(y0), mini(int(ceil(y1)), c.h)):
				var wy := minf(y1, y + 1.0) - maxf(y0, float(y))
				for x in range(int(x0), mini(int(ceil(x1)), c.w)):
					var wx := minf(x1, x + 1.0) - maxf(x0, float(x))
					acc += wx * wy * float(cov.call(c.g(x, y)))
			var a := acc / (sx * sy)
			if a < 0.08:
				continue
			var best := 1
			for v in shades:
				if absf((float(lum[v]) - lo) / (hi - lo) - a) < absf((float(lum[best]) - lo) / (hi - lo) - a):
					best = v
			if best != 1:
				out.s(tx, ty, best)
	return out


## part 38: the WINNER band of e_res_bg: [first, last] row between its two full-width white lines (V: rows 139 / 184
## in all five languages -> 140..183; the letters fill rows 144-178), or -1
static func _banner_rows(u: Canvas) -> Vector2i:
	var borders: Array = []
	for y in range(120, mini(u.h, 200)):
		var n := 0
		for x in 256:
			if u.g(x, y) == 15:
				n += 1
		if n >= 250:
			borders.append(y)
	if borders.size() < 2 or int(borders[-1]) - int(borders[0]) < 24:
		return Vector2i(-1, -1)
	return Vector2i(int(borders[0]) + 1, int(borders[-1]) - 1)


## the table rows: [label, value]
func _table_lines() -> Array:
	if endless:
		return _table_lines_e()
	var best := "--:--"
	if not table.is_empty():
		best = time_text(table[0].frames)
	var rank := "-"
	if new_rank >= 0:
		rank = "%d%s" % [new_rank + 1, ORD[new_rank]]
	var total: int = allstar.total() if allstar != null and allstar.has_method("total") else QoLAllStar.ROSTER.size()
	var beaten := total                                # a win = the last enemy beaten
	if allstar != null and allstar.beaten > 0:
		beaten = mini(total, allstar.start_index + allstar.beaten)
	var status := ""
	var value := ""
	match note:
		"":
			status = "New Record!"
		"out":
			status = "Not Ranked"
		"cheats":
			status = "Cheats On"
			value = "Not Recorded"
		"partial":
			status = "Practice"
			value = "Not Recorded"
		"nofile":
			status = "File Error"
			value = "Not Recorded"
	return [["Enemies", "%d/%d" % [beaten, total]], ["Hearts Used", str(entry.get("hearts", 0))], ["Rank", rank],
		["Best", best], [status, value]]


## part 38: the ENDLESS table: enemies beaten in this run, hearts, rank, the best run's enemies, status
func _table_lines_e() -> Array:
	var rank := "-"
	if new_rank >= 0:
		rank = "%d%s" % [new_rank + 1, ORD[new_rank]]
	var best := str(int(table[0].get("beaten", 0))) if not table.is_empty() else "-"
	var status := ""
	var value := ""
	match note:
		"":
			status = "New Record!"
		"out":
			status = "Not Ranked"
		"cheats":
			status = "Cheats On"
			value = "Not Recorded"
		"nofile":
			status = "File Error"
			value = "Not Recorded"
	return [["Enemies", str(int(entry.get("beaten", 0)))], ["Hearts Used", str(entry.get("hearts", 0))], ["Rank", rank],
		["Best", best], [status, value]]


## a value right-aligned to `xr` on table line k: digits / ':' / '/' / '-' in the table's yellow digit cells (8 x 16,
## at 24 + 16 k), letters (rank suffix, status words) in the table's letters
func _value(c: Canvas, xr: int, k: int, s: String) -> void:
	if s[0] >= "A" and s[0] <= "Z":                     # a word (status row): right-aligned in the table's letters
		_tfont.draw(c, xr - _tfont.width(s), LINE_Y0 + 16 * k, s)
		return
	var letters := ""
	while s.length() > 0 and s[-1] >= "a" and s[-1] <= "z":
		letters = s[-1] + letters
		s = s.left(-1)
	var x := xr
	if letters != "":
		x -= _tfont.width(letters)
		_tfont.draw(c, x, LINE_Y0 + 16 * k, letters)
		x -= 1
	_packed(c, x, 24 + 16 * k, s, _ydig, {":": [5, ["31", "14", "..", "..", "31", "14"]],
		"/": [4, [".....4", "....41", "....1.", "...41.", "..41..", "..1...", ".41...", "41...."]],
		"-": [6, ["7667", "4114", "7667"]]})


## a time right-aligned to `xr` in the Total bar's orange digit cells (8 x 12)
func _orange(c: Canvas, xr: int, y: int, s: String) -> void:
	_packed(c, xr, y, s, _odig, {":": [3, ["31", "15", "..", "..", "31", "15"]]})


## a time right-aligned to `xr` in the ranking's digits no0..no9 (ink only: the row's own yellow shows, also when the
## row flashes), colon and dashes drawn in their style
func _no_time(c: Canvas, xr: int, y: int, s: String) -> int:
	return _packed(c, xr, y, s, _ndig, {":": [5, ["11", "11", "..", "..", "11", "11"]], "-": [7, ["111111", "111111"]]})


## part 38: `s` right-aligned to `xr` (a cell row starting at y): digits = their ink from `dig` ([Canvas, top row]),
## the other characters from `marks` {char: [top row, template rows]}, everything 1 px apart (the game's 8-px cells
## left a gap around every narrow "1": "13 1", "6 1:07")
func _packed(c: Canvas, xr: int, y: int, s: String, dig: Array, marks: Dictionary) -> int:
	var x := xr
	for i in range(s.length() - 1, -1, -1):
		var ch := s[i]
		var g: Canvas = null
		var top := 0
		if ch >= "0" and ch <= "9" and dig.size() == 10:
			g = dig[int(ch)][0]
			top = int(dig[int(ch)][1])
		elif marks.has(ch):
			g = _template(marks[ch][1])
			top = int(marks[ch][0])
		if g == null:
			continue
		x -= g.w
		c.blit(g, x, y + top)
		x -= 1
	return x + 1


## part 38: an ENDLESS ranking row ({} = empty): the enemies beaten + "KO" in the ranking digits' own drawing (K =
## KO_K, O = the digit 0; same rows, same 1-px spacing) ending at KO_RIGHT where the game's score digits end, the
## time in the difficulty word's slot (the same digits, bottom on the words' baseline, with the word underline)
const KO_RIGHT := 122
func _row_endless(c: Canvas, e: Dictionary) -> void:
	if e.is_empty():
		_no_time(c, KO_RIGHT, 8, "--")
	else:
		var x := _packed(c, KO_RIGHT, 8, "0", _ndig, {}) - 1          # O
		var k := _template(KO_K)
		x -= k.w
		c.blit(k, x, 8 + 4)                                         # K (digit ink rows 4..11)
		_no_time(c, x - 4, 8, str(mini(int(e.get("beaten", 0)), BEATEN_MAX)))
	var x0 := _no_time(c, WORD_RIGHT, 13, "--:--" if e.is_empty() else time_text(int(e.frames)))
	for x2 in range(x0 - 2, 203):                       # the word's underline joins the row's (x >= 202)
		c.s(x2, 27, 1)


## the hearts used, lettered like the game's difficulty word (right end of the row, word rows 12-26, underline 27)
func _heart_word(c: Canvas, h: int) -> void:
	var opts: Array = HEART_WORDS[clampi(h, 0, 3)]
	var t: String = opts[-1]
	var sp := _rfont.space
	for o in opts:                                      # the first one that fits (a space 1 px narrower if need be)
		if _rfont.missing(o) != "":
			continue
		if _rfont.width(o) > WORD_W and o.contains(" "):
			_rfont.space = sp - 1
		if _rfont.width(o) <= WORD_W:
			t = o
			break
		_rfont.space = sp
	var x := WORD_RIGHT - _rfont.width(t)
	_rfont.draw(c, x, 12, t)
	_rfont.space = sp
	for xx in range(x - 2, 203):                        # the word's underline joins the row's (x >= 202)
		c.s(xx, 27, 1)


# ------------------------------------------------------------------------------------------------ drawing
func _draw() -> void:
	if not shown:
		return
	var a := 0.0                                 # black over everything
	if _phase == 0:
		a = 1.0 - float(_t) / FADE
	elif _phase == 2:
		a = float(_t) / FADE
	elif _phase == 3:
		draw_rect(Rect2(0, 0, 256, 384), Color(0, 0, 0, 1.0 - float(_t) / FADE))
		return
	draw_rect(Rect2(0, 0, 256, 384), Color.BLACK)
	if _ok:
		var off := HEX_ORIGIN + HEX_SPEED * float(_ht)
		var src := Rect2(Vector2(floorf(off.x), floorf(off.y)), Vector2(256, 192))
		draw_texture_rect_region(_hex, Rect2(0, 0, 256, 192), src)
		draw_texture_rect_region(_hex, Rect2(0, 192, 256, 192), src)
		_draw_top()
		_draw_low()
	else:
		font.draw(self, Vector2(18, 80), "ENDLESS RECORDS" if endless else "ALL-STAR RECORDS", WHITE, QoLFont.HEAVY, Color.BLACK)
		font.draw(self, Vector2(18, 100), ("Enemies %d  Time " % int(entry.get("beaten", 0)) if endless else "Clear time ") \
			+ time_text(entry.get("frames", 1)), WHITE, QoLFont.BOLD, Color.BLACK)
		font.draw(self, Vector2(18, 192 + 160), "Press A", YELLOW, QoLFont.BOLD, Color.BLACK)
	if a > 0.0:
		draw_rect(Rect2(0, 0, 256, 384), Color(0, 0, 0, a))


func _blink_on() -> bool:
	return (_t / 8) % 2 == 0


func _draw_top() -> void:
	for k in _portraits.size():
		if _portraits[k] != null:
			draw_texture(_portraits[k], Vector2(0, PORTRAIT_Y + 40 * k))
	if _upper != null:
		draw_texture(_upper, Vector2.ZERO)


func _draw_low() -> void:
	var o := 192
	var pt = _plate_top_e if endless else _plate_top
	if pt != null:
		draw_texture(pt, Vector2(0, o + TITLE_Y))
	for i in MAX:
		var y := o + ROW_Y0 + ROW_STEP * i
		var flash := i == new_rank and _blink_on() and _phase == 1
		draw_texture((_rows_hi if flash else _rows)[i], Vector2(0, y))
		if i < _row_info.size():
			draw_texture(_row_info[i], Vector2(0, y))
		if i < table.size():
			var ids: Array = table[i].ids
			for k in mini(3, ids.size()):
				if _faces.has(ids[k]):
					draw_texture(_faces[ids[k]], Vector2(FACE_X[k], y + 4))
	# OK = the results' "Character Select" plate (pressed: 1 px down-right and darker) with the results' cursor
	var bp := Vector2(0, o + BTN_Y) + (Vector2(1, 1) if _press or _phase == 2 else Vector2.ZERO)
	draw_texture(_button, bp, Color(0.8, 0.8, 0.8) if _press else Color.WHITE)
	if _phase == 1 and _blink_on() or _phase == 0:
		draw_texture(_cursor, bp)


# ------------------------------------------------------------------------------------------------ plate titles
## coverage (0..1) rows of `text` in the port's heavy capitals (QoLFont.HEAVY_GLYPHS, 10 rows stretched to 15),
## slanted IT_SLANT px per row (the bottom row unshifted): [width, Array of PackedFloat32Array]
static func italic_cov(text: String) -> Array:
	var w := 0
	for ch in text:
		w += (QoLFont.HEAVY_SPACE + 1) if not QoLFont.HEAVY_GLYPHS.has(ch) else (QoLFont.HEAVY_GLYPHS[ch][0] as String).length() + 1
	w = maxi(0, w - 1)
	var extra := int(ceil((IT_ROWS - 1) * IT_SLANT)) + 1
	var rows: Array = []
	for oy in IT_ROWS:
		var r := PackedFloat32Array()
		r.resize(w + extra)
		var off := (IT_ROWS - 1 - oy) * IT_SLANT
		var x := 0
		for ch in text:
			if not QoLFont.HEAVY_GLYPHS.has(ch):
				x += QoLFont.HEAVY_SPACE + 1
				continue
			var g: Array = QoLFont.HEAVY_GLYPHS[ch]
			var line: String = g[oy * 10 / IT_ROWS]
			for gx in line.length():
				if line[gx] == "#":
					var a := x + gx + off
					var i := int(floor(a))
					var fr := a - i
					r[i] += 1.0 - fr
					r[i + 1] += fr
			x += line.length() + 1
		rows.append(r)
	return [w + extra, rows]


static func _nib(t: PackedByteArray, w: int, x: int, y: int) -> int:
	return (t[(y * w + x) >> 1] >> (4 * (x & 1))) & 15


static func _put4(t: PackedByteArray, w: int, x: int, y: int, v: int) -> void:
	var i := (y * w + x) >> 1
	var s := 4 * (x & 1)
	t[i] = (t[i] & ~(15 << s) & 0xFF) | (v << s)


## a title plate (4-bit linear texture, `w` texels per row; the game's HI-SCORE RANKING / COURSE SELECT plates: a white
## square block at the left, then the white italic title on the plate colour `bg`, text rows top..top+14): the title
## is erased (from after the block to the plate's last `bg` column, row by row) and `text` written from the old
## title's first column on the bottom row, in the shades `levels` (bg, dark, mid, light, white). False (nothing
## changed) when the plate does not look like one or the text does not fit. (The Gamemode menu's header uses this;
## the records page now letters its plate with the plate's own capitals, plate_title(), and keeps this as fallback.)
static func retitle(t: PackedByteArray, w: int, top: int, bg: int, levels: Array, text: String) -> bool:
	if t.size() < w * (top + IT_ROWS + 1) / 2:
		return false
	var bottom := top + IT_ROWS - 1
	var starts: Array = []
	var ends: Array = []
	for y in range(top, bottom + 1):
		var x := 0
		while x < 48 and _nib(t, w, x, y) != 0xF:             # the block (a row above / below it: as its neighbour)
			x += 1
		if x < 48:
			while x < w and _nib(t, w, x, y) != bg:
				x += 1
		else:
			x = -1
		var e := w - 1
		while e > maxi(x, 0) and _nib(t, w, e, y) != bg:
			e -= 1
		starts.append(x)
		ends.append(e)
	for k in range(IT_ROWS - 2, -1, -1):
		if starts[k] < 0:
			starts[k] = starts[k + 1]
	for k in range(1, IT_ROWS):
		if starts[k] < 0:
			starts[k] = starts[k - 1]
	for k in IT_ROWS:
		if starts[k] < 0 or starts[k] >= w - 16 or ends[k] - starts[k] < 40:
			return false
	var x0: int = starts[IT_ROWS - 1]
	while x0 < ends[IT_ROWS - 1] and _nib(t, w, x0, bottom) == bg:   # the old title's first column (bottom row)
		x0 += 1
	var cov := italic_cov(text)
	for k in IT_ROWS:                                       # each row's last inked column stays 1 px off the edge
		var r: PackedFloat32Array = cov[1][k]
		var last := r.size() - 1
		while last > 0 and r[last] < 0.125:
			last -= 1
		if x0 + last > (ends[k] as int) - 1:
			return false
	for k in IT_ROWS:
		for x in range(starts[k], ends[k] + 1):
			_put4(t, w, x, top + k, bg)
		var r: PackedFloat32Array = cov[1][k]
		for i in r.size():
			var lv := clampi(int(round(r[i] * 4.0)), 0, 4)
			if lv > 0:
				_put4(t, w, x0 + i, top + k, levels[lv])
	return true
