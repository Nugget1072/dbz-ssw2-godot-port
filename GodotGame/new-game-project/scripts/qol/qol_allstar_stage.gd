class_name QoLAllStarStage
extends RefCounted
## ALL-STAR phase 3 (docs/ALLSTAR_DESIGN.md 1.7 / 1.8; DATA_NOTES "part 34 findings (All-Star stage)"): the space sky
## and the music rotation of an All-Star battle. Owned by QoLGame (`# ---- ALLSTAR STAGE (part 34)`), ticked once per
## game frame on the game thread only while QoLGame._asb_on (an All-Star battle runs): nothing here runs, reads or
## writes anything in any other battle, scene or mode (the normal Time Chamber is untouched).
##
## Sky (part 35; DATA_NOTES "part 35 findings (All-Star sky)"): the Time Chamber (stage 4) draws its sky on engine A
## BG3 (256-colour text BG, 256x256, never scrolled: HOFS / VOFS stay 0, the parallax is BG2's; BG palette indices
## 32..191 used only by it; BG2 = the panorama dots, BG0 = the 3D floor / building, BG1 = the HUD). Once the stage's own
## BG3 data is up, BG3 becomes a DS-style night sky built once at runtime from fixed seeds (no ROM data): a vertical
## gradient (near-black at the top -> indigo -> navy at the bottom; 5-bit ramp entries with 4x4 ordered dithering
## between neighbours), a faint milky-way band with a dark dust lane and a smaller cloud (value noise, periodic over
## the 256-px map width; 3 hues rose / violet / teal x 4 levels x 7 brightness bands, dithered), ~230 one-pixel stars
## (white, blue-white, yellow, orange, pale red; dim .. bright; denser in the band, fewer near the horizon) and 6 plus-
## shaped glints. Up to SKY_TILES deduplicated 8x8 tiles over BG3's own char block (tiles 0..479 = the stage's BG3
## tile data, 0x14000..0x1B800; 0x1C000 holds another map), the map in VRAM + the BG manager's BG3 map buffer (a
## re-queued upload keeps it). Palette: the static entries (ramp + nebula) and the twinkle entries (36 star slots =
## 4 height zones x 9 star classes, each its own period / phase, blending between the sky under its stars and the star
## colour; 6 glints x centre / arms / outer arms) go to the BG manager's palette shadow (+0x1D8) and palette RAM,
## written only when they differ. The sky's light-ray curtain (two translucent 3D objects over BG3) is hidden
## (`_hide_rays`). Floor, building, BG2 dots and fog keep the game's colours; fades / flashes / pause darkening are the
## game's own on top (unchanged). Re-applied whenever the game put its own data back (checked every frame, never while
## paused; the twinkle stops in the pause).
##
## Music: the battle BGM is a stream (STRM; Time Chamber = 5). Each fight frame the stream position (handle
## u32 0x020DE33C -> P, u32 P+0x158 = samples played) is compared with the track's sample count (STRM HEAD, read by
## QoLSound): when it is about to end (less than the largest per-frame step seen + 2 frames' worth left) or has gone
## backwards (it wrapped to the loop start), the game's own stop + play (FUN_0200FDE4(0), FUN_0200FE48(n)) starts a
## random other stage BGM n (STRM 1..15, never the one playing). The manager's "stopped / paused" bit (+0xA2 bit 0,
## set by the stop) is put back as it was (V: it is already 1 in battle, so the battle pause FUN_0200FD68 does not stop
## the BGM; a resume FUN_0200FCF8 would restart the CURRENT id +0xA8). Switches only in battle states 7, 8, 0xA-0xE and
## until the last enemy's KO; a track that ends while paused (state 9, the music keeps playing) switches when the fight
## resumes. The game's own battle end / scene change stops the music as usual. RANDOM MUSIC: the first track is whatever the
## game (and the cheat) started; the rotation's picks bypass the cheat's stream map (already random, and only stage
## BGMs: no 7-s VS jingle).
## Debug: `asdbg` (AS lines: sky applied / restored, music switch), `asmusic=F,...` (force a switch at port frame F),
## `asmseek=F:S,...` (at port frame F restart the playing track S seconds before its end: natural end tests),
## `asmseed=N` (rotation picks), `asmlog` (stream position every 30 frames), `assky=0` (no space sky: comparisons), `asrays=1` (keep the light rays),
## `asskypng=FILE` (the built sky as a PNG), `asskylog` (BG3 / BG2 scroll + blend registers every 10 frames).

const BGMGR := 0x020DD7BC                ## u32 -> BG manager: +0x1AC + 4*bg map buffers, +0x1D8 engine A BG palette shadow
const STAGE_BLK := 0x020DE3BC            ## u32 -> battle stage block: +0xCBE stage id
const BGM := 0x020DE2A0                  ## BGM manager: +0xA0 mode (bit 0 sequences), +0xA2 bit 0 stopped/paused, +0xA8 id
const STRM_H := 0x020DE33C               ## u32 -> stream player: +0x158 samples played, u16 +0xC0 rate
const FIGHT := [7, 8, 0xA, 0xB, 0xC, 0xD, 0xE]
const FPS := 59.8261
const PAL_FIRST := 32                    ## BG palette entries of the sky: 32..191 (BG3's own)
const PAL_LAST := 191
const SKY_H := 192                       ## visible rows (BG3 is not scrolled; map rows 24..31 never show)
const SKY_TILES := 480                   ## BG3's own char data: tiles 0..479 (0x06014000..0x0601B800)
const SKY_SEED := 35035
## gradient anchors [y, r, g, b] (8-bit, quantised to the DS's 5 bits)
const GRAD := [[0, 2, 3, 9], [30, 5, 6, 18], [70, 12, 12, 36], [100, 21, 21, 56], [140, 30, 33, 75], [191, 38, 46, 90]]
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const NEB_FAM := [[34, 10, 26], [26, 12, 38], [6, 24, 30]]   ## nebula tints (added light, 8-bit): rose, violet, teal
const NEB_K := 4                         ## nebula levels
const NEB_J := 7                         ## sky brightness bands of the nebula colours
const NEB_GAIN := 1.9
const NEB_FLOOR := 0.14                  ## faint nebula below this = clear sky (keeps the edges clean, saves tiles)
const ZONES := 4                         ## star twinkle slots per height zone (the slot's base = the sky under its stars)
const ZONE_H := 48
## star classes: [colour (8-bit), weight, brightness low, high] (twinkle = mix of the sky and the colour)
const STAR_CLASSES := [
	[[235, 240, 255], 40, 0.35, 0.6], [[200, 215, 255], 22, 0.35, 0.65], [[255, 245, 215], 14, 0.4, 0.7],
	[[255, 215, 160], 8, 0.45, 0.8], [[255, 180, 150], 5, 0.45, 0.75], [[255, 255, 255], 6, 0.8, 1.0],
	[[190, 210, 255], 5, 0.75, 1.0], [[255, 230, 170], 4, 0.75, 0.95], [[255, 200, 170], 3, 0.7, 0.9]]
const STARS := 230
const GLINTS := 6                        ## plus-shaped bright stars (the first GLINTS_LONG with 2-px arms)
const GLINTS_LONG := 3
const GLINT_Y0 := 10
const GLINT_Y1 := 130
const GLINT_COLS := [[255, 255, 255], [200, 220, 255], [255, 240, 200], [255, 210, 160], [220, 230, 255], [255, 250, 235]]
const RAY_TEX := 3                       ## stage 4: texture of the light-ray curtain objects
const POOL := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]   ## stage BGM streams (stage s -> s+1, 2 -> 4, 3 -> 3)
const BOSS_POOL := [16, 17]          ## part 43 BOSS RUSH: the game's two boss themes (BOSS1 / BOSS2), from the first FIGHT

var g                                    ## QoLGame
var dbg := Game.args.has("asdbg")
var _sky := Game.flag("assky", "1") != "0"
var _rays := Game.flag("asrays", "0") != "0"     ## debug `asrays=1`: keep the light-ray curtain
var _skylog := Game.args.has("asskylog")         ## debug: BG3 / BG2 scroll + blend registers every 10 frames
var _built := false
var _build_info := ""
var _tiles := PackedByteArray()          ## distinct 8x8 tiles (64 bytes each)
var _map := PackedByteArray()            ## 32 x 32 entries (u16)
var _static_pal := PackedInt32Array()    ## BGR555 of PAL_FIRST.. (ramp, then nebula)
var _p_neb := 0                          ## first nebula / star slot / glint palette index
var _p_star := 0
var _p_glint := 0
var _slots: Array = []                   ## twinkle: [palette index, base rgb (5-bit), colour rgb, lo (-1 glint), hi, period, phase]
var _glint_base: Array = []
var _lat := {}                          ## noise lattice cache (build only)
var _task := -1                          ## WorkerThreadPool task of the build (-1 none)
var _pal_now := {}                       ## palette index -> colour written last
var _sky_state := ""                     ## "" / "on" (log changes only)
var _t := 0                              ## twinkle clock (frames, not while paused)
var _sky_n := 0                          ## times the star field was (re)written this battle
# music
var _rng := RandomNumberGenerator.new()
var _m_id := -1                          ## stream id seen last frame
var _m_last := -1                        ## position seen last frame
var _m_since := 0                        ## fight frames since the id changed / the position was re-based
var _m_step := 0                         ## largest per-frame position step seen (the counter may move in blocks)
var _m_force: Array = []                 ## debug `asmusic=F,...`
var _m_seek: Array = []                  ## debug `asmseek=F:S,...`
var _m_pending := ""                     ## the track ended / wrapped while paused: switch when the fight resumes
var _m_switches := 0
var _m_log := Game.args.has("asmlog")


func _init(game) -> void:
	g = game
	if Game.args.has("asmseed"):
		_rng.seed = int(Game.flag("asmseed"))
	else:
		_rng.randomize()


func _log(s: String) -> void:
	if dbg:
		print("AS f%d %s" % [g._port_frame(), s])


## a new All-Star battle (FUN_020140C8)
func reset() -> void:
	_sky_state = ""
	_sky_n = 0
	_t = 0
	_pal_now = {}
	_m_id = -1
	_m_last = -1
	_m_since = 0
	_m_step = 0
	_m_switches = 0
	_m_pending = ""
	_m_force = []
	_m_seek = []
	if Game.args.has("asmseek"):
		for e in str(Game.flag("asmseek")).split(",", false):
			var q := e.split(":")
			_m_seek.append([int(q[0]), float(q[1]) if q.size() > 1 else 3.0])
	if Game.args.has("asmusic"):
		for f in str(Game.flag("asmusic")).split(",", false):
			_m_force.append(int(f))
	if _sky and not _built and _task < 0:              # the sky is built in the background while the stage loads
		_task = WorkerThreadPool.add_task(_build, false, "All-Star sky")


## once per game frame during an All-Star battle (after the phase-2 tick)
func tick(st: int) -> void:
	if _sky:
		_sky_tick(st)
	_music_tick(st)


# ------------------------------------------------------------------------------------------------ sky
## Builds the sky once (fixed seeds, no ROM data): an indexed 256x256 picture -> deduplicated 8x8 tiles + 32x32 map,
## the static palette (ramp + nebula) and the twinkle slots. About 0.15 s of GDScript, once per QoLAllStarStage, on a
## WorkerThreadPool task started at the battle setup (touches only this object's own fields; never game memory).
func _build() -> void:
	var t0 := Time.get_ticks_usec()
	# -- the gradient ramp: the 8-bit anchors quantised to 5-bit, consecutive duplicates removed
	var ramp: Array = []                               # [r, g, b] 0..31
	var ramp_y: Array = []                             # first y (float) of each entry
	for yy in SKY_H * 4:
		var c := _q5(_grad8(yy / 4.0))
		if ramp.is_empty() or c != ramp[-1]:
			ramp.append(c)
			ramp_y.append(yy / 4.0)
	var ng := ramp.size()
	var mids: Array = []
	for i in ng:
		mids.append((float(ramp_y[i]) + (float(ramp_y[i + 1]) if i + 1 < ng else float(SKY_H))) * 0.5)
	var upos := PackedFloat32Array()                   # per row: continuous ramp position
	upos.resize(256)
	for y in 256:
		var yf := float(mini(y, SKY_H - 1))
		var u := 0.0
		if yf > float(mids[0]):
			u = float(ng - 1)
			for i in ng - 1:
				if yf < float(mids[i + 1]):
					u = i + (yf - float(mids[i])) / (float(mids[i + 1]) - float(mids[i]))
					break
		upos[y] = u
	# -- palette layout (absolute BG palette indices from PAL_FIRST)
	_p_neb = PAL_FIRST + ng
	_p_star = _p_neb + NEB_FAM.size() * NEB_K * NEB_J
	_p_glint = _p_star + ZONES * STAR_CLASSES.size()
	var p_end := _p_glint + GLINTS * 3
	assert(p_end <= PAL_LAST + 1)
	_static_pal = PackedInt32Array()
	for c in ramp:
		_static_pal.append(_rgb15(c))
	for f in NEB_FAM.size():
		for k in NEB_K:
			for j in NEB_J:
				var base := _ramp8(ramp, (j + 0.5) * (ng - 1) / NEB_J)
				var lv := (k + 1.0) / NEB_K * NEB_GAIN
				var tint: Array = NEB_FAM[f]
				_static_pal.append(_rgb15(_q5([base[0] + tint[0] * lv, base[1] + tint[1] * lv, base[2] + tint[2] * lv])))
	# -- nebula fields at half resolution (128 x 96, x periodic), upsampled bilinearly per pixel
	var nh := PackedFloat32Array()
	var hh := PackedFloat32Array()
	nh.resize(128 * 96)
	hh.resize(128 * 96)
	for j in 96:
		for i in 128:
			var r := _neb(i * 2.0, j * 2.0)
			nh[j * 128 + i] = r.x
			hh[j * 128 + i] = r.y
	# -- the indexed picture (rows SKY_H..255 never show: BG3 is not scrolled; they repeat the last row)
	var img := PackedByteArray()
	img.resize(256 * 256)
	var nebf := PackedFloat32Array()                   # nebula intensity per visible pixel (star density)
	nebf.resize(256 * SKY_H)
	var plain := PackedByteArray()                     # per pixel: 1 = ramp only (no nebula / star)
	plain.resize(256 * 256)
	var rampimg := PackedByteArray()                   # ramp-only pixels (the plain tile of each tile row)
	rampimg.resize(256 * 256)
	for y in 256:
		var u: float = upos[y]
		var ui := int(u)
		var fr := u - ui
		var jb := u * NEB_J / (ng - 1)
		for x in 256:
			var d1: float = (BAYER[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0
			var r := mini(ng - 1, ui + (1 if fr > d1 else 0))
			var idx := PAL_FIRST + r
			plain[y * 256 + x] = 1
			rampimg[y * 256 + x] = idx
			if y < SKY_H:
				var n := _up(nh, x, y)
				nebf[y * 256 + x] = n
				n = maxf(0.0, (n - NEB_FLOOR) / (1.0 - NEB_FLOOR))
				var d2: float = (BAYER[((y + 2) & 3) * 4 + ((x + 1) & 3)] + 0.5) / 16.0
				var nk := n * NEB_K
				var ki := mini(NEB_K, int(nk) + (1 if nk - int(nk) > d2 else 0))
				if ki > 0:
					var j := clampi(int(jb + (d1 - 0.5) * 0.9), 0, NEB_J - 1)
					var hf := _up(hh, x, y) * (NEB_FAM.size() - 1)
					var f := mini(NEB_FAM.size() - 1, int(hf) + (1 if hf - int(hf) > d1 else 0))
					idx = _p_neb + (f * NEB_K + ki - 1) * NEB_J + j
					plain[y * 256 + x] = 0
			img[y * 256 + x] = idx
	# -- stars: 1-pixel stars (slot = zone x class), denser in the nebula band, fewer near the horizon
	var rng := RandomNumberGenerator.new()
	rng.seed = SKY_SEED
	var taken := {}
	var acc: Array = []                                # per slot: [sum r, g, b, n] of the sky under its stars
	for s in ZONES * STAR_CLASSES.size():
		acc.append([0.0, 0.0, 0.0, 0])
	var wsum := 0
	for c in STAR_CLASSES:
		wsum += int(c[1])
	var placed := 0
	var tries := 0
	while placed < STARS and tries < 30000:
		tries += 1
		var x := rng.randi_range(0, 255)
		var y := rng.randi_range(0, SKY_H - 3)
		var dens := 0.35 + 1.3 * nebf[y * 256 + x] + 0.4 * maxf(0.0, (120.0 - y) / 120.0)
		dens *= clampf((180.0 - y) / 60.0, 0.0, 1.0)
		if rng.randf() > dens * 0.5 or _near(taken, x, y, 1):
			continue
		var w := rng.randi_range(0, wsum - 1)
		var v := 0
		while w >= int(STAR_CLASSES[v][1]):
			w -= int(STAR_CLASSES[v][1])
			v += 1
		var z := mini(ZONES - 1, y / ZONE_H)
		var slot := z * STAR_CLASSES.size() + v
		var bg := _pal_rgb(img[y * 256 + x])
		var a: Array = acc[slot]
		a[0] += bg[0]
		a[1] += bg[1]
		a[2] += bg[2]
		a[3] += 1
		img[y * 256 + x] = _p_star + slot
		plain[y * 256 + x] = 0
		taken[y * 256 + x] = true
		placed += 1
	# -- glints: a few bright plus-shaped stars (centre, arms, outer arms on the first ones), each its own slots
	_glint_base = []
	var gl: Array = []
	tries = 0
	while gl.size() < GLINTS and tries < 2000:
		tries += 1
		var x := rng.randi_range(0, 255)
		var y := rng.randi_range(GLINT_Y0, GLINT_Y1)
		var ok := true
		for q in gl:
			if absi(posmod(x - int(q[0]) + 128, 256) - 128) < 34 and absi(y - int(q[1])) < 26:
				ok = false
		if not ok or _near(taken, x, y, 3):
			continue
		gl.append([x, y])
		var b := gl.size() - 1
		_glint_base.append(_pal_rgb(img[y * 256 + x]))
		var p := _p_glint + b * 3
		img[y * 256 + x] = p
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			img[(y + d[1]) * 256 + posmod(x + d[0], 256)] = p + 1
		if b < GLINTS_LONG:
			for d in [[2, 0], [-2, 0], [0, 2], [0, -2]]:
				img[(y + d[1]) * 256 + posmod(x + d[0], 256)] = p + 2
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				plain[(y + dy) * 256 + posmod(x + dx, 256)] = 0
				taken[(y + dy) * 256 + posmod(x + dx, 256)] = true
	# -- twinkle slots
	_slots = []
	for s in ZONES * STAR_CLASSES.size():
		var cl: Array = STAR_CLASSES[s % STAR_CLASSES.size()]
		var a: Array = acc[s]
		var base := [2.0, 2.0, 6.0] if int(a[3]) == 0 else [a[0] / a[3], a[1] / a[3], a[2] / a[3]]
		_slots.append([_p_star + s, base, _c5(cl[0]), float(cl[2]), float(cl[3]), rng.randi_range(80, 220), rng.randf() * TAU])
	for b in GLINTS:
		var base: Array = _glint_base[b] if b < _glint_base.size() else [2.0, 2.0, 6.0]
		_slots.append([_p_glint + b * 3, base, _c5(GLINT_COLS[b % GLINT_COLS.size()]), -1.0, 0.0, rng.randi_range(55, 120),
			rng.randf() * TAU])
	# -- tiles: one plain gradient tile per tile row first, then every other distinct tile up to SKY_TILES
	_tiles = PackedByteArray()
	_map = PackedByteArray()
	_map.resize(32 * 32 * 2)
	var seen := {}
	var row_tile := PackedInt32Array()
	for ty in 32:
		var t := _tile_of(rampimg, 0, ty)              # the ramp's dither repeats every 4 px: one tile per row
		var k := t.hex_encode()
		if not seen.has(k):
			seen[k] = _tiles.size() / 64
			_tiles.append_array(t)
		row_tile.append(int(seen[k]))
	var dropped := 0
	for ty in 32:
		for tx in 32:
			var ti := row_tile[ty]
			var isplain := true
			for yy in 8:
				for xx in 8:
					if plain[(ty * 8 + yy) * 256 + tx * 8 + xx] == 0:
						isplain = false
			if not isplain:
				var t := _tile_of(img, tx, ty)
				var k := t.hex_encode()
				if seen.has(k):
					ti = int(seen[k])
				elif _tiles.size() / 64 < SKY_TILES:
					ti = _tiles.size() / 64
					seen[k] = ti
					_tiles.append_array(t)
				else:
					dropped += 1                       # over the budget: the plain row tile (never with these seeds)
			_map.encode_u16((ty * 32 + tx) * 2, ti)
	_lat = {}
	_build_info = "%d tiles (%d dropped), ramp %d, palette %d..%d, %d stars + %d glints, %d us" % [_tiles.size() / 64,
		dropped, ng, PAL_FIRST, p_end - 1, placed, gl.size(), Time.get_ticks_usec() - t0]
	if Game.args.has("asskypng"):                     # debug: the built sky (twinkle at t = 0) as a PNG
		var im := Image.create_empty(256, 256, false, Image.FORMAT_RGB8)
		var pal := _static_pal.duplicate()
		pal.resize(p_end - PAL_FIRST)
		for e in _slot_colours(0):
			pal[int(e[0]) - PAL_FIRST] = int(e[1])
		for y in 256:
			for x in 256:
				var c: int = pal[img[y * 256 + x] - PAL_FIRST]
				im.set_pixel(x, y, Color8((c & 31) * 255 / 31, ((c >> 5) & 31) * 255 / 31, ((c >> 10) & 31) * 255 / 31))
		im.save_png(str(Game.flag("asskypng")))


func _grad8(y: float) -> Array:
	for i in GRAD.size() - 1:
		var a: Array = GRAD[i]
		var b: Array = GRAD[i + 1]
		if y <= float(b[0]):
			var t := (y - float(a[0])) / (float(b[0]) - float(a[0]))
			return [a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t]
	var l: Array = GRAD[-1]
	return [float(l[1]), float(l[2]), float(l[3])]


func _q5(c: Array) -> Array:
	return [clampi(roundi(float(c[0]) * 31.0 / 255.0), 0, 31), clampi(roundi(float(c[1]) * 31.0 / 255.0), 0, 31),
		clampi(roundi(float(c[2]) * 31.0 / 255.0), 0, 31)]


func _c5(c: Array) -> Array:
	return [float(c[0]) * 31.0 / 255.0, float(c[1]) * 31.0 / 255.0, float(c[2]) * 31.0 / 255.0]


func _rgb15(c: Array) -> int:
	return int(c[0]) | (int(c[1]) << 5) | (int(c[2]) << 10)


## the ramp's colour (8-bit floats) at a continuous position
func _ramp8(ramp: Array, pos: float) -> Array:
	var i := int(pos)
	if i >= ramp.size() - 1:
		var l: Array = ramp[-1]
		return [l[0] * 255.0 / 31.0, l[1] * 255.0 / 31.0, l[2] * 255.0 / 31.0]
	var f := pos - i
	var a: Array = ramp[i]
	var b: Array = ramp[i + 1]
	return [(a[0] + (b[0] - a[0]) * f) * 255.0 / 31.0, (a[1] + (b[1] - a[1]) * f) * 255.0 / 31.0,
		(a[2] + (b[2] - a[2]) * f) * 255.0 / 31.0]


## a static palette entry as 5-bit floats (for the twinkle bases)
func _pal_rgb(p: int) -> Array:
	var c: int = _static_pal[p - PAL_FIRST]
	return [float(c & 31), float((c >> 5) & 31), float((c >> 10) & 31)]


func _near(taken: Dictionary, x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if taken.has((y + dy) * 256 + posmod(x + dx, 256)):
				return true
	return false


func _tile_of(img: PackedByteArray, tx: int, ty: int) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(64)
	for yy in 8:
		for xx in 8:
			t[yy * 8 + xx] = img[(ty * 8 + yy) * 256 + tx * 8 + xx]
	return t


## half-resolution field (128 x 96, x periodic) sampled at a full-resolution pixel
func _up(f: PackedFloat32Array, x: int, y: int) -> float:
	var fx := x * 0.5
	var fy := minf(y * 0.5, 95.0)
	var i0 := int(fx)
	var j0 := int(fy)
	var i1 := (i0 + 1) & 127
	var j1 := mini(j0 + 1, 95)
	var ax := fx - i0
	var ay := fy - j0
	var a := f[j0 * 128 + i0] + (f[j0 * 128 + i1] - f[j0 * 128 + i0]) * ax
	var b := f[j1 * 128 + i0] + (f[j1 * 128 + i1] - f[j1 * 128 + i0]) * ax
	return a + (b - a) * ay


## nebula at (x, y): Vector2(intensity 0..1, hue 0..1 = rose .. violet .. teal); periodic in x (period 256)
func _neb(x: float, y: float) -> Vector2:
	var th := TAU * x / 256.0
	var yc := 64.0 + 15.0 * sin(th + 0.9) + 9.0 * sin(2.0 * th + 2.4)     # the milky-way band's centre line
	var d := (y - yc) / 26.0
	var band := exp(-d * d)
	var n1 := _fbm(x, y, 8, 4, 11)
	var n2 := _fbm(x, y, 16, 3, 23)
	var ld := (y - yc - 3.0 - 8.0 * (n2 - 0.5)) / 4.5                    # its dark dust lane
	var lane := exp(-ld * ld)
	var a := band * maxf(0.0, (n1 - 0.24) / 0.5) * (1.0 - 0.7 * lane)
	var dx := fposmod(x - 196.0 + 128.0, 256.0) - 128.0                   # a second, smaller teal-ish cloud
	var dy := y - 34.0
	var p := exp(-(dx * dx) / (2.0 * 34.0 * 34.0) - (dy * dy) / (2.0 * 16.0 * 16.0))
	var b := p * maxf(0.0, (_fbm(x, y, 12, 3, 37) - 0.35) / 0.4)
	var inten := minf(1.0, a * 0.95 + b * 0.7) * clampf((170.0 - y) / 50.0, 0.0, 1.0)
	var hue := clampf(0.45 + 1.6 * (_fbm(x, y, 6, 2, 53) - 0.5) + (0.4 if b > a else 0.0), 0.0, 1.0)
	return Vector2(inten, hue)


## fractal value noise, periodic in x over 256 px (`cells` lattice cells across at the first octave)
func _fbm(x: float, y: float, cells: int, octs: int, s: int) -> float:
	var tot := 0.0
	var amp := 0.5
	var norm := 0.0
	var per := cells
	for o in octs:
		var lat := _lattice(per, s + o * 101)          # value noise: bilinear between lattice values, smoothstep
		var fx := x * per / 256.0
		var fy := y * per / 256.0
		var ix := int(fx)
		var iy := int(fy)
		var ax := fx - ix
		var ay := fy - iy
		ax = ax * ax * (3.0 - 2.0 * ax)
		ay = ay * ay * (3.0 - 2.0 * ay)
		var x0 := ix % per
		var x1 := (ix + 1) % per
		var r0 := iy * per
		var r1 := r0 + per
		var top := lat[r0 + x0] + (lat[r0 + x1] - lat[r0 + x0]) * ax
		var bot := lat[r1 + x0] + (lat[r1 + x1] - lat[r1 + x0]) * ax
		tot += amp * (top + (bot - top) * ay)
		norm += amp
		amp *= 0.5
		per *= 2
	return tot / norm


## lattice values of one noise octave (period `per` in x, rows for y 0..SKY_H), cached
func _lattice(per: int, s: int) -> PackedFloat32Array:
	var k := per * 1000000 + s
	if _lat.has(k):
		return _lat[k]
	var rows := per * SKY_H / 256 + 3
	var l := PackedFloat32Array()
	l.resize(per * rows)
	for iy in rows:
		for ix in per:
			l[iy * per + ix] = _hash(ix, iy, s)
	_lat[k] = l
	return l


func _hash(ix: int, iy: int, s: int) -> float:
	var h := (ix * 374761393 + iy * 668265263 + s * 2246822519) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h ^= h >> 16
	return float(h & 0xFFFF) / 65535.0


func _bg3() -> Array:
	## [chars, map] VRAM addresses of engine A BG3 if it is the Time Chamber's sky as expected, else []
	var cnt: int = g.io_read(0x400000E, 2)
	var disp: int = g.io_read(0x4000000, 4)
	if (cnt & 0x80) == 0 or (cnt & 0xC000) != 0 or (disp & 0x0800) == 0:
		return []                                      # not 256-colour 256x256 / BG3 off
	var chars := 0x06000000 + ((cnt >> 2) & 0xF) * 0x4000 + ((disp >> 24) & 7) * 0x10000
	var mp := 0x06000000 + ((cnt >> 8) & 0x1F) * 0x800 + ((disp >> 27) & 7) * 0x10000
	return [chars, mp]


## our map and tiles still in VRAM (spot checks spread over both; the game re-uploading its own data changes them)
func _is_ours(a: Array) -> bool:
	for i in [0, 37, 200, 300, 333, 450, 777, 1023]:
		if g._ld(a[1] + i * 2, 2, false) != _map.decode_u16(i * 2):
			return false
	var n := _tiles.size() / 64
	for k in 8:
		var o: int = ((n - 1) * k / 7) * 64 + (k * 28) % 64 / 4 * 4
		if g._ld(a[0] + o, 4, false) != _tiles.decode_u32(o):
			return false
	return true


func _sky_tick(st: int) -> void:
	var s: int = g._ld(STAGE_BLK, 4, false)
	if s < 0x02000000 or s >= 0x02400000 or g._ld(s + 0xCBE, 1, false) != QoLAllStar.STAGE_ID:
		return
	if _skylog and g._port_frame() % 10 == 0:
		_log("skylog: st %x BG3CNT %x ofs %d,%d BG2 ofs %d,%d DISPCNT %x BLDCNT %x BLDALPHA %x BLDY %x MB %x" % [st,
			g.io_read(0x400000E, 2), g.io_read(0x400001C, 2), g.io_read(0x400001E, 2), g.io_read(0x4000018, 2),
			g.io_read(0x400001A, 2), g.io_read(0x4000000, 4), g.io_read(0x4000050, 2), g.io_read(0x4000052, 2),
			g.io_read(0x4000054, 2), g.io_read(0x400006C, 2)])
	if st == 9:                                        # pause: nothing touched (the window is drawn by the game)
		return
	if not _rays:
		_hide_rays(s)
	var mgr: int = g._ld(BGMGR, 4, false)
	if mgr < 0x02000000 or mgr >= 0x02400000:
		return
	var a := _bg3()
	if a.is_empty():
		return
	if not _built:
		if _task < 0:
			_task = WorkerThreadPool.add_task(_build, false, "All-Star sky")
		if not WorkerThreadPool.is_task_completed(_task):
			return                                     # not ready yet: the game's own sky meanwhile (a few frames)
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_built = true
		_log("sky: built " + _build_info)
	if not _is_ours(a):
		for o in range(0, _tiles.size(), 4):
			g._st(a[0] + o, 4, _tiles.decode_u32(o))
		for o in range(0, _map.size(), 4):
			g._st(a[1] + o, 4, _map.decode_u32(o))
		var buf: int = g._ld(mgr + 0x1AC + 3 * 4, 4, false)   # the BG manager's own BG3 map copy
		if buf >= 0x02000000 and buf + _map.size() <= 0x02400000:
			for o in range(0, _map.size(), 4):
				g._st(buf + o, 4, _map.decode_u32(o))
		_pal_now = {}
		_sky_n += 1
		_log("sky: space sky %s (BG3 chars %x map %x, map buffer %x, state %x)" % ["applied" if _sky_n == 1 else
			"re-applied #%d" % _sky_n, a[0], a[1], buf, st])
	_palette(mgr)
	_t += 1


## the sky's light-ray curtain: 3D stage objects drawn over BG3 with translucent texels (V: stage 4 objects 5 / 6, the
## horizontally repeating pair with texture 3; hiding them leaves the floor, building, hourglasses and poles as they
## are). Hidden through the object script state's visible flag u16 S+0x44+i*0x3C+0xA (scene init 1; FUN_02019C74 skips
## hidden objects), kept at 0 every frame.
func _hide_rays(s: int) -> void:
	var n: int = mini(g._ld(s + 0x550, 1, false), 16)
	for i in n:
		var o: int = g._ld(s + 4 + i * 4, 4, false)
		if o < 0x02000000 or o >= 0x02400000 or g._ld(o + 0x40, 4, false) != RAY_TEX or g._ld(o + 0x34, 1, false) != 1:
			continue
		var v := s + 0x44 + i * 0x3C + 0xA
		if g._ld(v, 2, false) != 0:
			g._st(v, 2, 0)
			_log("sky: light-ray object %d hidden" % i)


## [palette index, BGR555] of every twinkling entry at twinkle clock t
func _slot_colours(t: int) -> Array:
	var out: Array = []
	for sl in _slots:
		var base: Array = sl[1]
		var col: Array = sl[2]
		var ph: float = sl[6]
		var a := TAU * t / float(sl[5]) + ph
		var w := clampf(0.5 + 0.38 * sin(a) + 0.12 * sin(2.71 * a + 2.0 * ph), 0.0, 1.0)   # slightly irregular
		if float(sl[3]) >= 0.0:                        # 1-pixel star: brightness lo..hi, sharper peaks
			var b: float = sl[3] + (sl[4] - sl[3]) * w * w
			out.append([sl[0], _mix15(base, col, b)])
		else:                                          # glint: centre, arms, outer arms (only near the peak)
			var b := 0.5 + 0.5 * w * w
			out.append([sl[0], _mix15(base, col, b)])
			out.append([sl[0] + 1, _mix15(base, col, b * 0.45)])
			out.append([sl[0] + 2, _mix15(base, col, maxf(0.0, b - 0.55) * 0.55)])
	return out


func _mix15(base: Array, col: Array, b: float) -> int:
	return clampi(roundi(base[0] + (col[0] - base[0]) * b), 0, 31) | (clampi(roundi(base[1] + (col[1] - base[1]) * b),
		0, 31) << 5) | (clampi(roundi(base[2] + (col[2] - base[2]) * b), 0, 31) << 10)


## static entries (ramp + nebula) and the twinkle entries: written to the BG manager's shadow (a re-queued palette
## upload keeps them) and to palette RAM, each only when it differs from what palette RAM holds
func _palette(mgr: int) -> void:
	for i in _static_pal.size():
		_pal_put(mgr, PAL_FIRST + i, _static_pal[i])
	for e in _slot_colours(_t):
		_pal_put(mgr, int(e[0]), int(e[1]))


func _pal_put(mgr: int, p: int, v: int) -> void:
	if _pal_now.get(p, -1) == v and g._ld(0x05000000 + p * 2, 2, false) == v:
		return
	g._st(mgr + 0x1D8 + p * 2, 2, v)
	g._st(0x05000000 + p * 2, 2, v)
	_pal_now[p] = v


# ------------------------------------------------------------------------------------------------ music
func _music_tick(st: int) -> void:
	var a: QoLAllStar = g.allstar
	var fight: bool = st in FIGHT
	if a == null or a.done or not (fight or st == 9):
		_m_since = 0                                   # before FIGHT / after the last KO: nothing, re-base later
		_m_last = -1
		_m_pending = ""
		return
	if (g._ld(BGM + 0xA0, 2, false) & 1) != 0:
		return                                         # sequence mode (not a battle stream)
	var p: int = g._ld(STRM_H, 4, false)
	if p < 0x02000000 or p >= 0x02400000:
		return
	var id: int = g._ld(BGM + 0xA8, 4, false)
	var pos: int = g._ld(p + 0x158, 4, false)
	var info: Array = g.as_strm_info.get(id, [])
	if _m_log and g._port_frame() % 30 == 0:
		_log("music: id %d pos %d / %s step %d since %d A2 %x state %x" % [id, pos, str(info), _m_step, _m_since,
			g._ld(BGM + 0xA2, 2, false), st])
	var forced: bool = fight and not _m_force.is_empty() and g._port_frame() >= int(_m_force[0])
	if fight and not _m_seek.is_empty() and g._port_frame() >= int(_m_seek[0][0]) and not info.is_empty():
		var e: Array = _m_seek.pop_front()            # debug `asmseek=F:S`: restart this track S seconds before its end
		var ms: int = maxi(0, int(float(info[0]) * 1000.0 / float(info[2]) - float(e[1]) * 1000.0))
		g.f_020a453c(STRM_H, 0)                        # stop + start at an offset, as the pause resume does
		g.f_020a4568(STRM_H, id, ms)
		_log("music: track %d restarted at %d ms (asmseek, %s s before the end)" % [id, ms, str(e[1])])
		_m_last = -1
		return
	if fight and a.mode == QoLAllStar.BOSSRUSH and not id in BOSS_POOL and not _m_id in BOSS_POOL and _m_pending == "":
		_switch(id, "boss rush")                       # part 43: a boss theme from the first FIGHT on
		return
	if id != _m_id or _m_last < 0:
		_m_id = id
		_m_last = pos
		_m_since = 0
		if not forced:
			return
	_m_since += 1
	var why := ""
	if forced:
		_m_force.pop_front()
		why = "forced (asmusic)"
	elif info.is_empty():
		return
	elif _m_since > 30 and pos < _m_last:
		why = "wrapped %d -> %d" % [_m_last, pos]
	elif _m_since > 30 and pos > _m_last:
		var rate: int = g._ld(p + 0xC0, 2, false)
		if rate <= 0:
			rate = info[2]
		var left: int = int(info[0]) - pos
		if left <= _m_step + int(rate * 2 / FPS):
			why = "ending: %d of %d samples, %d left" % [pos, info[0], left]
	if pos > _m_last and pos - _m_last <= 2048:       # the counter's block size (a restart's jump ignored)
		_m_step = maxi(_m_step, pos - _m_last)
	_m_last = pos
	if not fight:                                      # pause: the game's BGM keeps playing (V: +0xA2 bit 0 is already
		if why != "" and _m_pending == "":             # set in battle, FUN_0200FD68 does nothing) -> switch at resume
			_m_pending = why
			_log("music: track %d %s during the pause: switch when the fight resumes" % [id, why])
		return
	if why == "" and _m_pending != "":
		why = _m_pending + ", during the pause"
	_m_pending = ""
	if why != "":
		_switch(id, why)


func _switch(cur: int, why: String) -> void:
	var boss: bool = g.allstar.mode == QoLAllStar.BOSSRUSH
	var pool: Array = (BOSS_POOL if boss else POOL).filter(func(n): return n != cur and g.as_strm_info.has(n))
	if pool.is_empty():
		return
	var n: int = pool[_rng.randi_range(0, pool.size() - 1)]
	var a2: int = g._ld(BGM + 0xA2, 2, false)
	var byp: bool = g.music_bypass
	g.music_bypass = true                              # RANDOM MUSIC: the rotation's pick as it is
	g.f_0200fde4(0)                                    # the game's stop (no fade) ...
	g.f_0200fe48(n)                                    # ... and play, as the jukebox does
	g.music_bypass = byp
	g._st(BGM + 0xA2, 2, a2)                           # stopped / paused bit as before (pause / resume keep working)
	_m_switches += 1
	_m_id = n
	_m_last = -1
	_m_since = 0
	_log("music switch #%d: %d -> %d (%s) state %x" % [_m_switches, cur, n, why, g._ld(0x020DD4C5, 1, false)])
