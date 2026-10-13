// Native fast paths for memory utility functions of the game (NitroSDK MI_Cpu*, MI_UncompressLZ8) and other
// bulk work on the emulated memory. The memory is a PackedByteArray owned by GDScript (DSCoreBase.M) and is
// passed inside an Array (`[M]`): the element shares the script variable's storage, so the native code writes
// to it in place (a PackedByteArray passed directly would be copied on write).
// All functions mirror the original ARM code byte for byte (see decomp/DATA_NOTES.md "MI functions").
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {

class DSMemNative : public RefCounted {
	GDCLASS(DSMemNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// every function returns false when an offset range is outside the array (the caller then uses the
	// translated original); offsets are into holder[0]
	static bool clear16(const Array &h, int64_t data, int64_t off, int64_t size);
	static bool copy16(const Array &h, int64_t soff, int64_t doff, int64_t size);
	static bool clear32(const Array &h, int64_t data, int64_t off, int64_t size);
	static bool copy32(const Array &h, int64_t soff, int64_t doff, int64_t size);
	static bool fill8(const Array &h, int64_t off, int64_t data, int64_t size);
	static bool copy8(const Array &h, int64_t soff, int64_t doff, int64_t size);
	// MI_UncompressLZ8: returns the source offset after the data (-1 when out of range)
	static int64_t uncompress_lz8(const Array &h, int64_t soff, int64_t doff);
	// MI_UncompressRL8 (0x020ABF84): returns the source offset after the data (-1 when out of range); _buf
	// variant for VRAM destinations
	static int64_t uncompress_rl8(const Array &h, int64_t soff, int64_t doff);
	static Array uncompress_rl8_buf(const Array &h, int64_t soff);   // [bytes, source end] or []
	static int64_t poke_ref(const Array &h, int64_t idx, int64_t off, int64_t value);
	// copy n bytes src[soff..] into h[idx][doff..] (VRAM bank writes); false when out of range
	static bool blit(const Array &h, int64_t idx, int64_t doff, const PackedByteArray &src, int64_t soff, int64_t n);
	// MI_UncompressLZ8 into a new buffer (destinations outside main RAM); empty when the source is out of range
	static Array uncompress_lz8_buf(const Array &h, int64_t soff);   // [bytes, source end] or []
};

} // namespace godot
