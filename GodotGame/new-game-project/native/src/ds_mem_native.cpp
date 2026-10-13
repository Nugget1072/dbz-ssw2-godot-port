#include "ds_mem_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/variant_internal.hpp>

#include <cstring>

using namespace godot;

namespace {

PackedByteArray *arr(const Array &h, int64_t idx = 0) {
	if (h.size() <= idx) return nullptr;
	Variant &v = const_cast<Array &>(h)[idx];
	if (v.get_type() != Variant::PACKED_BYTE_ARRAY) return nullptr;
	return VariantInternal::get_byte_array(&v);
}

inline bool in(const PackedByteArray *a, int64_t off, int64_t n) { return a && off >= 0 && n >= 0 && off + n <= a->size(); }

// the ARM loops compare signed 32-bit values (blt): a size with bit 31 set does nothing
inline int64_t s32(int64_t v) { return (int64_t)(int32_t)(uint32_t)(v & 0xFFFFFFFF); }

} // namespace

void DSMemNative::_bind_methods() {
	ClassDB::bind_static_method("DSMemNative", D_METHOD("clear16", "h", "data", "off", "size"), &DSMemNative::clear16);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("copy16", "h", "soff", "doff", "size"), &DSMemNative::copy16);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("clear32", "h", "data", "off", "size"), &DSMemNative::clear32);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("copy32", "h", "soff", "doff", "size"), &DSMemNative::copy32);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("fill8", "h", "off", "data", "size"), &DSMemNative::fill8);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("copy8", "h", "soff", "doff", "size"), &DSMemNative::copy8);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("uncompress_lz8", "h", "soff", "doff"), &DSMemNative::uncompress_lz8);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("poke_ref", "h", "idx", "off", "value"), &DSMemNative::poke_ref);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("uncompress_rl8", "h", "soff", "doff"), &DSMemNative::uncompress_rl8);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("uncompress_rl8_buf", "h", "soff"), &DSMemNative::uncompress_rl8_buf);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("blit", "h", "idx", "doff", "src", "soff", "n"), &DSMemNative::blit);
	ClassDB::bind_static_method("DSMemNative", D_METHOD("uncompress_lz8_buf", "h", "soff"), &DSMemNative::uncompress_lz8_buf);
}

// MIi_CpuClear16 (0x020ABB30): for (i = 0; i < size; i += 2) *(u16 *)(dest + i) = data
bool DSMemNative::clear16(const Array &h, int64_t data, int64_t off, int64_t size) {
	PackedByteArray *a = arr(h);
	size = s32(size);
	if (size <= 0) return a != nullptr;
	const int64_t n = (size + 1) / 2 * 2;
	if (!in(a, off, n)) return false;
	uint8_t *p = a->ptrw() + off;
	const uint16_t v = (uint16_t)data;
	for (int64_t i = 0; i < n; i += 2) memcpy(p + i, &v, 2);
	return true;
}

// MIi_CpuCopy16 (0x020ABB48): halfwords, ascending
bool DSMemNative::copy16(const Array &h, int64_t soff, int64_t doff, int64_t size) {
	PackedByteArray *a = arr(h);
	size = s32(size);
	if (size <= 0) return a != nullptr;
	const int64_t n = (size + 1) / 2 * 2;
	if (!in(a, soff, n) || !in(a, doff, n)) return false;
	uint8_t *m = a->ptrw();
	for (int64_t i = 0; i < n; i += 2) {
		uint16_t v;
		memcpy(&v, m + soff + i, 2);
		memcpy(m + doff + i, &v, 2);
	}
	return true;
}

// MIi_CpuClear32 (0x020ABB64) / MIi_CpuClearFast (0x020ABB90): words while dest < dest + size
bool DSMemNative::clear32(const Array &h, int64_t data, int64_t off, int64_t size) {
	PackedByteArray *a = arr(h);
	size = s32(size);
	if (size <= 0) return a != nullptr;
	const int64_t n = (size + 3) / 4 * 4;
	if (!in(a, off, n)) return false;
	uint8_t *p = a->ptrw() + off;
	const uint32_t v = (uint32_t)data;
	for (int64_t i = 0; i < n; i += 4) memcpy(p + i, &v, 4);
	return true;
}

// MIi_CpuCopy32 (0x020ABB78) / MIi_CpuCopyFast (0x020ABBDC): words, ascending
bool DSMemNative::copy32(const Array &h, int64_t soff, int64_t doff, int64_t size) {
	PackedByteArray *a = arr(h);
	size = s32(size);
	if (size <= 0) return a != nullptr;
	const int64_t n = (size + 3) / 4 * 4;
	if (!in(a, soff, n) || !in(a, doff, n)) return false;
	uint8_t *m = a->ptrw();
	if (doff <= soff || doff >= soff + n) {
		memmove(m + doff, m + soff, (size_t)n);   // same result as the ascending word loop
	} else {
		for (int64_t i = 0; i < n; i += 4) {
			uint32_t v;
			memcpy(&v, m + soff + i, 4);
			memcpy(m + doff + i, &v, 4);
		}
	}
	return true;
}

// MI_CpuFill8 (0x020ABC4C): bytes dest[0..size) = data (aligned halfword / word stores, same bytes)
bool DSMemNative::fill8(const Array &h, int64_t off, int64_t data, int64_t size) {
	PackedByteArray *a = arr(h);
	size &= 0xFFFFFFFF;
	if (size == 0) return a != nullptr;
	if (!in(a, off, size)) return false;
	memset(a->ptrw() + off, (int)(data & 0xFF), (size_t)size);
	return true;
}

// MI_CpuCopy8 (0x020ABCE0): bytes, ascending
bool DSMemNative::copy8(const Array &h, int64_t soff, int64_t doff, int64_t size) {
	PackedByteArray *a = arr(h);
	size &= 0xFFFFFFFF;
	if (size == 0) return a != nullptr;
	if (!in(a, soff, size) || !in(a, doff, size)) return false;
	uint8_t *m = a->ptrw();
	if (doff <= soff || doff >= soff + size) {
		memmove(m + doff, m + soff, (size_t)size);
	} else {
		for (int64_t i = 0; i < size; i++) m[doff + i] = m[soff + i];
	}
	return true;
}

// MI_UncompressLZ8 (0x020ABE18): header u32 (size << 8 | type); per flag byte (MSB first) a literal byte or
// a reference (len = hi nibble + 3, disp = 12 bits + 1); a reference is copied whole even past `size`.
// Returns the source offset after the data (the original returns its source pointer), -1 when out of range.
int64_t DSMemNative::uncompress_lz8(const Array &h, int64_t soff, int64_t doff) {
	PackedByteArray *a = arr(h);
	if (!a || soff < 0 || soff + 4 > a->size() || doff < 0) return -1;
	uint8_t *m = a->ptrw();
	const int64_t n = a->size();
	uint32_t hdr;
	memcpy(&hdr, m + soff, 4);
	int64_t remaining = (int64_t)(int32_t)hdr >> 8;   // asr? the original uses lsr: size is 24-bit, positive
	remaining = hdr >> 8;
	// worst case writes: size + 17 bytes (a reference can overshoot by up to 17)
	if (doff + remaining + 18 > n) return -1;
	int64_t s = soff + 4, d = doff;
	while (remaining > 0) {
		if (s >= n) return -1;
		uint8_t flags = m[s++];
		for (int b = 0; b < 8; b++) {
			if (flags & 0x80) {
				if (s + 1 >= n) return -1;
				const int64_t len = (m[s] >> 4) + 3;
				const int64_t disp = (((int64_t)(m[s] & 0xF) << 8) | m[s + 1]) + 1;
				s += 2;
				remaining -= len;
				if (d - disp < 0) return -1;
				for (int64_t k = 0; k < len; k++, d++) m[d] = m[d - disp];
			} else {
				if (s >= n) return -1;
				m[d++] = m[s++];
				remaining -= 1;
			}
			if (remaining <= 0) break;
			flags <<= 1;
		}
	}
	return s;   // source end (the original returns its source pointer)
}

int64_t DSMemNative::poke_ref(const Array &h, int64_t idx, int64_t off, int64_t value) {
	PackedByteArray *a = arr(h, idx);
	if (!a || off < 0 || off >= a->size()) return 0;
	a->ptrw()[off] = (uint8_t)value;
	return 1;
}

bool DSMemNative::blit(const Array &h, int64_t idx, int64_t doff, const PackedByteArray &src, int64_t soff, int64_t n) {
	PackedByteArray *a = arr(h, idx);
	if (n <= 0) return a != nullptr;
	if (!in(a, doff, n) || soff < 0 || soff + n > src.size()) return false;
	memmove(a->ptrw() + doff, src.ptr() + soff, (size_t)n);
	return true;
}

Array DSMemNative::uncompress_lz8_buf(const Array &h, int64_t soff) {
	Array res;
	PackedByteArray out;
	PackedByteArray *a = arr(h);
	if (!a || soff < 0 || soff + 4 > a->size()) return res;
	const uint8_t *m = a->ptr();
	const int64_t n = a->size();
	uint32_t hdr;
	memcpy(&hdr, m + soff, 4);
	int64_t remaining = hdr >> 8;
	out.resize(remaining + 18);
	uint8_t *o = out.ptrw();
	int64_t s = soff + 4, d = 0;
	while (remaining > 0) {
		if (s >= n) return Array();
		uint8_t flags = m[s++];
		for (int b = 0; b < 8; b++) {
			if (flags & 0x80) {
				if (s + 1 >= n) return Array();
				const int64_t len = (m[s] >> 4) + 3;
				const int64_t disp = (((int64_t)(m[s] & 0xF) << 8) | m[s + 1]) + 1;
				s += 2;
				remaining -= len;
				if (d - disp < 0) return Array();
				for (int64_t k = 0; k < len; k++, d++) o[d] = o[d - disp];
			} else {
				if (s >= n) return Array();
				o[d++] = m[s++];
				remaining -= 1;
			}
			if (remaining <= 0) break;
			flags <<= 1;
		}
	}
	out.resize(d);
	res.append(out);
	res.append(s);
	return res;
}

// MI_UncompressRL8: header u32 (size << 8 | type); flag byte: bit 7 clear = (n & 0x7F) + 1 literal bytes,
// set = the next byte repeated (n & 0x7F) + 3 times; a run is written whole even past `size`.
static int64_t rl8(const uint8_t *m, int64_t n, int64_t soff, uint8_t *out, int64_t out_size, int64_t *src_end) {
	uint32_t hdr;
	memcpy(&hdr, m + soff, 4);
	int64_t remaining = (int64_t)(hdr >> 8);
	int64_t s = soff + 4, d = 0;
	while (remaining > 0) {
		if (s >= n) return -1;
		const uint8_t f = m[s++];
		if (f & 0x80) {
			const int64_t len = (f & 0x7F) + 3;
			remaining -= len;
			if (s >= n || d + len > out_size) return -1;
			const uint8_t b = m[s++];
			for (int64_t k = 0; k < len; k++) out[d + k] = b;
			d += len;
		} else {
			const int64_t len = (f & 0x7F) + 1;
			remaining -= len;
			if (s + len > n || d + len > out_size) return -1;
			for (int64_t k = 0; k < len; k++) out[d + k] = m[s + k];
			s += len;
			d += len;
		}
	}
	*src_end = s;
	return d;
}

int64_t DSMemNative::uncompress_rl8(const Array &h, int64_t soff, int64_t doff) {
	PackedByteArray *a = arr(h);
	if (!a || soff < 0 || soff + 4 > a->size() || doff < 0) return -1;
	uint32_t hdr;
	memcpy(&hdr, a->ptr() + soff, 4);
	const int64_t size = hdr >> 8;
	if (doff + size + 130 > a->size()) return -1;
	// in place, byte by byte in the original order (source and destination may overlap)
	int64_t src_end = 0;
	if (rl8(a->ptr(), a->size(), soff, a->ptrw() + doff, a->size() - doff, &src_end) < 0) return -1;
	return src_end;
}

Array DSMemNative::uncompress_rl8_buf(const Array &h, int64_t soff) {
	Array res;
	PackedByteArray out;
	PackedByteArray *a = arr(h);
	if (!a || soff < 0 || soff + 4 > a->size()) return res;
	uint32_t hdr;
	memcpy(&hdr, a->ptr() + soff, 4);
	const int64_t size = hdr >> 8;
	out.resize(size + 130);
	int64_t src_end = 0;
	const int64_t d = rl8(a->ptr(), a->size(), soff, out.ptrw(), out.size(), &src_end);
	if (d < 0) return res;
	out.resize(d);
	res.append(out);
	res.append(src_end);
	return res;
}
