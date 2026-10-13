extends Node
## Loads converted ROM assets (autoload "Assets").
##
## Assets are produced by decomp/tools/build_all.py into GodotGame/new-game-project/assets/.
## That folder contains a .gdignore so the editor never re-imports/compresses them: every PNG is
## loaded at runtime with exact pixels (palette-index atlases must not be filtered or compressed).
## In an exported build the same folder is expected next to the executable (assets/).

var base_dir: String = ""
var _json_cache: Dictionary = {}
var _tex_cache: Dictionary = {}
var _img_cache: Dictionary = {}


func _ready() -> void:
	if OS.has_feature("editor") or not OS.has_feature("template"):
		base_dir = ProjectSettings.globalize_path("res://assets")
	else:
		base_dir = OS.get_executable_path().get_base_dir().path_join("assets")
	if Game.args.has("assets"):
		base_dir = String(Game.args["assets"])
	if not DirAccess.dir_exists_absolute(base_dir):
		# only the older hand-built scenes use converted assets; the game itself reads the ROM
		print_verbose("Assets folder not found: %s  (decomp/tools/build_all.py)" % base_dir)


func path(rel: String) -> String:
	return base_dir.path_join(rel)


func exists(rel: String) -> bool:
	return FileAccess.file_exists(path(rel))


func json(rel: String) -> Variant:
	if _json_cache.has(rel):
		return _json_cache[rel]
	var f := FileAccess.open(path(rel), FileAccess.READ)
	if f == null:
		push_error("missing asset " + rel)
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	_json_cache[rel] = data
	return data


func bytes(rel: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path(rel))


func image(rel: String) -> Image:
	if _img_cache.has(rel):
		return _img_cache[rel]
	var img := Image.load_from_file(path(rel))
	if img == null:
		push_error("missing image " + rel)
		img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
	_img_cache[rel] = img
	return img


func texture(rel: String) -> ImageTexture:
	if _tex_cache.has(rel):
		return _tex_cache[rel]
	var t := ImageTexture.create_from_image(image(rel))
	_tex_cache[rel] = t
	return t


## The game ROM is never part of the port: the player supplies their own copy of the European cartridge.
## Exported game: any file in the executable's folder (any name or extension) whose contents prove it is that
## ROM. Editor / repository: `nds=PATH`, else baseroms/. Read-only; never written.
const ROM_TITLE := "DRAGONBALLZ2"
const ROM_CODE := "ADBP"                                   ## game code of the European release (what was translated)
const ROM_HEADER_CRC := 0x53C2                             ## header CRC16 (0x15E) of that release
const ROM_ARM9_MD5 := "c859f91bcb9a8eac02cecafe3dd19703"   ## ARM9 binary after its 2 KiB secure-area header
const ROM_ARM7_MD5 := "9f883c56e47c5d0861c804b293723256"   ## ARM7 binary
var rom_path: String = ""                ## the file the game was read from
var rom_rejected: PackedStringArray = []  ## "<file>: <reason>" for candidates that are not this ROM
var rom_folder: String = ""              ## where the ROM is looked for (shown when none is found)


func rom_bytes() -> PackedByteArray:
	rom_rejected.clear()
	for p in _rom_files():
		var head := _head(p)
		if head.size() < 0x200 or head.slice(0, 12).get_string_from_ascii() != ROM_TITLE:
			continue   # some other file: not mentioned
		var b := FileAccess.get_file_as_bytes(p)
		var why := rom_problem(b)
		if why == "":
			rom_path = p
			return b
		rom_rejected.append("%s: %s" % [p.get_file(), why])
	return PackedByteArray()


## "" when `b` is the European Supersonic Warriors 2 ROM this port was made from (trimmed dumps and any file name
## are fine), else why not.
static func rom_problem(b: PackedByteArray) -> String:
	if b.size() < 0x200:
		return "too small"
	var code := b.slice(0xC, 0x10).get_string_from_ascii()
	if code != ROM_CODE:
		var region: String = {"ADBE": "US", "ADBJ": "Japanese"}.get(code, "another")
		return "%s version (game code %s); this port needs the European ROM (%s)" % [region, code, ROM_CODE]
	var crc := 0xFFFF   # CRC-16/MODBUS over the header, as stored at 0x15E
	for i in 0x15E:
		crc ^= b[i]
		for k in 8:
			crc = (crc >> 1) ^ 0xA001 if (crc & 1) != 0 else crc >> 1
	if crc != b.decode_u16(0x15E) or crc != ROM_HEADER_CRC:
		return "damaged or modified header"
	var o9 := b.decode_u32(0x20)
	var s9 := b.decode_u32(0x2C)
	var o7 := b.decode_u32(0x30)
	var s7 := b.decode_u32(0x3C)
	if o9 + s9 > b.size() or o7 + s7 > b.size():
		return "file is cut short"
	if _md5(b.slice(o9 + 0x800, o9 + s9)) != ROM_ARM9_MD5 or _md5(b.slice(o7, o7 + s7)) != ROM_ARM7_MD5:
		return "different revision or modified program code"
	return ""


static func _md5(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(b)
	return h.finish().hex_encode()


static func _head(p: String) -> PackedByteArray:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null or f.get_length() < 0x200 or f.get_length() > 0x20000000:
		return PackedByteArray()
	return f.get_buffer(0x200)


## Candidate ROM files: `nds=` first; exported game: every file in the executable's folder; editor: baseroms/,
## else finished/.
func _rom_files() -> PackedStringArray:
	var out := PackedStringArray()
	if Game.args.has("nds"):
		out.append(String(Game.args["nds"]))
	var dir := ProjectSettings.globalize_path("res://").path_join("../../baseroms").simplify_path()
	if not DirAccess.dir_exists_absolute(dir):   # part 21: the user keeps the ROM only in finished/ (next to the exe)
		dir = ProjectSettings.globalize_path("res://").path_join("../../finished").simplify_path()
	if not OS.has_feature("editor") and OS.has_feature("template"):
		dir = OS.get_executable_path().get_base_dir()
	rom_folder = dir
	var d := DirAccess.open(dir)
	if d:
		var files := d.get_files()
		files.sort()
		for f in files:
			if not f.get_extension().to_lower() in ["exe", "dll", "so", "pck", "sav", "txt", "md", "x86_64"]:
				out.append(dir.path_join(f))
	return out


## Save memory: `user_path` (the port's own save, written by the game) or, the first time, the completed save
## (everything unlocked): 100Save/ in the repository, else the copy exported inside the game
## (res://data/save100.sav, copied from 100Save/ by build_all.py). A save holds the player's progress, not game
## content. The originals are never modified.
const SAVE_SIZE := 8192                           ## 8 KiB EEPROM (DATA_NOTES "Save")
const BUILTIN_SAVE := "res://data/save100.sav"


func save_bytes(user_path: String) -> PackedByteArray:
	if FileAccess.file_exists(user_path):
		var b := FileAccess.get_file_as_bytes(user_path)
		if b.size() == SAVE_SIZE and b.slice(0, 4).get_string_from_ascii() == "DBZ2":   # else damaged: reseed
			return b
	var cands := _rom_candidates("sav", ["100Save"])
	cands.append(BUILTIN_SAVE)
	for p in cands:
		if FileAccess.file_exists(p):
			var b := FileAccess.get_file_as_bytes(p)
			if b.size() >= SAVE_SIZE:
				return b.slice(0, SAVE_SIZE)
	return PackedByteArray()


func _rom_candidates(ext: String, folders: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if Game.args.has(ext):
		out.append(String(Game.args[ext]))
	for folder in folders:
		var root := ProjectSettings.globalize_path("res://").path_join("../..").path_join(folder)
		var d := DirAccess.open(root)
		if d and not OS.has_feature("template"):   # repository layout only
			for f in d.get_files():
				if f.get_extension().to_lower() == ext:
					out.append(root.path_join(f))
	return out
