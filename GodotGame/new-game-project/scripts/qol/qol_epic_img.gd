class_name QoLEpicImg
extends RefCounted
## EPIC MODE, part 23: text that the game only has as pictures (Data File pages, the Data File help panels, the
## Data File touch-screen items, the staff credits) rewritten when the game loads the picture (QoLGame's
## FUN_02009B28 hook: one member of a resource pack into a RAM buffer, before it reaches VRAM).
## Nothing from the ROM is stored here. The text is READ from the picture at run time (glyph shapes are matched
## against reference glyphs cut at run time out of the player's ROM, at the coordinates in DF_REFS / CR_REFS: my own
## table of where one sample of each letter sits), rewritten by QoLEpic's rules, and drawn back with the same glyphs
## (missing ones from the game's text font, font_eu), in the original colours, positions and box widths. The help
## panels get hand-written text (QoLEpic.HELP_TEXT). Findings: DATA_NOTES "part 23 findings (text)".

const CREDITS_TABLE := 0x020E1570    ## u32 -> the credits pictures table (FUN_02087678)
const SLOT := 15                      ## text line spacing of the Data File description boxes (px)
var core                              ## the QoLGame (RAM: core.M, core.BASE)
var epic: QoLEpic
var rom := PackedByteArray()
var dbg := false
var _packs := {}                      ## ROM path -> {"f": Vector2i, "hs": int, "n": int, "names": {name: index}}
var _df := {}                         ## Data File font: {"keys": {key: label}, "glyphs": {label: glyph}}
var _cr := {}                         ## credits font
var _eu := {}                         ## font_eu glyphs {char: glyph} (fallback)
var _chars := {}                      ## pack handle -> [member, address, size] of the last .nbfc load


func _init(c, e: QoLEpic, r: PackedByteArray) -> void:
	core = c
	epic = e
	rom = r


# ------------------------------------------------------------------------------------------------ ROM packs
func _pack(path: String) -> Dictionary:
	if _packs.has(path):
		return _packs[path]
	var p := path.trim_prefix("/")
	if p.begins_with("Romdata/"):
		p = "romdata/" + p.substr(8)
	var f := QoLFont.nitro_file(rom, p)
	var d := {}
	if f.x >= 0 and rom[f.x] in [3, 4]:
		var n := rom.decode_u16(f.x + 2)
		var names := {}
		for i in n:
			var e := f.x + 8 + i * 0x4C
			var nm := rom.slice(e, e + 64).get_string_from_ascii().replace("\\", "/")
			names[nm.get_file()] = i
		d = {"f": f, "hs": rom.decode_u32(f.x + 4), "n": n, "names": names, "list": names.keys()}
	_packs[path] = d
	return d


func member_name(path: String, i: int) -> String:
	var d := _pack(path)
	if d.is_empty() or i >= int(d["n"]):
		return ""
	var e: int = d["f"].x + 8 + i * 0x4C
	return rom.slice(e, e + 64).get_string_from_ascii().replace("\\", "/").get_file()


func member(path: String, name: String) -> PackedByteArray:
	var d := _pack(path)
	if d.is_empty() or not d["names"].has(name):
		return PackedByteArray()
	var e: int = d["f"].x + 8 + int(d["names"][name]) * 0x4C
	var us := rom.decode_u32(e + 64)
	var ss := rom.decode_u32(e + 68)
	var a: int = d["f"].x + int(d["hs"]) + rom.decode_u32(e + 72)
	var raw := rom.slice(a, a + ss)
	if ss == us:
		return raw
	return _decompress(raw, us)


static func _decompress(src: PackedByteArray, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	var o := 0
	var i := 4
	if src[0] == 0x30:
		while o < n and i < src.size():
			var flag := src[i]
			i += 1
			if flag & 0x80:
				var cnt := (flag & 0x7F) + 3
				for k in cnt:
					if o < n:
						out[o] = src[i]
						o += 1
				i += 1
			else:
				var cnt2 := (flag & 0x7F) + 1
				for k in cnt2:
					if o < n:
						out[o] = src[i + k]
						o += 1
				i += cnt2
	elif src[0] == 0x10:
		while o < n and i < src.size():
			var flags := src[i]
			i += 1
			for b in 8:
				if o >= n or i >= src.size():
					break
				if flags & (0x80 >> b):
					var disp := ((src[i] & 0xF) << 8 | src[i + 1]) + 1
					var cnt := (src[i] >> 4) + 3
					i += 2
					for k in cnt:
						if o < n:
							out[o] = out[o - disp]
							o += 1
				else:
					out[o] = src[i]
					o += 1
					i += 1
	return out


# ------------------------------------------------------------------------------------------------ bitmaps
## 4bpp texture (256 wide) -> one byte per pixel
static func tex4_to_px(d: PackedByteArray) -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(d.size() * 2)
	for i in d.size():
		px[i * 2] = d[i] & 15
		px[i * 2 + 1] = d[i] >> 4
	return px


static func px_to_tex4(px: PackedByteArray) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(px.size() / 2)
	for i in d.size():
		d[i] = px[i * 2] | (px[i * 2 + 1] << 4)
	return d


## BG picture (4bpp tiles + 32-wide screen map) -> pixels (256 x rows*8)
static func bg_to_px(chars: PackedByteArray, map: PackedByteArray) -> PackedByteArray:
	var rows := map.size() / 64
	var px := PackedByteArray()
	px.resize(256 * rows * 8)
	for ty in rows:
		for tx in 32:
			var e := map.decode_u16((ty * 32 + tx) * 2)
			var t := e & 0x3FF
			var hf := (e >> 10) & 1
			var vf := (e >> 11) & 1
			for y in 8:
				for x in 8:
					var o := t * 32 + y * 4 + (x >> 1)
					var v := 0
					if o < chars.size():
						v = (chars[o] >> ((x & 1) * 4)) & 15
					var X := tx * 8 + (7 - x if hf else x)
					var Y := ty * 8 + (7 - y if vf else y)
					px[Y * 256 + X] = v
	return px


# ------------------------------------------------------------------------------------------------ OCR
## connected glyph pieces of colour `ink` (8-neighbours) no larger than 13x13 whose 1-pixel frame holds one other
## colour only (the background): [x0, y0, x1, y1, bg, points (PackedInt32Array of y*w+x)]
static func components(px: PackedByteArray, w: int, h: int, ink: int, y_from := 0, y_to := -1, lim := 12) -> Array:
	if y_to < 0:
		y_to = h
	var seen := PackedByteArray()
	seen.resize(w * h)
	var out: Array = []
	var stack := PackedInt32Array()
	for y in range(y_from, y_to):
		for x in w:
			var i := y * w + x
			if px[i] != ink or seen[i]:
				continue
			seen[i] = 1
			stack.clear()
			stack.append(i)
			var pts := PackedInt32Array()
			var x0 := x
			var x1 := x
			var y0 := y
			var y1 := y
			while not stack.is_empty():
				var p := stack[stack.size() - 1]
				stack.remove_at(stack.size() - 1)
				pts.append(p)
				var px_ := p % w
				var py := p / w
				x0 = mini(x0, px_)
				x1 = maxi(x1, px_)
				y0 = mini(y0, py)
				y1 = maxi(y1, py)
				for dy in [-1, 0, 1]:
					var v: int = py + dy
					if v < y_from or v >= y_to:
						continue
					for dx in [-1, 0, 1]:
						var u: int = px_ + dx
						if u < 0 or u >= w:
							continue
						var q := v * w + u
						if not seen[q] and px[q] == ink:
							seen[q] = 1
							stack.append(q)
			if x1 - x0 > lim or y1 - y0 > lim:
				continue
			var bg := -1
			var ok := true
			for v in range(maxi(y_from, y0 - 1), mini(y_to, y1 + 2)):
				for u in range(maxi(0, x0 - 1), mini(w, x1 + 2)):
					var c := px[v * w + u]
					if c == ink:
						continue
					if bg < 0:
						bg = c
					elif c != bg:
						ok = false
			if ok and bg >= 0:
				out.append([x0, y0, x1, y1, bg, pts])
	return out


## pieces -> text lines (vertical overlap, in the order of their tops) -> glyphs (pieces overlapping in columns)
static func lines_of(comps: Array) -> Array:
	var cs := comps.duplicate()
	cs.sort_custom(func(a, b): return a[1] < b[1])
	var L: Array = []
	for c in cs:
		var put := false
		for l in L:
			if not (c[3] < l["y0"] - 1 or c[1] > l["y1"] + 1):
				l["c"].append(c)
				l["y0"] = mini(l["y0"], c[1])
				l["y1"] = maxi(l["y1"], c[3])
				put = true
				break
		if not put:
			L.append({"y0": c[1], "y1": c[3], "c": [c]})
	for l in L:
		var lc: Array = l["c"]
		lc.sort_custom(func(a, b): return a[0] < b[0])
		var G: Array = []
		for c in lc:
			if not G.is_empty() and c[0] <= G[G.size() - 1]["x1"]:
				var g: Dictionary = G[G.size() - 1]
				g["pts"].append_array(c[5])
				g["x1"] = maxi(g["x1"], c[2])
				g["y0"] = mini(g["y0"], c[1])
				g["y1"] = maxi(g["y1"], c[3])
			else:
				G.append({"x0": c[0], "x1": c[2], "y0": c[1], "y1": c[3], "pts": PackedInt32Array(c[5]), "bg": c[4]})
		l["g"] = G
		var cnt := {}
		var best := -1
		var base := 0
		for g in G:
			cnt[g["y1"]] = int(cnt.get(g["y1"], 0)) + 1
			if cnt[g["y1"]] > best:
				best = cnt[g["y1"]]
				base = g["y1"]
		l["base"] = base
	return L


static func glyph_key(g: Dictionary, base: int, w: int) -> String:
	var gw: int = g["x1"] - g["x0"] + 1
	var gh: int = g["y1"] - g["y0"] + 1
	var bits := PackedByteArray()
	bits.resize(gw * gh)
	bits.fill(48)
	for p in g["pts"]:
		bits[(p / w - g["y0"]) * gw + (p % w - g["x0"])] = 49
	return "%d,%d,%d,%s" % [gw, gh, base - g["y1"], bits.get_string_from_ascii()]


## text runs of one line: [{x0, x1, base, ink, bg, lg, text, gl: [[glyph, label]]}]; `mono` = credits spacing
static func runs_of(l: Dictionary, ink: int, keys: Dictionary, w: int, split_gap: int, mono: bool) -> Array:
	var out: Array = []
	var cur = null
	var cut_next := false
	for g in l["g"]:
		var lab: String = keys.get(glyph_key(g, l["base"], w), "~")
		if lab == "~":
			if cur != null:
				cur["cut"] = true
				out.append(cur)
			cur = null
			cut_next = true
			continue
		if cur != null and (g["x0"] - cur["x1"] - 1 > split_gap or g["bg"] != cur["bg"]):
			out.append(cur)
			cur = null
		if cur == null:
			cur = {"x0": g["x0"], "x1": g["x1"], "base": l["base"], "ink": ink, "bg": g["bg"], "gl": [[g, lab]],
				"y0": g["y0"], "y1": g["y1"], "cut": cut_next}
			cut_next = false
		else:
			cur["gl"].append([g, lab])
			cur["x1"] = g["x1"]
			cur["y0"] = mini(cur["y0"], g["y0"])
			cur["y1"] = maxi(cur["y1"], g["y1"])
	if cur != null:
		out.append(cur)
	for r in out:
		var gl: Array = r["gl"]
		var gaps: Array = []
		for i in range(1, gl.size()):
			gaps.append(gl[i][0]["x0"] - gl[i - 1][0]["x1"] - 1)
		var cnt := {}
		var lg := 1
		var best := -1
		for gp in gaps:
			cnt[gp] = int(cnt.get(gp, 0)) + 1
			if cnt[gp] > best:
				best = cnt[gp]
				lg = gp
		lg = mini(maxi(lg, 0), 2)
		r["lg"] = lg
		var sps: Array = []
		for gp in gaps:
			if gp >= lg + 3:
				sps.append(gp)
		r["sp"] = sps[sps.size() / 2] if not sps.is_empty() else lg + 3
		var s: String = gl[0][1]
		for i in range(1, gl.size()):
			if mono:
				var c0: float = (gl[i - 1][0]["x0"] + gl[i - 1][0]["x1"]) / 2.0
				var c1: float = (gl[i][0]["x0"] + gl[i][0]["x1"]) / 2.0
				s += " ".repeat(maxi(0, roundi((c1 - c0) / 6.0) - 1))
			else:
				var nar: bool = gl[i - 1][1] in ["l", "i", "I", "j", "!", ".", ",", "'", "1"] or gl[i][1] in ["l", "i", "I", "j", "!", ".", ",", "'", "1"]
				if gaps[i - 1] >= lg + 2 + (1 if nar else 0):
					s += " "
			s += gl[i][1]
		r["text"] = _fix_i(s).replace("fight ing", "fighting").replace("Fr ieza", "Frieza").replace("#1 6", "#16").replace("#1 7", "#17").replace("#1 8", "#18")
	return out


## the fonts draw I and l alike: a word starting "l" + consonant, or inside capitals, is an I
static func _fix_i(s: String) -> String:
	var words := s.split(" ")
	for k in words.size():
		var w: String = words[k]
		if w.length() >= 2 and w[0] == "l" and w[1] in ["n", "s", "t", "w", "c", "f", "N", "S", "T", "C", "F"]:
			w = "I" + w.substr(1)
		var up := 0
		for ch in w:
			if ch >= "A" and ch <= "Z":
				up += 1
		if up >= 2 and up >= w.length() / 2:
			w = w.replace("l", "I")
		if w == "l":
			w = "I"
		words[k] = w
	return " ".join(words)


# ------------------------------------------------------------------------------------------------ fonts
## reference glyphs: each table row [member, x0, y0, w, h, dy, ink, label, uses] cut out of the ROM picture
func _font(refs: Array, pack: String, bg_pics: bool) -> Dictionary:
	var keys := {}
	var glyphs := {}
	var uses := {}
	var pics := {}
	var prev_tm := []
	for r in refs:
		var mname: String = r[0]
		if not pics.has(mname):
			if bg_pics:
				var base := mname.get_basename()
				pics[mname] = bg_to_px(member(pack, mname), member(pack, base + ".nbfs"))
			else:
				pics[mname] = tex4_to_px(member(pack, mname))
		var px: PackedByteArray = pics[mname]
		var x0: int = r[1]
		var y0: int = r[2]
		var gw: int = r[3]
		var gh: int = r[4]
		var bits := PackedByteArray()
		bits.resize(gw * gh)
		var ok := true
		for y in gh:
			for x in gw:
				var i := (y0 + y) * 256 + x0 + x
				if i >= px.size():
					ok = false
					break
				bits[y * gw + x] = 49 if px[i] == int(r[6]) else 48
		if not ok:
			continue
		var key := "%d,%d,%d,%s" % [gw, gh, int(r[5]), bits.get_string_from_ascii()]
		var lab: String = r[7]
		keys[key] = lab
		var g := {"w": gw, "h": gh, "dy": int(r[5]), "bits": bits}
		if lab == "" and not prev_tm.is_empty() and prev_tm[0] == mname:
			# second piece of a two-piece mark (TM): joined to the first one
			var t: Dictionary = glyphs.get("™", {})
			if not t.is_empty() and not t.has("joined"):
				glyphs["™"] = _join(t, prev_tm[1], prev_tm[2], g, x0, y0)
		if lab == "™":
			prev_tm = [mname, x0, y0]
		if lab.length() == 1 and lab != "~" and int(r[8]) > int(uses.get(lab, -1)):
			uses[lab] = int(r[8])
			glyphs[lab] = g
	return {"keys": keys, "glyphs": glyphs}


static func _join(a: Dictionary, ax: int, ay: int, b: Dictionary, bx: int, by: int) -> Dictionary:
	var x0 := mini(ax, bx)
	var y0 := mini(ay, by)
	var x1 := maxi(ax + a["w"], bx + b["w"])
	var y1 := maxi(ay + a["h"], by + b["h"])
	var bits := PackedByteArray()
	bits.resize((x1 - x0) * (y1 - y0))
	bits.fill(48)
	for part in [[a, ax, ay], [b, bx, by]]:
		var g: Dictionary = part[0]
		for y in g["h"]:
			for x in g["w"]:
				if g["bits"][y * g["w"] + x] == 49:
					bits[(part[2] - y0 + y) * (x1 - x0) + part[1] - x0 + x] = 49
	# baseline: the first piece's bottom sits dy above it
	var bottom_a: int = ay + a["h"] - 1
	return {"w": x1 - x0, "h": y1 - y0, "dy": a["dy"] + (y1 - 1 - bottom_a) * -1, "bits": bits, "joined": true}


## font_eu (the game's text font) glyphs trimmed to their ink: fallback for letters a picture font lacks
func _eu_glyph(ch: String) -> Dictionary:
	if _eu.is_empty():
		var cells := QoLFont._rom_cells(rom)
		for k in cells.size():
			var cell: PackedByteArray = cells[k]
			var cx0 := 9
			var cx1 := -1
			var cy0 := 15
			var cy1 := -1
			for y in 15:
				for x in 9:
					if cell[y * 9 + x]:
						cx0 = mini(cx0, x)
						cx1 = maxi(cx1, x)
						cy0 = mini(cy0, y)
						cy1 = maxi(cy1, y)
			if cx1 < 0:
				continue
			var gw := cx1 - cx0 + 1
			var gh := cy1 - cy0 + 1
			var bits := PackedByteArray()
			bits.resize(gw * gh)
			for y in gh:
				for x in gw:
					bits[y * gw + x] = 49 if cell[(cy0 + y) * 9 + cx0 + x] else 48
			_eu[String.chr(0x21 + k)] = {"w": gw, "h": gh, "dy": 12 - cy1, "bits": bits}
	return _eu.get(ch, {})


func _glyph(font: Dictionary, ch: String) -> Dictionary:
	if ch == "I" and not font["glyphs"].has("I"):
		ch = "l"
	if font["glyphs"].has(ch):
		return font["glyphs"][ch]
	if ch == "0" and font["glyphs"].has("O"):
		return font["glyphs"]["O"]
	return _eu_glyph(ch)


func text_width(font: Dictionary, s: String, lg: int, space: int) -> int:
	var w := 0
	for i in s.length():
		var ch := s[i]
		if ch == " ":
			w += space
			continue
		var g := _glyph(font, ch)
		w += (int(g["w"]) if not g.is_empty() else 4) + (lg if i < s.length() - 1 else 0)
	return w


## draws `s` with its first glyph's left edge at x and the baseline at `base`
func draw_text(px: PackedByteArray, w: int, h: int, font: Dictionary, s: String, x: int, base: int, ink: int, lg: int, space: int) -> void:
	for i in s.length():
		var ch := s[i]
		if ch == " ":
			x += space
			continue
		var g := _glyph(font, ch)
		if g.is_empty():
			x += 4
			continue
		var gw: int = g["w"]
		var gh: int = g["h"]
		var top: int = base - int(g["dy"]) - gh + 1
		var bits: PackedByteArray = g["bits"]
		for y in gh:
			for xx in gw:
				if bits[y * gw + xx] == 49:
					var X := x + xx
					var Y := top + y
					if X >= 0 and X < w and Y >= 0 and Y < h:
						px[Y * w + X] = ink
		x += gw + lg


## moves the block of non-background columns that starts after x (rows y0..y1) left by d pixels
static func _shift_left(px: PackedByteArray, w: int, x: int, y0: int, y1: int, bg: int, d: int) -> void:
	if d <= 0:
		return
	var a := x
	while a < w and _col_bg(px, w, a, y0, y1, bg):
		a += 1
	var b := a
	var empty := 0
	while b < w and empty < 4:
		empty = empty + 1 if _col_bg(px, w, b, y0, y1, bg) else 0
		b += 1
	b -= empty
	for xx in range(a, b):
		for y in range(y0, y1 + 1):
			px[y * w + xx - d] = px[y * w + xx]
			px[y * w + xx] = bg


static func _col_bg(px: PackedByteArray, w: int, x: int, y0: int, y1: int, bg: int) -> bool:
	for y in range(y0, y1 + 1):
		if px[y * w + x] != bg:
			return false
	return true


static func erase_run(px: PackedByteArray, r: Dictionary) -> void:
	for gl in r["gl"]:
		for p in gl[0]["pts"]:
			px[p] = r["bg"]


## free pixels right of a run: first column after x1 (rows y0..y1) holding something else than the background
static func free_right(px: PackedByteArray, w: int, r: Dictionary, y0: int, y1: int) -> int:
	var x: int = r["x1"] + 1
	while x < w:
		for y in range(y0, y1 + 1):
			if px[y * w + x] != r["bg"] and px[y * w + x] != r["ink"]:
				return x
		x += 1
	return w


static func area_free(px: PackedByteArray, w: int, x0: int, x1: int, y0: int, y1: int, bg: int) -> bool:
	if x0 < 0 or y0 < 0 or x1 >= w or y1 * w >= px.size():
		return false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if px[y * w + x] != bg:
				return false
	return true


# ------------------------------------------------------------------------------------------------ entry
## called after FUN_02009B28 loaded member `idx` of the pack at ROM path `path` into RAM [addr, addr+size)
func loaded(path: String, handle: int, idx: int, addr: int, size: int) -> void:
	var name := member_name(path, idx)
	if name == "":
		return
	if path.ends_with("DataModeDataImage_EN.bin") and name.ends_with(".ntft"):
		if name.contains("_face"):
			return
		_data_page(name, addr, size)
	elif path.ends_with("HelpEU.bin") and name.ends_with("_US.ntft"):
		_help(name, addr, size)
	elif path.ends_with("CreditRollEU.bin") or path.ends_with("DataSubScrEU.bin"):
		if name.ends_with(".nbfc"):
			_chars[handle] = [idx, addr, size, name]
		elif name.ends_with(".nbfs") and _chars.has(handle) and _chars[handle][0] == idx - 2:
			var c: Array = _chars[handle]
			_chars.erase(handle)
			if path.ends_with("CreditRollEU.bin"):
				_credits(c[3], c[1], c[2], addr, size)
			elif name.contains("US"):
				_subscr(c[3], c[1], c[2], addr, size)


func _ram(addr: int, size: int) -> PackedByteArray:
	return core.M.slice(addr - core.BASE, addr - core.BASE + size)


func _put(addr: int, d: PackedByteArray) -> void:
	var o: int = addr - core.BASE
	for i in d.size():
		core.M[o + i] = d[i]


# ------------------------------------------------------------------------------------------------ Data File pages
func _data_page(name: String, addr: int, size: int) -> void:
	if not _df.has("keys"):
		_df.merge(_font(QoLEpicRefs.DF_REFS, "/Romdata/data/DataModeDataImage_EN.bin", false))
	var tex := _ram(addr, size)
	var px := tex4_to_px(tex)
	var w := 256
	var h := px.size() / w
	var changed := false
	if name.contains("_name"):
		changed = _name_suffix(px, w, h, name)
	else:
		var runs: Array = []
		for ink in [15, 1]:
			for l in lines_of(components(px, w, h, ink)):
				for r in runs_of(l, ink, _df["keys"], w, 12, false):
					var letters := 0
					for ch in str(r["text"]):
						if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
							letters += 1
					if letters >= 2:
						runs.append(r)
		# description paragraphs: same colours and left edge, one SLOT apart
		runs.sort_custom(func(a, b): return a["base"] < b["base"] if a["base"] != b["base"] else a["x0"] < b["x0"])
		var used := {}
		for i in runs.size():
			if used.has(i):
				continue
			var para: Array = [runs[i]]
			used[i] = true
			for j in range(i + 1, runs.size()):
				var last: Dictionary = para[para.size() - 1]
				var r: Dictionary = runs[j]
				if not used.has(j) and r["ink"] == last["ink"] and r["bg"] == last["bg"] and absi(r["x0"] - last["x0"]) <= 2 and r["base"] - last["base"] == SLOT:
					para.append(r)
					used[j] = true
			if _df_rewrite(px, w, h, para, name):
				changed = true
		if _tabs(px, w, h, name):
			changed = true
	if changed:
		_put(addr, px_to_tex4(px))


## one Data File text: a move / ability name (white on black), an input line, or a description paragraph
func _df_rewrite(px: PackedByteArray, w: int, h: int, para: Array, name: String) -> bool:
	var first: Dictionary = para[0]
	var text := ""
	for r in para:
		text += (" " if text != "" else "") + str(r["text"])
	var lg: int = first["lg"]
	var space := lg + 3
	var maxw := 999
	for r in para:
		maxw = mini(maxw, free_right(px, w, r, r["y0"], r["y1"]) - 3 - int(r["x0"]))
	var kind := "desc"
	if first["ink"] == 15:
		kind = "name"
	elif name.contains("_ex") and para.size() == 1:
		kind = "input"
	elif name.contains("_team"):
		kind = "name"
	var max_lines := para.size()
	if kind == "desc":
		var last: Dictionary = para[para.size() - 1]
		if area_free(px, w, int(first["x0"]), int(first["x0"]) + maxw, int(last["base"]) + 3, int(last["base"]) + SLOT + 2, int(first["bg"])):
			max_lines += 1
	var cands: Array = epic.picture_text(text, kind)
	for c in cands:
		var lines := _wrap(_df, str(c), maxw, max_lines, lg, space)
		if lines.is_empty():
			continue
		for r in para:
			erase_run(px, r)
		for k in lines.size():
			draw_text(px, w, h, _df, lines[k], first["x0"], int(first["base"]) + k * SLOT, first["ink"], lg, space)
		if kind == "input":
			# the button icons follow the text: move them up to the new text's end
			var nx1: int = int(first["x0"]) + text_width(_df, lines[0], lg, space) - 1
			_shift_left(px, w, int(first["x1"]) + 1, int(first["y0"]) - 1, int(first["y1"]) + 1, int(first["bg"]), int(first["x1"]) - nx1)
		if dbg:
			print("EPIC img %s: %s => %s" % [name, text, " / ".join(PackedStringArray(lines))])
		return true
	if dbg:
		print("EPIC img %s: %s (kept, w %d)" % [name, text, maxw])
	return false


func _wrap(font: Dictionary, text: String, maxw: int, max_lines: int, lg: int, space: int) -> Array:
	var out: Array = []
	var cur := ""
	for word in text.split(" ", false):
		var cand: String = word if cur == "" else cur + " " + word
		if text_width(font, cand, lg, space) <= maxw:
			cur = cand
			continue
		if cur == "" or text_width(font, word, lg, space) > maxw:
			return []
		out.append(cur)
		cur = word
	if cur != "":
		out.append(cur)
	return out if out.size() <= max_lines and not out.is_empty() else []


## section tabs in tiny capitals (colour 9 on black): "ARTS" -> "EPIC ARTS" ... (QoLEpic.TAB_TEXT, letters these
## tabs have: A B C E I K L M O P R S T U)
func _tabs(px: PackedByteArray, w: int, h: int, name: String) -> bool:
	if not _df.has("tiny"):
		_df["tiny"] = _font(QoLEpicRefs.TINY_REFS, "/Romdata/data/DataModeDataImage_EN.bin", false)
	var tiny: Dictionary = _df["tiny"]
	var cs: Array = []
	for c in components(px, w, h, 9):
		if int(c[3]) - int(c[1]) <= 6:
			cs.append(c)
	var done := false
	for l in lines_of(cs):
		if int(l["y1"]) - int(l["y0"]) > 7 or l["g"].size() < 3:
			continue
		var rs := runs_of(l, 9, tiny["keys"], w, 12, false)
		if rs.is_empty():
			continue
		var r: Dictionary = rs[0]
		for k in range(1, rs.size()):
			r["gl"].append_array(rs[k]["gl"])
			r["x1"] = rs[k]["x1"]
			r["text"] = str(r["text"]) + str(rs[k]["text"])
		var key := str(r["text"]).replace(" ", "")
		if not QoLEpic.TAB_TEXT.has(key):
			continue
		var nt: String = QoLEpic.TAB_TEXT[key]
		var maxw := free_right(px, w, r, r["y0"], r["y1"]) - 2 - int(r["x0"])
		if text_width(tiny, nt, 1, 3) > maxw:
			continue
		erase_run(px, r)
		draw_text(px, w, h, tiny, nt, r["x0"], r["base"], 9, 1, 3)
		done = true
		if dbg:
			print("EPIC img %s: tab %s => %s" % [name, key, nt])
	return done


## the character's name bar (bold anti-aliased font, white on colour 1): a suffix after the name ("B)", "(Boss)"),
## drawn with the page font (white)
func _name_suffix(px: PackedByteArray, w: int, h: int, name: String) -> bool:
	var right := -1
	for x in range(w - 1, -1, -1):
		for y in range(2, mini(h, 18)):
			if px[y * w + x] > 1:
				right = x
				break
		if right >= 0:
			break
	if right < 0 or right > 200:
		return false
	epic._h = QoLEpic.fnv(name.to_ascii_buffer())
	var suf: String = epic._pick(QoLEpic.NAME_SUFFIX, "name")
	if right + 5 + text_width(_df, suf, 1, 4) >= w - 2:
		return false
	draw_text(px, w, h, _df, suf, right + 5, 15, 15, 1, 4)
	if dbg:
		print("EPIC img %s: name + %s" % [name, suf])
	return true


# ------------------------------------------------------------------------------------------------ help panels
## Data File help panels (A3I5 textures 256x256: low 5 bits colour, high 3 bits alpha): white text lines in the
## game's text font, 14 px apart; the three icons of the Super Attack panel stay. Hand-written text.
func _help(name: String, addr: int, size: int) -> void:
	var key := name.trim_suffix("_US.ntft")
	if not QoLEpic.HELP_TEXT.has(key):
		return
	var d := _ram(addr, size)
	var cnt := {}
	for b in d:
		cnt[b] = int(cnt.get(b, 0)) + 1
	var order := cnt.keys()
	order.sort_custom(func(a, b): return cnt[a] > cnt[b])
	if order.size() < 2:
		return
	var bg: int = order[0]
	var ink: int = order[1]                  # the text colour is the second most common value
	var blocks: Array = QoLEpic.HELP_TEXT[key]   # [x, cap top y, [lines]]
	var clear_x := 256
	for blk in blocks:
		clear_x = mini(clear_x, int(blk[0]) - 3)
	for i in d.size():
		if i % 256 >= clear_x:          # right of the Super Attack icons there is only text
			d[i] = bg
	var cells := QoLFont._rom_cells(rom)
	for blk in blocks:
		var lines: Array = blk[2]
		for k in lines.size():
			var cx: int = blk[0]
			var top: int = int(blk[1]) + k * 14
			for ch in str(lines[k]):
				var gi := ch.unicode_at(0) - 0x21
				if gi >= 0 and gi < cells.size():
					var cell: PackedByteArray = cells[gi]
					for cy in 15:
						for cxx in 9:
							if cell[cy * 9 + cxx]:
								var X := cx - 2 + cxx
								var Y := top - 3 + cy
								if X >= clear_x and X < 256 and Y >= 0 and Y < 256:
									d[Y * 256 + X] = ink
				cx += 6
	_put(addr, d)
	if dbg:
		print("EPIC help %s: ink %x bg %x" % [name, ink, bg])


# ------------------------------------------------------------------------------------------------ credits
func _credits(cname: String, chars_a: int, chars_n: int, map_a: int, map_n: int) -> void:
	if _cr.is_empty():
		_cr = _font(QoLEpicRefs.CR_REFS, "/Romdata/credit/CreditRollEU.bin", true)
	var t0 := Time.get_ticks_usec()
	var chars := _ram(chars_a, chars_n)
	var map := _ram(map_a, map_n)
	var px := bg_to_px(chars, map)
	var t1 := Time.get_ticks_usec()
	var w := 256
	var h := px.size() / w
	var cnt := {}
	for v in px:
		cnt[v] = int(cnt.get(v, 0)) + 1
	var edits: Array = []      # [run, new text, x]
	for ink in cnt.keys():
		if int(cnt[ink]) > px.size() / 4 or ink == 0:
			continue
		for l in lines_of(components(px, w, h, ink)):
			var lruns := runs_of(l, ink, _cr["keys"], w, 10, true)
			for r in lruns:
				var t: String = r["text"]
				if t.strip_edges().length() < 2 or r["cut"]:
					continue
				var c: Array = epic.credit_text(t, ink)
				for cand in c:
					var nw := text_width(_cr, cand, 1, 6)
					var ow: int = r["x1"] - r["x0"] + 1
					var cx: int = (r["x0"] + r["x1"]) / 2
					var x0: int
					if absi(cx - 128) <= 12:
						x0 = cx - nw / 2               # centred
					elif r["x1"] < 128:
						x0 = r["x1"] - nw + 1          # right-aligned (cast: character names)
					else:
						x0 = r["x0"]                   # left-aligned (cast: actors)
					if x0 < 4 or x0 + nw > 252 or (r["x1"] < 128 and x0 + nw > 128) or (r["x0"] >= 128 and x0 < 128 and absi(cx - 128) > 12):
						continue
					var hit := false
					for o in lruns:
						if o != r and x0 <= int(o["x1"]) + 6 and x0 + nw >= int(o["x0"]) - 6:
							hit = true
					if hit:
						continue
					edits.append([r, cand, x0, ow])
					break
	var t2 := Time.get_ticks_usec()
	if edits.is_empty():
		return
	# the credits table (*0x020E1570, 11 x {+0 palette, +4 chars, +8 map, +0xC chars size, +0x10 map size}) lets the
	# picture grow to 1024 tiles: BG1 / BG2 characters at VRAM 0xC000 / 0x14000, 32 KiB each
	var entry := -1
	var tab: int = core._ld(CREDITS_TABLE, 4, false)
	for i in 11:
		if tab != 0 and core._ld(tab + i * 0x14 + 4, 4, false) == chars_a:
			entry = tab + i * 0x14
	var tiles_max := 1024 if entry >= 0 else chars_n / 32
	var n_apply := edits.size()
	while n_apply > 0:
		var p2 := px.duplicate()
		for k in n_apply:
			erase_run(p2, edits[k][0])
		for k in n_apply:
			var e: Array = edits[k]
			draw_text(p2, w, h, _cr, e[1], e[2], e[0]["base"], e[0]["ink"], 1, 6)
		var enc := _encode_bg(p2, map, tiles_max)
		if not enc.is_empty():
			var need: int = int(enc[2]) * 32
			var dst := chars_a
			if need > chars_n:
				dst = core.f_020090e4(need)
				if dst == 0:
					n_apply -= 1
					continue
				core.f_020090b0(chars_a)
				core._st(entry + 4, 4, dst)
				core._st(entry + 0xC, 4, need)
			var cdata: PackedByteArray = enc[0]
			cdata.resize(maxi(need, chars_n) if dst == chars_a else need)
			_put(dst, cdata)
			_put(map_a, enc[1])
			if dbg:
				for k in n_apply:
					print("EPIC credits %s: %s => %s" % [cname, edits[k][0]["text"], edits[k][1]])
				print("EPIC credits %s: %d/%d lines, %d tiles of %d (ms: decode %d, read %d, write %d)" % [cname, n_apply, edits.size(), enc[2], tiles_max, (t1 - t0) / 1000, (t2 - t1) / 1000, (Time.get_ticks_usec() - t2) / 1000])
			return
		n_apply -= 1
	if dbg:
		print("EPIC credits %s: no room for the rewrites" % cname)


## pixels -> tiles (de-duplicated, no flips) + map (palette bits kept); [] if more tiles than `tiles_max`
static func _encode_bg(px: PackedByteArray, old_map: PackedByteArray, tiles_max: int) -> Array:
	var rows := old_map.size() / 64
	var index := {}
	var chars := PackedByteArray()
	var map := PackedByteArray()
	map.resize(old_map.size())
	var blank := PackedByteArray()
	blank.resize(32)
	index[blank] = 0
	chars.append_array(blank)
	for ty in rows:
		for tx in 32:
			var t := PackedByteArray()
			t.resize(32)
			for y in 8:
				for x in 4:
					var o := (ty * 8 + y) * 256 + tx * 8 + x * 2
					t[y * 4 + x] = px[o] | (px[o + 1] << 4)
			var id: int
			var fl := 0
			if index.has(t):
				id = index[t]
			else:
				var found := false
				var vs := [_flip(t, true, false), _flip(t, false, true), _flip(t, true, true)]
				for f in 3:
					if index.has(vs[f]):
						id = index[vs[f]]
						fl = [1, 2, 3][f]
						found = true
						break
				if not found:
					id = chars.size() / 32
					if id >= tiles_max or id >= 1024:
						return []
					index[t] = id
					chars.append_array(t)
			var e := old_map.decode_u16((ty * 32 + tx) * 2)
			map.encode_u16((ty * 32 + tx) * 2, (e & 0xF000) | (fl << 10) | id)
	return [chars, map, chars.size() / 32]


static func _flip(t: PackedByteArray, h: bool, v: bool) -> PackedByteArray:
	var o := PackedByteArray()
	o.resize(32)
	for y in 8:
		var sy := 7 - y if v else y
		for x in 8:
			var sx := 7 - x if h else x
			var val := (t[sy * 4 + (sx >> 1)] >> ((sx & 1) * 4)) & 15
			o[y * 4 + (x >> 1)] |= val << ((x & 1) * 4)
	return o


# ------------------------------------------------------------------------------------------------ touch-screen items
func _subscr(cname: String, chars_a: int, chars_n: int, map_a: int, map_n: int) -> void:
	var pack := "/Romdata/data/DataSubScrEU.bin"
	if not _df.has("sub_small"):
		_df["sub_small"] = _font(QoLEpicRefs.SUB_SMALL_REFS, pack, true)
		_df["sub_big"] = _font(QoLEpicRefs.SUB_BIG_REFS, pack, true)
		var keys: Dictionary = _df["sub_small"]["keys"].duplicate()
		keys.merge(_df["sub_big"]["keys"])
		_df["sub_keys"] = keys
	var chars := _ram(chars_a, chars_n)
	var map := _ram(map_a, map_n)
	var px := bg_to_px(chars, map)
	var w := 256
	var h := px.size() / w
	var edits: Array = []
	for l in lines_of(components(px, w, h, 15, 0, -1, 16)):
		var rs := runs_of(l, 15, _df["sub_keys"], w, 12, false)
		if rs.size() > 1:            # one label per line: the big font's word gaps can exceed the run split
			var m: Dictionary = rs[0]
			for k in range(1, rs.size()):
				m["gl"].append_array(rs[k]["gl"])
				m["x1"] = rs[k]["x1"]
				m["text"] = str(m["text"]) + str(rs[k]["text"])
			rs = [m]
		for r in rs:
			var t: String = str(r["text"]).replace(" ", "").replace("I", "l")
			if dbg and not QoLEpic.SUB_TEXT.has(t):
				print("EPIC sub %s: run %s (kept)" % [cname, t])
			if not QoLEpic.SUB_TEXT.has(t):
				continue
			var big: bool = int(r["y1"]) - int(r["y0"]) > 11
			var font: Dictionary = _df["sub_big"] if big else _df["sub_small"]
			var nt: String = QoLEpic.SUB_TEXT[t]
			var nw := text_width(font, nt, r["lg"], r["sp"])
			var x0: int = r["x0"] if not big else (int(r["x0"]) + int(r["x1"])) / 2 - nw / 2
			# the rest of the line after the run (a full stop the reader does not know) goes too
			var gl_after: Array = []
			for g in l["g"]:
				if g["x0"] > r["x1"] and g["x0"] - r["x1"] < 8:
					gl_after.append(g)
			edits.append([r, nt, x0, font, gl_after])
	if edits.is_empty():
		return
	var n_apply := edits.size()
	while n_apply > 0:
		var p2 := px.duplicate()
		for k in n_apply:
			erase_run(p2, edits[k][0])
			for g in edits[k][4]:
				for p in g["pts"]:
					p2[p] = edits[k][0]["bg"]
		for k in n_apply:
			var e: Array = edits[k]
			draw_text(p2, w, h, e[3], e[1], e[2], e[0]["base"], 15, e[0]["lg"], e[0]["sp"])
		var enc := _encode_bg(p2, map, chars_n / 32)
		if not enc.is_empty():
			var cdata: PackedByteArray = enc[0]
			cdata.resize(chars_n)
			_put(chars_a, cdata)
			_put(map_a, enc[1])
			if dbg:
				for k in n_apply:
					print("EPIC sub %s: %s => %s" % [cname, edits[k][0]["text"], edits[k][1]])
			return
		n_apply -= 1
	if dbg:
		print("EPIC sub %s: no room" % cname)
