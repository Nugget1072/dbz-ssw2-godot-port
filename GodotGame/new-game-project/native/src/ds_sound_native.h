// Native DS sound mixer: a C++ port of scripts/core/ds_sound.gd (DSSound) with the same arithmetic (doubles
// where the script uses floats, float32 accumulators like its PackedFloat32Array), so the output is identical.
// Main RAM (sample data) is passed as an Array holding DSCoreBase.M (see ds_mem_native.h).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <cstdint>
#include <vector>

namespace godot {

class DSSoundNative : public RefCounted {
	GDCLASS(DSSoundNative, RefCounted)

protected:
	static void _bind_methods();

public:
	DSSoundNative();
	int64_t read(int64_t o, int64_t size) const;
	void write(int64_t o, int64_t size, int64_t v, const Array &mem);
	void advance(int64_t cycles, const Array &mem);
	void flush(const Array &mem);
	PackedVector2Array take_out();
	int64_t active_mask() const;
	void set_mute_mask(int64_t m) { mute_mask = m; }

private:
	struct Channel {
		bool active = false;
		int64_t addr = 0, loop_start = 0, loop_len = 0;
		double pos = 0.0;
		int64_t adpcm_pos = -1, adpcm_val = 0, adpcm_idx = 0, adpcm_loop_val = 0, adpcm_loop_idx = 0;
		int64_t lfsr = 0x7FFF, noise_out = 0, noise_pos = -1;
	};
	uint8_t regs[0x120];
	Channel ch[16];
	std::vector<Vector2> out;
	double cycle_acc = 0.0;
	int64_t mute_mask = 0;   // QoL music / sound effect switches: muted channels are mixed at gain 0
	const uint8_t *mem = nullptr;
	int64_t mem_size = 0;

	void bind_mem(const Array &m);
	uint32_t u32(int o) const { return regs[o] | (regs[o + 1] << 8) | (regs[o + 2] << 16) | ((uint32_t)regs[o + 3] << 24); }
	uint32_t u16(int o) const { return regs[o] | (regs[o + 1] << 8); }
	int64_t r8(int64_t a) const;
	int64_t r16(int64_t a) const;
	int64_t r32(int64_t a) const;
	void start(int n);
	void stop(int n);
	void mix(int64_t n);
	int64_t sample(int i, Channel &c, int64_t fmt, int64_t rep, int64_t cnt);
	int64_t adpcm(Channel &c, int64_t p, int64_t loop_s);
	void adpcm_step(Channel &c);
};

} // namespace godot
