#include "ds_fs_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/variant_internal.hpp>

#include <cstdint>
#include <unordered_map>

using namespace godot;

namespace {

constexpr uint32_t BASE = 0x02000000;
constexpr uint32_t READ_MEM_CB = 0x020AEE38;   // archive read callback: MI_CpuCopy8 from the table in memory
constexpr uint32_t CMD_TABLE = 0x020D53A0;     // default command handlers (DAT_020ada34)
constexpr uint32_t SEEKDIR = 0x020AE234, READDIR = 0x020AE124;

// memory view with a write overlay: nothing reaches RAM unless the whole lookup stayed in range
struct Mem {
	uint8_t *p = nullptr;
	int64_t size = 0;
	bool bad = false;
	std::unordered_map<uint32_t, uint8_t> w;

	uint8_t r8(uint32_t a) {
		auto it = w.find(a);
		if (it != w.end()) return it->second;
		const int64_t o = (int64_t)a - BASE;
		if (o < 0 || o >= size) { bad = true; return 0; }
		return p[o];
	}
	uint32_t r16(uint32_t a) { return r8(a) | (uint32_t)r8(a + 1) << 8; }
	uint32_t r32(uint32_t a) { return r16(a) | r16(a + 2) << 16; }
	void w8(uint32_t a, uint32_t v) {
		const int64_t o = (int64_t)a - BASE;
		if (o < 0 || o >= size) { bad = true; return; }
		w[a] = (uint8_t)v;
	}
	void w16(uint32_t a, uint32_t v) { w8(a, v); w8(a + 1, v >> 8); }
	void w32(uint32_t a, uint32_t v) { w16(a, v); w16(a + 2, v >> 16); }
	void commit() {
		for (auto &e : w) p[(int64_t)e.first - BASE] = e.second;
	}
};

struct FindPath {
	Mem &m;
	uint32_t F, arc;
	int steps = 0;

	// 0x020AE370: read through the archive's read callback (memory copy), returns the new position
	uint32_t read(uint32_t pos, uint32_t dst, uint32_t len) {
		m.w32(arc + 0x10, m.r32(arc + 0x10) | 0x200);
		for (uint32_t i = 0; i < len && !m.bad; i++) m.w8(dst + i, m.r8(pos + i));
		m.w32(arc + 0x10, m.r32(arc + 0x10) & ~0x200u);
		return pos + len;
	}
	// 0x020AE234 (FS_COMMAND_SEEKDIR); the 8-byte table entry goes to the handler's stack (scratch) in the
	// original, here to a local
	uint32_t seekdir() {
		const uint32_t fnt = m.r32(arc + 0x28);
		const uint32_t pos = fnt + m.r16(F + 0x30) * 8;
		const uint32_t off = m.r32(pos), first = m.r16(pos + 4), parent = m.r16(pos + 6);
		read(pos, 0, 0);
		m.w32(F + 0x1C, m.r32(F + 0x2C));
		m.w32(F + 0x20, m.r32(F + 0x30));
		m.w32(F + 0x24, m.r32(F + 0x34));
		if (m.r16(F + 0x32) == 0 && m.r32(F + 0x34) == 0) {
			m.w16(F + 0x22, first);
			m.w32(F + 0x24, fnt + off);
		}
		m.w32(F + 0x28, parent & 0xFFF);
		return 0;
	}
	// 0x020AE124 (FS_COMMAND_READDIR) into the FSDirEntry at F+0x2C; the first byte (length | dir flag) and the
	// directory id go through the handler's stack in the original
	uint32_t readdir() {
		const uint32_t ent = m.r32(F + 0x2C);
		uint32_t pos = m.r32(F + 0x24);
		const uint32_t b = m.r8(pos);
		read(pos, 0, 0);   // the 1-byte read: same flag traffic (the byte itself lands on the stack)
		pos += 1;
		const uint32_t len = b & 0x7F, isdir = b >> 7;
		m.w32(ent + 0x10, len);
		m.w32(ent + 0x0C, isdir);
		if (len == 0) return 1;
		if (m.r32(F + 0x30) == 0) {
			pos = read(pos, ent + 0x14, len);
			m.w8(ent + 0x14 + len, 0);
		} else {
			pos += len;
		}
		if (isdir == 0) {
			m.w32(ent, m.r32(F + 8));
			const uint32_t idx = m.r16(F + 0x22);
			m.w32(ent + 4, idx);
			m.w16(F + 0x22, idx + 1);
		} else {
			const uint32_t id = m.r16(pos);
			read(pos, 0, 0);
			pos += 2;
			m.w32(ent, m.r32(F + 8));
			m.w16(ent + 4, id & 0xFFF);
			m.w16(ent + 6, 0);
			m.w32(ent + 8, 0);
		}
		m.w32(F + 0x24, pos);
		return 0;
	}
	// 0x020AD8BC for a synchronous command (FSFile stat bit 2 set) whose archive has no own handler for it
	uint32_t command(int cmd) {
		m.w32(arc + 0x10, m.r32(arc + 0x10) | 0x200);
		const uint32_t r = cmd == 2 ? seekdir() : readdir();
		m.w32(arc + 0x10, m.r32(arc + 0x10) & ~0x200u);
		m.w32(F + 0x14, r);
		return r;
	}
	// 0x020AE414: case-insensitive compare of n bytes
	bool same(uint32_t a, uint32_t b, uint32_t n) {
		for (uint32_t i = 0; i < n; i++) {
			uint32_t x = m.r8(a + i), y = m.r8(b + i);
			if (x - 0x41 < 0x1A) x += 0x20;
			if (y - 0x41 < 0x1A) y += 0x20;
			if (x != y) return false;
		}
		return true;
	}

	int64_t run(uint32_t fp) {
		const uint32_t find_dir = m.r32(F + 0x3C);
		uint32_t p = m.r32(F + 0x38);
		command(2);
		uint8_t c = m.r8(p);
		while (c != 0) {
			if (m.bad || ++steps > 4096) return -1;
			uint32_t n = 0;
			uint8_t ch;
			while ((ch = m.r8(p + n)) != 0 && ch != '/' && ch != '\\' && !m.bad) n++;
			const uint32_t isdir = (ch != 0 || find_dir != 0) ? 1 : 0;
			if (n == 0) return 1;
			if (c == '.' && n == 1) {
				p += 1;
			} else if (c == '.' && n == 2 && m.r8(p + 1) == '.') {
				if ((m.r32(F + 0x20) & 0xFFFF) != 0) {   // 0x020AE33C: seek to the parent directory
					const uint32_t parent = m.r32(F + 0x28) & 0xFFFF;
					m.w32(F + 0x0C, m.r32(F + 0x0C) | 4);
					m.w32(F + 0x2C, m.r32(F + 8));
					m.w32(F + 0x34, 0);
					m.w16(F + 0x32, 0);
					m.w16(F + 0x30, parent);
					command(2);
				}
				p += 2;
			} else {
				if (n > 0x7F) return 1;
				m.w32(F + 0x2C, fp);
				m.w32(F + 0x30, 0);
				for (;;) {
					if (m.bad || ++steps > 65536) return -1;
					if (command(3) != 0) return 1;
					if (isdir == m.r32(fp + 12) && n == m.r32(fp + 16) && same(p, fp + 20, n)) break;
				}
				if (isdir == 0) {
					if (find_dir != 0) return 1;
					const uint32_t out = m.r32(F + 0x40);
					m.w32(out, m.r32(fp));
					m.w32(out + 4, m.r32(fp + 4));
					return 0;
				}
				m.w32(F + 0x2C, m.r32(fp));
				m.w32(F + 0x30, m.r32(fp + 4));
				m.w32(F + 0x34, m.r32(fp + 8));
				p += n;
				command(2);
			}
			p += m.r8(p) != 0 ? 1 : 0;
			c = m.r8(p);
		}
		if (find_dir != 0) {
			const uint32_t out = m.r32(F + 0x40);
			m.w32(out, m.r32(F + 0x1C));
			m.w32(out + 4, m.r32(F + 0x20));
			m.w32(out + 8, m.r32(F + 0x24));
		}
		return find_dir == 0 ? 1 : 0;
	}
};

} // namespace

void DSFSNative::_bind_methods() {
	ClassDB::bind_static_method("DSFSNative", D_METHOD("find_path", "h", "file", "fp"), &DSFSNative::find_path);
}

int64_t DSFSNative::find_path(const Array &h, int64_t file, int64_t fp) {
	if (h.size() < 1) return -1;
	Variant &v = const_cast<Array &>(h)[0];
	if (v.get_type() != Variant::PACKED_BYTE_ARRAY) return -1;
	PackedByteArray *a = VariantInternal::get_byte_array(&v);
	Mem m;
	m.p = a->ptrw();
	m.size = a->size();
	const uint32_t F = (uint32_t)file;
	const uint32_t arc = m.r32(F + 8);
	// preconditions: synchronous command, the archive has no own seek/read-dir handler (mask bits 2, 3), reads
	// come from the table in memory, the default handler table is the original
	if ((m.r32(F + 0x0C) & 4) == 0 || (m.r32(arc + 0x4C) & 0xC) != 0 || m.r32(arc + 0x44) != READ_MEM_CB ||
			m.r32(CMD_TABLE + 8) != SEEKDIR || m.r32(CMD_TABLE + 12) != READDIR || m.bad)
		return -1;
	FindPath f{ m, F, arc };
	const int64_t r = f.run((uint32_t)fp);
	if (r < 0 || m.bad) return -1;
	m.commit();
	return r;
}
