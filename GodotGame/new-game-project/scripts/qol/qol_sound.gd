class_name QoLSound
extends RefCounted
## Quality-of-life sound features on top of the original sound code (nothing in the game is changed):
## - which hardware channels currently play music (for the Music / Sound effects switches), read from the
##   ARM7 sound driver's own structures every frame;
## - the Jukebox: every music track in the game's sound archive, played through the game's own BGM functions.
##
## Music in this game is either a stream (STRM: the ARM9 stream library plays hardware channels 6/7 directly,
## no driver channel owns them) or a MIDI sequence (SEQ)
## played on the BGM handle. SDAT player numbers are not the ARM7 player numbers (the NNS library allocates
## those), so a sequence is recognised by its data: track 0's base pointer is the start of the SSEQ data the
## game loaded, compared with the BGM sequences of the ROM's sound archive. (DATA_NOTES "QoL sound".)

# ARM7 sound driver (NitroSDK SND, ARM7 WRAM) - addresses from the translated driver (ds_game7.gd)
const SND_CHANNELS := 0x038085DC     ## SNDExChannel[16], 0x54 bytes: +0 hw channel, +3 flags (bit 0 active), +0x4C callback data
const SND_PLAYERS := 0x03808B1C      ## SNDPlayer[16], 0x24 bytes: +0 flags (bit 0 active), +8 tracks[16] (0xFF = none)
const SND_TRACKS := 0x03808D5C       ## SNDTrack[32], 0x40 bytes: +0x24 sequence data base pointer (main RAM)
# ARM9 game: BGM manager (0x020DE2A0 struct, functions at 0x0200FCA0..0x0201005C)
const BGM_MGR := 0x020DE2A0          ## +0xA0 u16 mode (bit 0: 1 = sequences, 0 = streams), +0xA2 bit 0 paused, +0xA8 current id

var core                              ## DSGame (ARM9)
var arm7                              ## DSGame7 (the translated ARM7 sound driver: its WRAM)
var snd: DSSound
var tracks: Array = []                ## jukebox list: {kind "seq"/"strm", id, name}
var _bgm_sigs: Dictionary = {}        ## first 16 bytes of each BGM sequence's data -> true
var ok: bool = false                  ## sound archive found

# jukebox state
var jb_active: bool = false
var jb_index: int = 0
var jb_playing: bool = false
var jb_message: String = ""
var _orig_mode: int = 0
var _orig_id: int = 0
var _heap_level: int = -1


func setup(c, rom: PackedByteArray) -> void:
	core = c
	arm7 = c.arm7.core7
	snd = c.arm7.sound
	var sdat := _find_sdat(rom)
	if sdat < 0:
		return
	_parse(rom, sdat)
	ok = not tracks.is_empty()
	if core is QoLGame:
		core.as_strm_info = strm_info     # part 34: All-Star music rotation (track lengths)


# ------------------------------------------------------------------------------------------------ sound archive
## The SDAT inside the NitroFS (sound/sound_data.sdat): found by its header (magic, BOM, block count, size).
static func _find_sdat(rom: PackedByteArray) -> int:
	var i := 0
	while true:
		i = _find(rom, "SDAT".to_ascii_buffer(), i)
		if i < 0:
			return -1
		if rom.decode_u16(i + 4) == 0xFEFF and rom.decode_u32(i + 8) > 0x40 and i + rom.decode_u32(i + 8) <= rom.size():
			return i
		i += 4
	return -1


static func _find(hay: PackedByteArray, needle: PackedByteArray, from: int) -> int:
	var n := needle.size()
	var i := from - (from & 3)
	while i + n <= hay.size():
		if hay[i] == needle[0] and hay.slice(i, i + n) == needle:
			return i
		i += 4
	return -1


## bytes the game's loader (f_0200FE98) puts in the sound heap for BGM sequence i: sequence + bank + wave archives
var seq_size := {}
## part 34 (All-Star music rotation): STRM id -> [samples, loop start, rate] from the file's HEAD block
var strm_info := {}


static func _seq_load_size(rom: PackedByteArray, s: int, info: int, fat: int, e: int) -> int:
	var fsize := func(fid: int) -> int: return rom.decode_u32(fat + 12 + 16 * fid + 4)
	var n: int = fsize.call(rom.decode_u16(e))
	var bank := rom.decode_u16(e + 4)
	var brec := info + rom.decode_u32(info + 8 + 4 * 2)
	if bank < rom.decode_u32(brec):
		var be := info + rom.decode_u32(brec + 4 + 4 * bank)
		n += fsize.call(rom.decode_u16(be))
		var wrec := info + rom.decode_u32(info + 8 + 4 * 3)
		for k in 4:
			var wa := rom.decode_u16(be + 4 + 2 * k)
			if wa != 0xFFFF and wa < rom.decode_u32(wrec):
				var we := info + rom.decode_u32(wrec + 4 + 4 * wa)
				n += fsize.call(rom.decode_u16(we))
	return n


func _parse(rom: PackedByteArray, s: int) -> void:
	var symb := s + rom.decode_u32(s + 0x10)
	var info := s + rom.decode_u32(s + 0x18)
	var fat := s + rom.decode_u32(s + 0x20)
	var has_symb := rom.decode_u32(s + 0x10) != 0
	var file_of := func(fid: int) -> PackedByteArray:
		var o := s + rom.decode_u32(fat + 12 + 16 * fid)
		return rom.slice(o, o + rom.decode_u32(fat + 12 + 16 * fid + 4))
	var name_of := func(kind: int, i: int) -> String:
		if not has_symb:
			return ""
		var rec := symb + rom.decode_u32(symb + 8 + 4 * kind)
		if i >= rom.decode_u32(rec):
			return ""
		var no := rom.decode_u32(rec + 4 + 4 * i)
		if no == 0:
			return ""
		var e := rom.find(0, symb + no)
		return rom.slice(symb + no, e).get_string_from_ascii()
	# INFO record 0 = SEQ (u16 file, u16, u16 bank, u8 vol, cpr, ppr, player at +9), 7 = STRM (u16 file, u16, vol, prio, player at +6)
	for kind in [0, 7]:
		var rec := info + rom.decode_u32(info + 8 + 4 * kind)
		var n := rom.decode_u32(rec)
		for i in n:
			var eo := rom.decode_u32(rec + 4 + 4 * i)
			if eo == 0:
				continue
			var e := info + eo
			var player := rom.decode_u8(e + (9 if kind == 0 else 6))
			var nm: String = name_of.call(kind, i)
			if kind == 0:
				if player != 0:   # SDAT player 0 = PLAYER_BGM: the game's MIDI music
					continue
				var f: PackedByteArray = file_of.call(rom.decode_u16(e))
				if f.size() > 0x20 and f.slice(0, 4).get_string_from_ascii() == "SSEQ":
					var d := f.decode_u32(0x18)
					_bgm_sigs[f.slice(d, d + 16).hex_encode()] = true
				tracks.append({"kind": "seq", "id": i, "name": _pretty(nm, "SEQ", i)})
				seq_size[i] = _seq_load_size(rom, s, info, fat, e)
			else:
				tracks.append({"kind": "strm", "id": i, "name": _pretty(nm, "STRM", i)})
				var so := s + rom.decode_u32(fat + 12 + 16 * rom.decode_u16(e))   # the file's header only (no copy)
				if so + 0x28 <= rom.size() and rom.slice(so + 0x10, so + 0x14).get_string_from_ascii() == "HEAD":
					strm_info[i] = [rom.decode_u32(so + 0x24), rom.decode_u32(so + 0x20), rom.decode_u16(so + 0x1C)]
	# streams first (the battle music), then the MIDI pieces, like the game's own order of use
	var st := tracks.filter(func(t): return t["kind"] == "strm")
	var sq := tracks.filter(func(t): return t["kind"] == "seq")
	tracks = st + sq


## "STRM_BGM_BOSS1" -> "BOSS 1", "SEQ_BGMMIDI_CHARASELE" -> "CHARA SELE"
static func _pretty(nm: String, kind: String, i: int) -> String:
	if nm == "":
		return "%s %d" % [kind, i]
	var t := nm.to_upper()
	for p in ["STRM_BGM_", "SEQ_BGMMIDI_", "SEQ_BGM_", "STRM_", "SEQ_"]:
		if t.begins_with(p):
			t = t.substr(p.length())
			break
	t = t.replace("_", " ")
	if t.is_valid_int():
		t = "BGM " + t
	var r := RegEx.new()
	r.compile("([A-Z])([0-9]+)$")
	t = r.sub(t, "$1 $2")
	return t


# ------------------------------------------------------------------------------------------------ music channels
## bit n set = hardware channel n plays music now (stream channels + notes of BGM sequences)
func music_mask() -> int:
	if arm7 == null:
		arm7 = core.arm7.core7   # created when the sound driver boots
		if arm7 == null:
			return 0
	# streams: the stream library drives its (locked) hardware channels directly, without a driver channel
	var hw: int = snd.native.active_mask() if snd.native != null else 0
	if snd.native == null:
		for i in 16:
			if snd.ch[i].active:
				hw |= 1 << i
	var driver := 0
	for c in 16:
		var ca := SND_CHANNELS + c * 0x54
		if (arm7._ld(ca + 3, 1, false) & 1) != 0:
			driver |= 1 << (arm7._ld(ca, 1, false) & 15)
	var mask: int = hw & ~driver
	var bgm_tracks := {}
	for p in 16:
		var pa := SND_PLAYERS + p * 0x24
		if (arm7._ld(pa, 1, false) & 1) == 0:
			continue
		var t0: int = arm7._ld(pa + 8, 1, false)
		if t0 == 0xFF:
			continue
		var base: int = arm7._ld(SND_TRACKS + t0 * 0x40 + 0x24, 4, false)
		if base < 0x02000000 or base >= 0x02400000:
			continue
		var o: int = base - 0x02000000
		if not _bgm_sigs.has(core.M.slice(o, o + 16).hex_encode()):
			continue
		for k in 16:
			var t: int = arm7._ld(pa + 8 + k, 1, false)
			if t != 0xFF:
				bgm_tracks[SND_TRACKS + t * 0x40] = true
	if bgm_tracks.is_empty():
		return mask
	for c in 16:
		var ca := SND_CHANNELS + c * 0x54
		if (arm7._ld(ca + 3, 1, false) & 1) != 0 and bgm_tracks.has(arm7._ld(ca + 0x4C, 4, false)):
			mask |= 1 << (arm7._ld(ca, 1, false) & 15)
	return mask


# ------------------------------------------------------------------------------------------------ jukebox
## These run on the game thread at the start of a frame (DSMachine.inject), where the game itself calls them.
func jb_start() -> void:
	jb_active = true
	jb_playing = false
	jb_message = ""
	_orig_mode = core.r16(BGM_MGR + 0xA0)
	_orig_id = core.r32(BGM_MGR + 0xA8)
	_heap_level = core.f_02010044()   # NNS_SndHeapSaveState: everything the jukebox loads goes above this


## the jukebox plays exactly the chosen track (RANDOM MUSIC does not apply to it)
func jb_play(i: int) -> void:
	_bypass(true)
	_jb_play(i)
	_bypass(false)


func jb_stop() -> void:
	_bypass(true)
	_jb_stop()
	_bypass(false)


func _bypass(on: bool) -> void:
	if core is QoLGame:
		core.music_bypass = on


func _jb_play(i: int) -> void:
	jb_index = i
	var t: Dictionary = tracks[i]
	core.f_0200fde4(0)                                  # stop the current BGM (no fade)
	if t["kind"] == "seq":
		core.f_0200fee0(_orig_mode | 1)                 # BGM mode: sequences
		if _heap_level >= 0:
			core.f_02010028(_heap_level)                # free the previous jukebox sequence
		if core.f_0200fe98(t["id"]) == 0:               # load sequence + bank + waves into the sound heap
			jb_message = "COULD NOT LOAD"
			jb_playing = false
			return
	else:
		core.f_0200fee0(_orig_mode & ~1)                # BGM mode: streams
	core.f_0200fe48(t["id"])                            # the game's PlayBGM
	jb_playing = true
	jb_message = ""
	if Game.args.has("qoldbg"):
		print("QOL jukebox play %d %s %s id %d -> mode %x bgm %d" % [i, t["kind"], t["name"], t["id"], core.r16(BGM_MGR + 0xA0), core.r32(BGM_MGR + 0xA8)])


func jb_pause() -> void:
	core.f_0200fd68(0, 0, 0, 0)
	jb_playing = false


func jb_resume() -> void:
	core.f_0200fcf8()
	jb_playing = true


## back to what Mode Select was playing
func _jb_stop() -> void:
	if not jb_active:
		return
	core.f_0200fde4(0)
	if _heap_level >= 0:
		core.f_02010028(_heap_level)
	core.f_0200fee0(_orig_mode)
	core.f_0200fe48(_orig_id)
	jb_active = false
	jb_playing = false


func debug_dump() -> void:
	if music_mask() < 0 or arm7 == null:
		return
	print("QOLSND music %04x sigs %d" % [music_mask(), _bgm_sigs.size()])
	for p in 16:
		var pa := SND_PLAYERS + p * 0x24
		var fl: int = arm7._ld(pa, 1, false)
		if fl == 0:
			continue
		var tr := []
		for k in 16:
			tr.append(arm7._ld(pa + 8 + k, 1, false))
		var t0: int = tr[0]
		var base: int = arm7._ld(SND_TRACKS + t0 * 0x40 + 0x24, 4, false) if t0 != 0xFF else 0
		var sig: String = core.M.slice(base - 0x02000000, base - 0x02000000 + 16).hex_encode() if base >= 0x02000000 and base < 0x02400000 else "-"
		print("QOLSND player %d flags %02x tracks %s base %08x sig %s bgm %s" % [p, fl, str(tr.slice(0, 4)), base, sig, _bgm_sigs.has(sig)])
		var raw := []
		for k in 0x40:
			raw.append("%02x" % arm7._ld(SND_TRACKS + t0 * 0x40 + k, 1, false))
		print("QOLSND   track %d: %s" % [t0, "".join(raw)])
	for c in 16:
		var ca := SND_CHANNELS + c * 0x54
		var f3: int = arm7._ld(ca + 3, 1, false)
		if f3 & 1:
			print("QOLSND ch %d hw %d flags %02x cb %08x data %08x" % [c, arm7._ld(ca, 1, false), f3, arm7._ld(ca + 0x48, 4, false), arm7._ld(ca + 0x4C, 4, false)])
