class_name CharData
extends RefCounted
## Everything converted for one character code (e.g. "gkn"): sprite atlas, palettes, frame info and
## the behaviour bytecode chunk. Produced by decomp/tools/convert_chara.py.

var code: String
var script_bin: PackedByteArray          ## raw 'c' chunk (VM bytecode + tables), offsets are chunk-relative
var script_base: int = 0                 ## chunk offset of the action bytecode area (header +0x0C)
var actions: PackedInt32Array = []       ## action id -> offset relative to script_base
var frames: Array = []                   ## frame id -> {image, origin:[x,y], boxes:[[x,y,w,h,kind],...]}
var images: Array = []                   ## image id -> {crop:[x,y,w,h], atlas:[x,y,w,h]}
var atlas: Texture2D                     ## L8: palette index per pixel
var palette: Texture2D                   ## 16x16 RGBA: row = sub-palette

static var _cache: Dictionary = {}


static func load_code(c: String) -> CharData:
	if _cache.has(c):
		return _cache[c]
	var d := CharData.new()
	d.code = c
	var dir := "chara/" + c + "/"
	d.script_bin = Assets.bytes(dir + "script.bin")
	var sj: Dictionary = Assets.json(dir + "script.json")
	var h: Dictionary = sj["header"]
	d.script_base = int(h["script_base"])
	for a in h["actions"]:
		d.actions.append(int(a))
	d.frames = (Assets.json(dir + "frames.json") as Dictionary)["frames"]
	d.images = (Assets.json(dir + "images.json") as Dictionary)["images"]
	d.atlas = Assets.texture(dir + "atlas.png")
	d.palette = Assets.texture(dir + "palette.png")
	_cache[c] = d
	return d


func u8(off: int) -> int:
	return script_bin[off]


func u16(off: int) -> int:
	return script_bin[off] | (script_bin[off + 1] << 8)


func s16(off: int) -> int:
	var v := u16(off)
	return v - 0x10000 if v >= 0x8000 else v


func u32(off: int) -> int:
	return script_bin[off] | (script_bin[off + 1] << 8) | (script_bin[off + 2] << 16) | (script_bin[off + 3] << 24)


func action_offset(action_id: int) -> int:
	## chunk-relative start offset of an action (where its op 0x00 header sits)
	return script_base + actions[action_id]
