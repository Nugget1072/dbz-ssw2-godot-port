class_name DSSound
extends RefCounted
## The DS sound hardware (GBATEK "DS Sound"), driven at register level by the translated ARM7 sound driver
## (DSArm7 / DSGame7): 16 channels at 0x04000400 + 0x10 * n {CNT, SAD, TMR, PNT, LEN}, SOUNDCNT 0x04000500.
## Channels read their sample data from main RAM while playing (streamed music is written there by the ARM9
## just ahead of playback). The mixer produces 32768 Hz stereo like the DS output.
##
## SOUNDxCNT: 0-6 volume, 8-9 shift (/1 /2 /4 /16), 16-22 pan, 24-26 PSG duty, 27-28 repeat (1 loop, 2 one-shot),
## 29-30 format (PCM8, PCM16, IMA-ADPCM, PSG/noise), 31 start/busy. TMR: rate = 33513982/2 / (0x10000 - TMR).

const MIX_RATE := 32768
const BUS_HZ := 33513982
const TIMER_HZ := 16756991              ## channel timers count at bus/2
const ADPCM_STEP := [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66,
	73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544,
	598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
	3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818,
	18500, 20350, 22385, 24623, 27086, 29794, 32767]
const ADPCM_IDX := [-1, -1, -1, -1, 2, 4, 6, 8]


class Channel:
	var active: bool = false
	var addr: int = 0          ## latched at start
	var loop_start: int = 0    ## words
	var loop_len: int = 0      ## words
	var pos: float = 0.0       ## sample index (fractional)
	var adpcm_pos: int = -1
	var adpcm_val: int = 0
	var adpcm_idx: int = 0
	var adpcm_loop_val: int = 0
	var adpcm_loop_idx: int = 0
	var lfsr: int = 0x7FFF
	var noise_out: int = 0
	var noise_pos: int = -1


var core                               ## ARM9 core (main RAM)
var regs := PackedByteArray()          ## 0x04000400-0x0400051F
var ch: Array = []
var out := PackedVector2Array()         ## mixed samples not yet taken by the audio player
var _cycle_acc: float = 0.0
## QoL Music / Sound effects switches: channels whose bit is set are mixed silently (they keep playing, so
## switching back on resumes mid-note). Set every frame by GameDS from QoLSound.music_mask().
var mute_mask: int = 0:
	set(v):
		mute_mask = v
		if native != null:
			native.set_mute_mask(v)


## The native mixer (native/src/ds_sound_native.cpp, identical output) when the library is present;
## `sndnative=0` forces this GDScript one (the debug flags sndstat/sndcnt read the GDScript channel state).
## (Reads the command line itself: DSSound also runs without the Game autoload, in tools/lockstep.gd.)
var native = ClassDB.instantiate("DSSoundNative") if ClassDB.class_exists("DSSoundNative") and not _gd_mixer() else null


static func _gd_mixer() -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "sndnative=0" or a.begins_with("sndstat") or a.begins_with("sndcnt"):
			return true
	return false


func _init(c) -> void:
	core = c
	regs.resize(0x120)
	for i in 16:
		ch.append(Channel.new())


## mixed samples since the last call (the audio player takes them every frame)
func take_out() -> PackedVector2Array:
	if native != null:
		return native.take_out()
	var o := out
	out = PackedVector2Array()
	return o


func read(o: int, size: int) -> int:
	if native != null:
		return native.read(o, size)
	var v := 0
	for k in size:
		var a := o + k
		if a >= 0 and a < 0x120:
			v |= regs[a] << (8 * k)
	return v


func write(o: int, size: int, v: int) -> void:
	if native != null:
		native.write(o, size, v, [core.M])
		return
	flush()
	for k in size:
		var a := o + k
		if a < 0 or a >= 0x120:
			continue
		var b := (v >> (8 * k)) & 0xFF
		if a < 0x100 and (a & 15) == 3:   # SOUNDxCNT bit 31: start / stop
			var n := a >> 4
			var was := regs[a] & 0x80
			regs[a] = b
			if (b & 0x80) != 0 and was == 0:
				_start(n)
			elif (b & 0x80) == 0:
				ch[n].active = false
		else:
			regs[a] = b


func _start(n: int) -> void:
	var c: Channel = ch[n]
	var o := n * 16
	c.active = true
	c.addr = regs.decode_u32(o + 4) & 0x07FFFFFC
	c.loop_start = regs.decode_u16(o + 10)
	c.loop_len = regs.decode_u32(o + 12) & 0x3FFFFF
	c.pos = 0.0
	c.adpcm_pos = -1
	c.noise_pos = -1
	c.lfsr = 0x7FFF


func _stop(n: int) -> void:
	ch[n].active = false
	regs[n * 16 + 3] &= 0x7F


## emulated time passes: the elapsed time is mixed to `out` in blocks (and before any register write, so
## register changes take effect at the right sample)
func advance(cycles: int) -> void:
	if native != null:
		native.advance(cycles, [core.M])
		return
	_cycle_acc += cycles * float(MIX_RATE) / BUS_HZ
	if _cycle_acc >= 128.0:
		flush()


func flush() -> void:
	if native != null:
		native.flush([core.M])
		return
	var n := int(_cycle_acc)
	if n > 0:
		_cycle_acc -= n
		_mix(n)


func _mix(n: int) -> void:
	if out.size() > MIX_RATE * 4:   # nobody is taking the audio (headless tools): keep the last second only
		out = out.slice(out.size() - MIX_RATE)
	var base := out.size()
	out.resize(base + n)
	var scnt := regs.decode_u16(0x100)
	if (scnt & 0x8000) == 0:
		return
	var acc_l := PackedFloat32Array()
	var acc_r := PackedFloat32Array()
	acc_l.resize(n)
	acc_r.resize(n)
	var any := false
	var mv := (scnt & 0x7F) / 128.0
	var mem: PackedByteArray = core.M
	for i in 16:
		var c: Channel = ch[i]
		if not c.active:
			continue
		any = true
		var o := i * 16
		var cnt := regs.decode_u32(o)
		var tmr := regs.decode_u16(o + 8)
		var step := float(TIMER_HZ) / (0x10000 - tmr) / MIX_RATE
		var vol := cnt & 0x7F
		var div := float([1, 2, 4, 16][(cnt >> 8) & 3])
		var pan := (cnt >> 16) & 0x7F
		# DS mixer: sample * volume/128 >> shift, panned (128 - pan)/128 : pan/128, * master/128 (level checked
		# against melonDS captures of the intro music)
		var gain := vol / 128.0 / div * mv / 32768.0
		if (mute_mask >> i) & 1:
			gain = 0.0
		var gl := gain * (128 - pan) / 128.0
		var gr := gain * pan / 128.0
		var fmt := (cnt >> 29) & 3
		var rep := (cnt >> 27) & 3
		if fmt == 1 or fmt == 0:
			# PCM: tight loop over main RAM
			var total_bytes := (c.loop_start + c.loop_len) * 4
			var n_samples := total_bytes if fmt == 0 else total_bytes / 2
			var loop_s := c.loop_start * 4 if fmt == 0 else c.loop_start * 2
			var off := (c.addr & 0x3FFFFF)
			var pos := c.pos
			for k in n:
				var p := int(pos)
				if p >= n_samples:
					if rep == 1 and n_samples > loop_s:
						var ll := n_samples - loop_s
						pos -= float(((p - loop_s) / ll) * ll)
						p = int(pos)
					else:
						c.active = false
						break
				var v: float
				if fmt == 1:
					v = mem.decode_s16(off + p * 2)
				else:
					v = mem.decode_s8(off + p) * 256
				acc_l[k] += v * gl
				acc_r[k] += v * gr
				pos += step
			c.pos = pos
			if not c.active:
				_stop(i)
			continue
		for k in n:
			var smp := _sample(i, c, fmt, rep, cnt)
			if not c.active:
				_stop(i)
				break
			acc_l[k] += smp * gl
			acc_r[k] += smp * gr
			c.pos += step
	if any:
		for k in n:
			out[base + k] = Vector2(acc_l[k], acc_r[k])


## current sample of a channel (16-bit range), handling loops / end of one-shot data
func _sample(i: int, c: Channel, fmt: int, rep: int, cnt: int) -> int:
	if fmt == 3:
		if i >= 14:   # noise
			var pn := int(c.pos)
			while c.noise_pos < pn:
				c.noise_pos += 1
				var carry := c.lfsr & 1
				c.lfsr >>= 1
				if carry:
					c.lfsr ^= 0x6000
				c.noise_out = -0x7FFF if carry else 0x7FFF
			return c.noise_out
		if i >= 8:    # PSG square wave, duty (n+1)/8
			var duty := (cnt >> 24) & 7
			return 0x7FFF if (int(c.pos) & 7) > (6 - duty) else -0x7FFF
		return 0
	var total_bytes := (c.loop_start + c.loop_len) * 4
	var n_samples := total_bytes if fmt == 0 else (total_bytes / 2 if fmt == 1 else (total_bytes - 4) * 2)
	var loop_s := c.loop_start * 4 if fmt == 0 else (c.loop_start * 2 if fmt == 1 else (c.loop_start * 4 - 4) * 2)
	var p := int(c.pos)
	if p >= n_samples:
		if rep == 1 and n_samples > loop_s:
			var ll := n_samples - loop_s
			c.pos -= float(((p - loop_s) / ll) * ll)
			p = int(c.pos)
		else:
			c.active = false
			return 0
	match fmt:
		0:
			var b: int = core.r8(c.addr + p)
			return (b - 256 if b >= 128 else b) << 8
		1:
			var v: int = core.r16(c.addr + p * 2)
			return v - 65536 if v >= 32768 else v
	return _adpcm(c, p, loop_s)


func _adpcm(c: Channel, p: int, loop_s: int) -> int:
	if c.adpcm_pos < 0 or p < c.adpcm_pos:
		if c.adpcm_pos >= 0 and p >= loop_s and loop_s > 0:
			# looped: the hardware reloads the state it saved at the loop start
			c.adpcm_val = c.adpcm_loop_val
			c.adpcm_idx = c.adpcm_loop_idx
			c.adpcm_pos = loop_s - 1
		else:
			var hdr: int = core.r32(c.addr)
			c.adpcm_val = hdr & 0xFFFF
			if c.adpcm_val >= 32768:
				c.adpcm_val -= 65536
			c.adpcm_idx = clampi((hdr >> 16) & 0x7F, 0, 88)
			c.adpcm_pos = -1
			if loop_s == 0:
				c.adpcm_loop_val = c.adpcm_val
				c.adpcm_loop_idx = c.adpcm_idx
	while c.adpcm_pos < p:
		_adpcm_step(c)
		if c.adpcm_pos == loop_s - 1:
			c.adpcm_loop_val = c.adpcm_val
			c.adpcm_loop_idx = c.adpcm_idx
	return c.adpcm_val


func _adpcm_step(c: Channel) -> void:
	c.adpcm_pos += 1
	var byte: int = core.r8(c.addr + 4 + (c.adpcm_pos >> 1))
	var nib := (byte >> 4) if (c.adpcm_pos & 1) else (byte & 15)
	var st: int = ADPCM_STEP[c.adpcm_idx]
	var diff := st >> 3
	if nib & 1:
		diff += st >> 2
	if nib & 2:
		diff += st >> 1
	if nib & 4:
		diff += st
	if nib & 8:
		c.adpcm_val = maxi(c.adpcm_val - diff, -0x7FFF)
	else:
		c.adpcm_val = mini(c.adpcm_val + diff, 0x7FFF)
	c.adpcm_idx = clampi(c.adpcm_idx + ADPCM_IDX[nib & 7], 0, 88)
