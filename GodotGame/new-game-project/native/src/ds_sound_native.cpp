// See ds_sound_native.h; every function mirrors the GDScript function of the same name in ds_sound.gd.
#include "ds_sound_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/variant_internal.hpp>

#include <cstring>

using namespace godot;

namespace {
const int64_t MIX_RATE = 32768;
const int64_t BUS_HZ = 33513982;
const int64_t TIMER_HZ = 16756991;
const int64_t ADPCM_STEP[89] = { 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60,
	66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598,
	658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026,
	4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385,
	24623, 27086, 29794, 32767 };
const int64_t ADPCM_IDX[8] = { -1, -1, -1, -1, 2, 4, 6, 8 };
inline int64_t clampi(int64_t v, int64_t lo, int64_t hi) { return v < lo ? lo : (v > hi ? hi : v); }
} // namespace

DSSoundNative::DSSoundNative() { memset(regs, 0, sizeof(regs)); }

void DSSoundNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("read", "o", "size"), &DSSoundNative::read);
	ClassDB::bind_method(D_METHOD("write", "o", "size", "v", "mem"), &DSSoundNative::write);
	ClassDB::bind_method(D_METHOD("advance", "cycles", "mem"), &DSSoundNative::advance);
	ClassDB::bind_method(D_METHOD("flush", "mem"), &DSSoundNative::flush);
	ClassDB::bind_method(D_METHOD("take_out"), &DSSoundNative::take_out);
	ClassDB::bind_method(D_METHOD("active_mask"), &DSSoundNative::active_mask);
	ClassDB::bind_method(D_METHOD("set_mute_mask", "mask"), &DSSoundNative::set_mute_mask);
}

void DSSoundNative::bind_mem(const Array &m) {
	mem = nullptr;
	mem_size = 0;
	if (m.size() < 1) return;
	const Variant &v = m[0];
	if (v.get_type() != Variant::PACKED_BYTE_ARRAY) return;
	const PackedByteArray *pa = VariantInternal::get_byte_array(&v);
	mem = pa->ptr();
	mem_size = pa->size();
}

// main RAM reads like DSCoreBase.r8/r16/r32 for 0x02000000-0x027FFFFF (sample data); 0 elsewhere
int64_t DSSoundNative::r8(int64_t a) const {
	a &= 0xFFFFFFFF;
	const int64_t o = a - 0x2000000;
	if (!mem || o < 0 || o >= mem_size || a >= 0x2800000) return 0;
	return mem[o];
}
int64_t DSSoundNative::r16(int64_t a) const { return r8(a) | (r8(a + 1) << 8); }
int64_t DSSoundNative::r32(int64_t a) const { return r16(a) | (r16(a + 2) << 16); }

int64_t DSSoundNative::read(int64_t o, int64_t size) const {
	int64_t v = 0;
	for (int64_t k = 0; k < size; k++) {
		const int64_t a = o + k;
		if (a >= 0 && a < 0x120) v |= (int64_t)regs[a] << (8 * k);
	}
	return v;
}

void DSSoundNative::write(int64_t o, int64_t size, int64_t v, const Array &m) {
	flush(m);
	for (int64_t k = 0; k < size; k++) {
		const int64_t a = o + k;
		if (a < 0 || a >= 0x120) continue;
		const uint8_t b = (uint8_t)((v >> (8 * k)) & 0xFF);
		if (a < 0x100 && (a & 15) == 3) {
			const int n = (int)(a >> 4);
			const uint8_t was = regs[a] & 0x80;
			regs[a] = b;
			if ((b & 0x80) != 0 && was == 0)
				start(n);
			else if ((b & 0x80) == 0)
				ch[n].active = false;
		} else {
			regs[a] = b;
		}
	}
}

void DSSoundNative::start(int n) {
	Channel &c = ch[n];
	const int o = n * 16;
	c.active = true;
	c.addr = u32(o + 4) & 0x07FFFFFC;
	c.loop_start = u16(o + 10);
	c.loop_len = u32(o + 12) & 0x3FFFFF;
	c.pos = 0.0;
	c.adpcm_pos = -1;
	c.noise_pos = -1;
	c.lfsr = 0x7FFF;
}

void DSSoundNative::stop(int n) {
	ch[n].active = false;
	regs[n * 16 + 3] &= 0x7F;
}

void DSSoundNative::advance(int64_t cycles, const Array &m) {
	cycle_acc += (double)cycles * (double)MIX_RATE / (double)BUS_HZ;
	if (cycle_acc >= 128.0) flush(m);
}

void DSSoundNative::flush(const Array &m) {
	const int64_t n = (int64_t)cycle_acc;
	if (n > 0) {
		cycle_acc -= (double)n;
		bind_mem(m);
		mix(n);
	}
}

PackedVector2Array DSSoundNative::take_out() {
	PackedVector2Array a;
	a.resize(out.size());
	if (!out.empty()) memcpy(a.ptrw(), out.data(), out.size() * sizeof(Vector2));
	out.clear();
	return a;
}

int64_t DSSoundNative::active_mask() const {
	int64_t m = 0;
	for (int i = 0; i < 16; i++)
		if (ch[i].active) m |= int64_t(1) << i;
	return m;
}

void DSSoundNative::mix(int64_t n) {
	if ((int64_t)out.size() > MIX_RATE * 4) out.erase(out.begin(), out.end() - MIX_RATE);
	const size_t base = out.size();
	out.resize(base + n, Vector2());
	const int64_t scnt = u16(0x100);
	if ((scnt & 0x8000) == 0) return;
	std::vector<float> acc_l(n, 0.0f), acc_r(n, 0.0f);
	bool any = false;
	const double mv = (double)(scnt & 0x7F) / 128.0;
	static const double DIVS[4] = { 1.0, 2.0, 4.0, 16.0 };
	for (int i = 0; i < 16; i++) {
		Channel &c = ch[i];
		if (!c.active) continue;
		any = true;
		const int o = i * 16;
		const int64_t cnt = u32(o);
		const int64_t tmr = u16(o + 8);
		const double step = (double)TIMER_HZ / (double)(0x10000 - tmr) / (double)MIX_RATE;
		const int64_t vol = cnt & 0x7F;
		const double div = DIVS[(cnt >> 8) & 3];
		const int64_t pan = (cnt >> 16) & 0x7F;
		const double gain = ((mute_mask >> i) & 1) ? 0.0 : (double)vol / 128.0 / div * mv / 32768.0;
		const double gl = gain * (double)(128 - pan) / 128.0;
		const double gr = gain * (double)pan / 128.0;
		const int64_t fmt = (cnt >> 29) & 3;
		const int64_t rep = (cnt >> 27) & 3;
		if (fmt == 1 || fmt == 0) {
			const int64_t total_bytes = (c.loop_start + c.loop_len) * 4;
			const int64_t n_samples = fmt == 0 ? total_bytes : total_bytes / 2;
			const int64_t loop_s = fmt == 0 ? c.loop_start * 4 : c.loop_start * 2;
			const int64_t off = c.addr & 0x3FFFFF;
			double pos = c.pos;
			for (int64_t k = 0; k < n; k++) {
				int64_t p = (int64_t)pos;
				if (p >= n_samples) {
					if (rep == 1 && n_samples > loop_s) {
						const int64_t ll = n_samples - loop_s;
						pos -= (double)(((p - loop_s) / ll) * ll);
						p = (int64_t)pos;
					} else {
						c.active = false;
						break;
					}
				}
				double v;
				if (fmt == 1) {
					const int64_t a = off + p * 2;
					v = (mem && a >= 0 && a + 2 <= mem_size) ? (double)(int16_t)(mem[a] | (mem[a + 1] << 8)) : 0.0;
				} else {
					const int64_t a = off + p;
					v = (mem && a >= 0 && a < mem_size) ? (double)((int64_t)(int8_t)mem[a] * 256) : 0.0;
				}
				acc_l[k] = (float)((double)acc_l[k] + v * gl);
				acc_r[k] = (float)((double)acc_r[k] + v * gr);
				pos += step;
			}
			c.pos = pos;
			if (!c.active) stop(i);
			continue;
		}
		for (int64_t k = 0; k < n; k++) {
			const int64_t smp = sample(i, c, fmt, rep, cnt);
			if (!c.active) {
				stop(i);
				break;
			}
			acc_l[k] = (float)((double)acc_l[k] + (double)smp * gl);
			acc_r[k] = (float)((double)acc_r[k] + (double)smp * gr);
			c.pos += step;
		}
	}
	if (any)
		for (int64_t k = 0; k < n; k++) out[base + k] = Vector2(acc_l[k], acc_r[k]);
}

int64_t DSSoundNative::sample(int i, Channel &c, int64_t fmt, int64_t rep, int64_t cnt) {
	if (fmt == 3) {
		if (i >= 14) {
			const int64_t pn = (int64_t)c.pos;
			while (c.noise_pos < pn) {
				c.noise_pos += 1;
				const int64_t carry = c.lfsr & 1;
				c.lfsr >>= 1;
				if (carry) c.lfsr ^= 0x6000;
				c.noise_out = carry ? -0x7FFF : 0x7FFF;
			}
			return c.noise_out;
		}
		if (i >= 8) {
			const int64_t duty = (cnt >> 24) & 7;
			return (((int64_t)c.pos & 7) > (6 - duty)) ? 0x7FFF : -0x7FFF;
		}
		return 0;
	}
	const int64_t total_bytes = (c.loop_start + c.loop_len) * 4;
	const int64_t n_samples = fmt == 0 ? total_bytes : (fmt == 1 ? total_bytes / 2 : (total_bytes - 4) * 2);
	const int64_t loop_s = fmt == 0 ? c.loop_start * 4 : (fmt == 1 ? c.loop_start * 2 : (c.loop_start * 4 - 4) * 2);
	int64_t p = (int64_t)c.pos;
	if (p >= n_samples) {
		if (rep == 1 && n_samples > loop_s) {
			const int64_t ll = n_samples - loop_s;
			c.pos -= (double)(((p - loop_s) / ll) * ll);
			p = (int64_t)c.pos;
		} else {
			c.active = false;
			return 0;
		}
	}
	switch (fmt) {
		case 0: {
			const int64_t b = r8(c.addr + p);
			return (b >= 128 ? b - 256 : b) << 8;
		}
		case 1: {
			const int64_t v = r16(c.addr + p * 2);
			return v >= 32768 ? v - 65536 : v;
		}
	}
	return adpcm(c, p, loop_s);
}

int64_t DSSoundNative::adpcm(Channel &c, int64_t p, int64_t loop_s) {
	if (c.adpcm_pos < 0 || p < c.adpcm_pos) {
		if (c.adpcm_pos >= 0 && p >= loop_s && loop_s > 0) {
			c.adpcm_val = c.adpcm_loop_val;
			c.adpcm_idx = c.adpcm_loop_idx;
			c.adpcm_pos = loop_s - 1;
		} else {
			const int64_t hdr = r32(c.addr);
			c.adpcm_val = hdr & 0xFFFF;
			if (c.adpcm_val >= 32768) c.adpcm_val -= 65536;
			c.adpcm_idx = clampi((hdr >> 16) & 0x7F, 0, 88);
			c.adpcm_pos = -1;
			if (loop_s == 0) {
				c.adpcm_loop_val = c.adpcm_val;
				c.adpcm_loop_idx = c.adpcm_idx;
			}
		}
	}
	while (c.adpcm_pos < p) {
		adpcm_step(c);
		if (c.adpcm_pos == loop_s - 1) {
			c.adpcm_loop_val = c.adpcm_val;
			c.adpcm_loop_idx = c.adpcm_idx;
		}
	}
	return c.adpcm_val;
}

void DSSoundNative::adpcm_step(Channel &c) {
	c.adpcm_pos += 1;
	const int64_t byte = r8(c.addr + 4 + (c.adpcm_pos >> 1));
	const int64_t nib = (c.adpcm_pos & 1) ? (byte >> 4) : (byte & 15);
	const int64_t st = ADPCM_STEP[c.adpcm_idx];
	int64_t diff = st >> 3;
	if (nib & 1) diff += st >> 2;
	if (nib & 2) diff += st >> 1;
	if (nib & 4) diff += st;
	if (nib & 8)
		c.adpcm_val = c.adpcm_val - diff > -0x7FFF ? c.adpcm_val - diff : -0x7FFF;
	else
		c.adpcm_val = c.adpcm_val + diff < 0x7FFF ? c.adpcm_val + diff : 0x7FFF;
	c.adpcm_idx = clampi(c.adpcm_idx + ADPCM_IDX[nib & 7], 0, 88);
}
