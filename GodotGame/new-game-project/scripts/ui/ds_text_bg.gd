class_name DSTextBG
extends ColorRect
## A DS text-mode BG layer drawn from raw tile/map/palette data (see shaders/ds_textbg.gdshader).
## The map is editable at runtime (set_entry) exactly like the game writes to BG map VRAM.

var map_w: int = 32
var map_h: int = 32
var entries: PackedInt32Array = []
var _map_img: Image
var _map_tex: ImageTexture
var _dirty: bool = false


## tiles_png: L8 tile strip, pal_png: RGBA palette rows, map_bin: raw u16 map (linear map_w x map_h order)
func setup(tiles_png: String, pal_png: String, map_bin: String, bpp: int, w: int = 32, h: int = 32) -> void:
	size = Vector2(256, 192)
	map_w = w
	map_h = h
	entries.resize(w * h)
	if map_bin != "":
		var raw := Assets.bytes(map_bin)
		for i in mini(w * h, raw.size() / 2):
			entries[i] = raw[2 * i] | (raw[2 * i + 1] << 8)
	_map_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_map_tex = ImageTexture.create_from_image(_map_img)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/ds_textbg.gdshader")
	m.set_shader_parameter("tiles", Assets.texture(tiles_png))
	m.set_shader_parameter("palette", Assets.texture(pal_png))
	m.set_shader_parameter("map", _map_tex)
	m.set_shader_parameter("bpp", bpp)
	material = m
	_dirty = true
	flush()


func get_entry(x: int, y: int) -> int:
	return entries[y * map_w + x]


func set_entry(x: int, y: int, e: int) -> void:
	entries[y * map_w + x] = e
	_dirty = true


func set_scroll(x: float, y: float) -> void:
	(material as ShaderMaterial).set_shader_parameter("scroll", Vector2(x, y))


func flush() -> void:
	if not _dirty:
		return
	for i in entries.size():
		var e := entries[i]
		_map_img.set_pixel(i % map_w, i / map_w, Color8(e & 255, (e >> 8) & 255, 0, 255))
	_map_tex.update(_map_img)
	_dirty = false


# ---------------------------------------------------------------- raw VRAM-style API
## Use instead of setup() when composing a screen from raw pack members like the game does:
##   setup_raw(4); write_palette(0, pal512); write_tiles(0, nbfc); set_entry(...); flush_all()
var tiles_mem: PackedByteArray = []
var palette_mem: PackedByteArray = []
var bpp_raw: int = 4
var _tiles_img: Image
var _tiles_tex: ImageTexture
var _pal_img: Image
var _pal_tex: ImageTexture


func setup_raw(bpp: int, w: int = 32, h: int = 32, max_tiles: int = 1024) -> void:
	size = Vector2(256, 192)
	bpp_raw = bpp
	map_w = w
	map_h = h
	entries.resize(w * h)
	entries.fill(0)
	tiles_mem.resize(max_tiles * 8 * bpp)
	tiles_mem.fill(0)
	palette_mem.resize(512)
	palette_mem.fill(0)
	_map_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_map_tex = ImageTexture.create_from_image(_map_img)
	_tiles_img = Image.create(8, max_tiles * 8, false, Image.FORMAT_L8)
	_tiles_tex = ImageTexture.create_from_image(_tiles_img)
	_pal_img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	_pal_tex = ImageTexture.create_from_image(_pal_img)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/ds_textbg.gdshader")
	m.set_shader_parameter("tiles", _tiles_tex)
	m.set_shader_parameter("palette", _pal_tex)
	m.set_shader_parameter("map", _map_tex)
	m.set_shader_parameter("bpp", bpp)
	material = m


## copy raw character data (nbfc) to tile index `tile`
func write_tiles(tile: int, data: PackedByteArray) -> void:
	var off := tile * 8 * bpp_raw
	for i in mini(data.size(), tiles_mem.size() - off):
		tiles_mem[off + i] = data[i]


## copy raw BGR555 palette bytes starting at 16-colour row `row`
func write_palette(row: int, data: PackedByteArray) -> void:
	var off := row * 32
	for i in mini(data.size(), 512 - off):
		palette_mem[off + i] = data[i]


## place a raw map (nbfs, w_src tiles wide) at (x0, y0), adding `add` to every entry (tile base / palette bits)
func blit_map(data: PackedByteArray, w_src: int, x0: int, y0: int, cols: int = -1, rows: int = -1, add: int = 0) -> void:
	var h_src := data.size() / 2 / w_src
	if cols < 0: cols = w_src
	if rows < 0: rows = h_src
	for y in rows:
		for x in cols:
			var i := (y * w_src + x) * 2
			if i + 1 >= data.size(): continue
			var e := data[i] | (data[i + 1] << 8)
			var tx := x0 + x
			var ty := y0 + y
			if tx < map_w and ty < map_h:
				entries[ty * map_w + tx] = e + add
	_dirty = true


func flush_all() -> void:
	# tiles
	var n := tiles_mem.size() / (8 * bpp_raw)
	for t in n:
		for y in 8:
			for x in 8:
				var v: int
				if bpp_raw == 4:
					var b := tiles_mem[t * 32 + y * 4 + (x >> 1)]
					v = (b >> 4) if (x & 1) else (b & 15)
				else:
					v = tiles_mem[t * 64 + y * 8 + x]
				_tiles_img.set_pixel(x, t * 8 + y, Color8(v, v, v))
	_tiles_tex.update(_tiles_img)
	# palette
	for i in 256:
		var c := palette_mem[2 * i] | (palette_mem[2 * i + 1] << 8)
		_pal_img.set_pixel(i & 15, i >> 4, Color8((c & 31) * 255 / 31, ((c >> 5) & 31) * 255 / 31, ((c >> 10) & 31) * 255 / 31))
	_pal_tex.update(_pal_img)
	_dirty = true
	flush()
