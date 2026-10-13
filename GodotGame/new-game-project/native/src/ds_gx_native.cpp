// See ds_gx_native.h. Every function corresponds to the GDScript function of the same name in
// scripts/render/ds_gx.gd; keep the two in step (tools/bench_gx.gd checks they agree bit for bit).
#include "ds_gx_native.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

// Mesh::ArrayType (the Mesh class is left out of the godot-cpp build profile)
enum { ARRAY_VERTEX = 0, ARRAY_COLOR = 3, ARRAY_TEX_UV = 4, ARRAY_TEX_UV2 = 5, ARRAY_CUSTOM0 = 6, ARRAY_CUSTOM1 = 7,
	ARRAY_CUSTOM2 = 8, ARRAY_MAX = 13 };

const int NPARAMS[][2] = {
	{ 0x00, 0 }, { 0x10, 1 }, { 0x11, 0 }, { 0x12, 1 }, { 0x13, 1 }, { 0x14, 1 }, { 0x15, 0 }, { 0x16, 16 }, { 0x17, 12 },
	{ 0x18, 16 }, { 0x19, 12 }, { 0x1A, 9 }, { 0x1B, 3 }, { 0x1C, 3 }, { 0x20, 1 }, { 0x21, 1 }, { 0x22, 1 }, { 0x23, 2 },
	{ 0x24, 1 }, { 0x25, 1 }, { 0x26, 1 }, { 0x27, 1 }, { 0x28, 1 }, { 0x29, 1 }, { 0x2A, 1 }, { 0x2B, 1 }, { 0x30, 1 },
	{ 0x31, 1 }, { 0x32, 1 }, { 0x33, 1 }, { 0x34, 32 }, { 0x40, 1 }, { 0x41, 0 }, { 0x50, 1 }, { 0x60, 1 }, { 0x70, 3 },
	{ 0x71, 2 }, { 0x72, 1 },
};

inline int64_t s_ext(int64_t v, int bits) {
	v &= (int64_t(1) << bits) - 1;
	return (v & (int64_t(1) << (bits - 1))) ? v - (int64_t(1) << bits) : v;
}

inline double fx(int64_t v) { return (double)s_ext(v, 32) / 4096.0; }

inline Color c5(int64_t v) {
	return Color((double)(v & 31) / 31.0, (double)((v >> 5) & 31) / 31.0, (double)((v >> 10) & 31) / 31.0);
}

inline double minf(double a, double b) { return a < b ? a : b; }
inline double maxf(double a, double b) { return a > b ? a : b; }
inline double clampf(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline int64_t clampi(int64_t v, int64_t lo, int64_t hi) { return v < lo ? lo : (v > hi ? hi : v); }

inline int quad(double nx, double ny) {
	if (nx > 0.0 && ny >= 0.0) return 0;
	if (nx <= 0.0 && ny > 0.0) return 1;
	if (nx < 0.0 && ny <= 0.0) return 2;
	return 3;
}

const double DILATE = 118.0 / 256.0;   // multiple of 1/256 px: ring corners on the GPU's sub-pixel grid

} // namespace

DSGXNative::DSGXNative() {
	for (int i = 0; i < 256; i++) NP[i] = 0;
	for (const auto &e : NPARAMS) NP[e[0]] = e[1];
	for (int i = 0; i < 128; i++) shininess[i] = 0.0f;
	for (int i = 0; i < 36; i++) light_k[i] = 0.0;
	for (int i = 0; i < 4; i++) {
		light_vec[i] = Vector3();
		light_col[i] = Color(0, 0, 0, 1);
		light_half[i] = Vector3();
		prim_o[i] = 0;
	}
}

void DSGXNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("run", "cmds"), &DSGXNative::run);
	ClassDB::bind_method(D_METHOD("get_swaps"), &DSGXNative::get_swaps);
	ClassDB::bind_method(D_METHOD("get_tri_count"), &DSGXNative::get_tri_count);
	ClassDB::bind_method(D_METHOD("set_dilate", "dilate"), &DSGXNative::set_dilate);
	ClassDB::bind_method(D_METHOD("get_dilate"), &DSGXNative::get_dilate);
	ClassDB::bind_method(D_METHOD("prepare"), &DSGXNative::prepare);
	ClassDB::bind_method(D_METHOD("get_out_pos"), &DSGXNative::get_out_pos);
	ClassDB::bind_method(D_METHOD("get_out_col"), &DSGXNative::get_out_col);
	ClassDB::bind_method(D_METHOD("get_out_uv"), &DSGXNative::get_out_uv);
	ClassDB::bind_method(D_METHOD("get_out_attr"), &DSGXNative::get_out_attr);
	ClassDB::bind_method(D_METHOD("get_out_tex"), &DSGXNative::get_out_tex);
	ClassDB::bind_method(D_METHOD("get_out_pal"), &DSGXNative::get_out_pal);
	ClassDB::bind_method(D_METHOD("get_out_uvbox"), &DSGXNative::get_out_uvbox);
	ClassDB::bind_method(D_METHOD("get_out_prev"), &DSGXNative::get_out_prev);
}

// ------------------------------------------------------------------------------------------------ frames

void DSGXNative::swap_buffers() {
	out_pos.swap(acc.pos);
	out_col.swap(acc.col);
	out_uv.swap(acc.uv);
	out_attr.swap(acc.attr);
	out_tex.swap(acc.tex);
	out_pal.swap(acc.pal);
	out_uvbox.swap(acc.uvbox);
	out_prev.swap(acc.prev);
	acc.clear();
	prev_key.swap(poly_key);
	prev_uv.swap(poly_uv);
	prev_v.swap(poly_v);
	poly_key.clear();
	poly_uv.clear();
	poly_v.clear();
	swaps += 1;
}

void DSGXNative::run(const Array &cmds) {
	const int64_t n = cmds.size();
	for (int64_t i = 0; i < n; i++) {
		const Array c = cmds[i];
		const int64_t a = c[0];
		if (a == -1) {
			if (c.size() > 3) {
				const PackedInt32Array words = c[3];
				run_words(words.ptr(), words.size());
			}
		} else if (a < 0x4000440) {
			fifo_word((int64_t)c[1]);
		} else {
			port_write(a, (int64_t)c[1]);
		}
	}
}

void DSGXNative::run_words(const int32_t *words, int64_t n) {
	int64_t i = 0;
	while (i < n) {
		const int64_t w = words[i];
		if (fifo_need > 0) {
			fifo_word(w);
			i += 1;
			continue;
		}
		if ((w & -256) == 0) {
			const int64_t n1 = NP[w];
			if (i + 1 + n1 > n) {
				fifo_word(w);
				i += 1;
				continue;
			}
			if (w != 0) exec(w, words, n, i + 1);
			i += 1 + n1;
			continue;
		}
		const int64_t id0 = w & 0xFF, id1 = (w >> 8) & 0xFF, id2 = (w >> 16) & 0xFF, id3 = (w >> 24) & 0xFF;
		const int64_t n0 = NP[id0], n1 = NP[id1], n2 = NP[id2], n3 = NP[id3];
		if (i + 1 + n0 + n1 + n2 + n3 > n) {
			fifo_word(w);
			i += 1;
			continue;
		}
		int64_t o = i + 1;
		if (id0 != 0) exec(id0, words, n, o);
		o += n0;
		if (id1 != 0) exec(id1, words, n, o);
		o += n1;
		if (id2 != 0) exec(id2, words, n, o);
		o += n2;
		if (id3 != 0) exec(id3, words, n, o);
		i = o + n3;
	}
}

void DSGXNative::port_write(int64_t addr, int64_t v) {
	const int64_t cmd = 0x10 + ((addr - 0x4000440) >> 2);
	const int64_t n = NP[cmd & 0xFF];
	if (cmd != port_cmd) {
		port_cmd = cmd;
		port_params.clear();
	}
	if (n == 0) {
		exec(cmd, port_params.data(), (int64_t)port_params.size(), 0);
		port_cmd = -1;
		return;
	}
	port_params.push_back((int32_t)(uint32_t)(v & 0xFFFFFFFF));
	if ((int64_t)port_params.size() >= n) {
		std::vector<int32_t> p = port_params;
		exec(cmd, p.data(), (int64_t)p.size(), 0);
		port_params.clear();
		port_cmd = -1;
	}
}

void DSGXNative::fifo_word(int64_t w) {
	if (fifo_need > 0) {
		fifo_params.push_back((int32_t)(uint32_t)(w & 0xFFFFFFFF));
		fifo_need -= 1;
		if (fifo_need == 0) flush_fifo();
		return;
	}
	fifo_cmds.clear();
	fifo_params.clear();
	int64_t total = 0;
	for (int k = 0; k < 4; k++) {
		const int64_t id = (w >> (8 * k)) & 0xFF;
		fifo_cmds.push_back((int32_t)id);
		total += NP[id];
	}
	fifo_need = total;
	if (total == 0) flush_fifo();
}

void DSGXNative::flush_fifo() {
	std::vector<int32_t> cmds = fifo_cmds;
	std::vector<int32_t> params = fifo_params;
	int64_t i = 0;
	for (int32_t id : cmds) {
		if (id == 0) continue;
		exec(id, params.data(), (int64_t)params.size(), i);
		i += NP[id];
	}
	fifo_cmds.clear();
	fifo_params.clear();
}

// ------------------------------------------------------------------------------------------------ matrices

void DSGXNative::cur_set(const Projection &m) {
	switch (mtx_mode) {
		case 0: proj = m; break;
		case 1: pos = m; break;
		case 2: pos = m; vec = m; break;
		case 3: tex = m; break;
	}
	clip_dirty = true;
}

void DSGXNative::mul(const Projection &n) {
	switch (mtx_mode) {
		case 0: proj = proj * n; break;
		case 1: pos = pos * n; break;
		case 2: pos = pos * n; vec = vec * n; break;
		case 3: tex = tex * n; break;
	}
	clip_dirty = true;
}

static Projection m44(const int32_t *p, int64_t o) {
	return Projection(Vector4(fx(p[o]), fx(p[o + 1]), fx(p[o + 2]), fx(p[o + 3])),
			Vector4(fx(p[o + 4]), fx(p[o + 5]), fx(p[o + 6]), fx(p[o + 7])),
			Vector4(fx(p[o + 8]), fx(p[o + 9]), fx(p[o + 10]), fx(p[o + 11])),
			Vector4(fx(p[o + 12]), fx(p[o + 13]), fx(p[o + 14]), fx(p[o + 15])));
}

static Projection m43(const int32_t *p, int64_t o) {
	return Projection(Vector4(fx(p[o]), fx(p[o + 1]), fx(p[o + 2]), 0.0),
			Vector4(fx(p[o + 3]), fx(p[o + 4]), fx(p[o + 5]), 0.0),
			Vector4(fx(p[o + 6]), fx(p[o + 7]), fx(p[o + 8]), 0.0),
			Vector4(fx(p[o + 9]), fx(p[o + 10]), fx(p[o + 11]), 1.0));
}

// ------------------------------------------------------------------------------------------------ commands

void DSGXNative::exec(int64_t cmd, const int32_t *p, int64_t np, int64_t o) {
	const int64_t v = o < np ? (int64_t)p[o] : 0;
	if (cmd >= 0x20 && cmd <= 0x28) {
		switch (cmd) {
			case 0x22:
				texcoord0 = Vector2((double)(((v & 0xFFFF) ^ 0x8000) - 0x8000) / 16.0,
						(double)((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 16.0);
				texcoord = texcoord0;
				if (((teximage >> 30) & 3) == 1) {
					const Vector4 tv = tex.xform(Vector4(texcoord0.x, texcoord0.y, 1.0 / 16.0, 1.0 / 16.0));
					texcoord = Vector2(tv.x, tv.y);
				}
				break;
			case 0x21:
				normal(v);
				break;
			case 0x23:
				vtx = Vector3((double)(((v & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0,
						(double)((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0,
						(double)((((int64_t)p[o + 1] & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0);
				vertex();
				break;
			case 0x26:
				vtx = Vector3((double)(((v & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0, vtx.y,
						(double)((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0);
				vertex();
				break;
			case 0x27:
				vtx = Vector3(vtx.x, (double)(((v & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0,
						(double)((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0);
				vertex();
				break;
			case 0x25:
				vtx = Vector3((double)(((v & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0,
						(double)((((v >> 16) & 0xFFFF) ^ 0x8000) - 0x8000) / 4096.0, vtx.z);
				vertex();
				break;
			case 0x28:
				vtx += Vector3((double)(((v & 0x3FF) ^ 0x200) - 0x200) / 4096.0,
						(double)((((v >> 10) & 0x3FF) ^ 0x200) - 0x200) / 4096.0,
						(double)((((v >> 20) & 0x3FF) ^ 0x200) - 0x200) / 4096.0);
				vertex();
				break;
			case 0x24:
				vtx = Vector3((double)s_ext(v, 10) / 64.0, (double)s_ext(v >> 10, 10) / 64.0, (double)s_ext(v >> 20, 10) / 64.0);
				vertex();
				break;
			case 0x20:
				color = c5(v);
				break;
		}
		return;
	}
	switch (cmd) {
		case 0x40:
			prim_type = v & 3;
			polyattr = polyattr_next;
			prim_n = 0;
			strip_n = 0;
			break;
		case 0x41:
			prim_type = -1;
			prim_n = 0;
			break;
		case 0x10:
			mtx_mode = v & 3;
			break;
		case 0x11:
			if (mtx_mode == 0) {
				proj_stack[0] = proj;
			} else if (mtx_mode != 3) {
				if (stack_ptr < 31) {
					pos_stack[stack_ptr] = pos;
					vec_stack[stack_ptr] = vec;
				}
				stack_ptr = std::min<int64_t>(stack_ptr + 1, 31);
			}
			break;
		case 0x12:
			if (mtx_mode == 0) {
				proj = proj_stack[0];
			} else if (mtx_mode != 3) {
				stack_ptr = clampi(stack_ptr - s_ext(v, 6), 0, 31);
				pos = pos_stack[stack_ptr];
				vec = vec_stack[stack_ptr];
			}
			clip_dirty = true;
			break;
		case 0x13:
			if (mtx_mode == 0) {
				proj_stack[0] = proj;
			} else if (mtx_mode != 3) {
				const int64_t i = v & 31;
				if (i < 31) {
					pos_stack[i] = pos;
					vec_stack[i] = vec;
				}
			}
			break;
		case 0x14:
			if (mtx_mode == 0) {
				proj = proj_stack[0];
			} else if (mtx_mode != 3) {
				const int64_t i = v & 31;
				if (i < 31) {
					pos = pos_stack[i];
					vec = vec_stack[i];
				}
			}
			clip_dirty = true;
			break;
		case 0x15:
			cur_set(Projection());
			break;
		case 0x16:
			cur_set(m44(p, o));
			break;
		case 0x17:
			cur_set(m43(p, o));
			break;
		case 0x18:
			mul(m44(p, o));
			break;
		case 0x19:
			mul(m43(p, o));
			break;
		case 0x1A:
			mul(Projection(Vector4(fx(p[o]), fx(p[o + 1]), fx(p[o + 2]), 0.0),
					Vector4(fx(p[o + 3]), fx(p[o + 4]), fx(p[o + 5]), 0.0),
					Vector4(fx(p[o + 6]), fx(p[o + 7]), fx(p[o + 8]), 0.0), Vector4(0.0, 0.0, 0.0, 1.0)));
			break;
		case 0x1B: {
			const Projection m(Vector4(fx(v), 0, 0, 0), Vector4(0, fx(p[o + 1]), 0, 0), Vector4(0, 0, fx(p[o + 2]), 0),
					Vector4(0, 0, 0, 1));
			if (mtx_mode == 2) {
				pos = pos * m;
				clip_dirty = true;
			} else {
				mul(m);
			}
		} break;
		case 0x1C:
			mul(Projection(Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0),
					Vector4(fx(v), fx(p[o + 1]), fx(p[o + 2]), 1)));
			break;
		case 0x29:
			polyattr_next = v;
			break;
		case 0x2A:
			teximage = v;
			break;
		case 0x2B:
			pltt = v & 0x1FFF;
			break;
		case 0x30:
			dif = c5(v);
			amb = c5(v >> 16);
			light_dirty = true;
			if (v & 0x8000) color = dif;
			break;
		case 0x31:
			spe = c5(v);
			emi = c5(v >> 16);
			light_dirty = true;
			use_shine = (v & 0x8000) != 0;
			break;
		case 0x32: {
			const int64_t i = (v >> 30) & 3;
			const Vector4 d((double)s_ext(v, 10) / 512.0, (double)s_ext(v >> 10, 10) / 512.0, (double)s_ext(v >> 20, 10) / 512.0, 0.0);
			const Vector4 t = vec.xform(d);
			light_vec[i] = Vector3(t.x, t.y, t.z);
			light_dirty = true;
		} break;
		case 0x33:
			light_col[(v >> 30) & 3] = c5(v);
			light_dirty = true;
			break;
		case 0x34:
			for (int i = 0; i < 32; i++)
				for (int k = 0; k < 4; k++)
					shininess[i * 4 + k] = (float)((double)(((int64_t)p[o + i] >> (8 * k)) & 0xFF) / 256.0);
			break;
		case 0x50:
			swap_params = v;
			swap_buffers();
			break;
		case 0x60:
			vp_x1 = v & 255;
			vp_y1 = (v >> 8) & 255;
			vp_x2 = (v >> 16) & 255;
			vp_y2 = (v >> 24) & 255;
			break;
		default:
			break;
	}
}

// ------------------------------------------------------------------------------------------------ lighting

void DSGXNative::light_prep() {
	light_dirty = false;
	for (int i = 0; i < 4; i++) {
		const Color lc = light_col[i];
		light_half[i] = (light_vec[i] + Vector3(0, 0, -1)) * 0.5;
		const int k = i * 9;
		light_k[k] = (double)spe.r * (double)lc.r;
		light_k[k + 1] = (double)dif.r * (double)lc.r;
		light_k[k + 2] = (double)amb.r * (double)lc.r;
		light_k[k + 3] = (double)spe.g * (double)lc.g;
		light_k[k + 4] = (double)dif.g * (double)lc.g;
		light_k[k + 5] = (double)amb.g * (double)lc.g;
		light_k[k + 6] = (double)spe.b * (double)lc.b;
		light_k[k + 7] = (double)dif.b * (double)lc.b;
		light_k[k + 8] = (double)amb.b * (double)lc.b;
	}
}

void DSGXNative::normal(int64_t v) {
	const Vector4 n4((double)(((v & 0x3FF) ^ 0x200) - 0x200) / 512.0, (double)((((v >> 10) & 0x3FF) ^ 0x200) - 0x200) / 512.0,
			(double)((((v >> 20) & 0x3FF) ^ 0x200) - 0x200) / 512.0, 0.0);
	if (((teximage >> 30) & 3) == 2) {
		const Vector4 t = tex.xform(n4);
		texcoord = texcoord0 + Vector2(t.x, t.y);
	}
	const Vector4 t2 = vec.xform(n4);
	const Vector3 n(t2.x, t2.y, t2.z);
	Color c = emi;
	const int64_t en = polyattr_next & 15;
	if (en == 0) {
		color = Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0));
		return;
	}
	if (light_dirty) light_prep();
	for (int i = 0; i < 4; i++) {
		if ((en & (1 << i)) == 0) continue;
		const Vector3 lv = light_vec[i];
		const double diffuse = maxf(0.0, -(double)lv.dot(n));
		const Vector3 half = light_half[i];
		double shine = maxf(0.0, -(double)half.dot(n));
		shine = minf(shine * shine, 1.0);
		if (use_shine) shine = shininess[clampi((int64_t)(shine * 127.0), 0, 127)];
		const int k = i * 9;
		c += Color(light_k[k] * shine + light_k[k + 1] * diffuse + light_k[k + 2],
				light_k[k + 3] * shine + light_k[k + 4] * diffuse + light_k[k + 5],
				light_k[k + 6] * shine + light_k[k + 7] * diffuse + light_k[k + 8], 0.0);
	}
	color = Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0));
}

// ------------------------------------------------------------------------------------------------ vertices

void DSGXNative::vertex() {
	if (prim_type < 0) return;
	if (clip_dirty) {
		clip = proj * pos;
		clip_dirty = false;
	}
	const Vector4 v4(vtx.x, vtx.y, vtx.z, 1.0);
	Vector2 uv = texcoord;
	if (((teximage >> 30) & 3) == 3) {
		const Vector4 t = tex.xform(v4);
		uv = texcoord0 + Vector2(t.x, t.y);
	}
	const int64_t k = prim_n;
	const Vector4 cv = clip.xform(v4);
	prim_p[k] = cv;
	const double w = cv.w;
	int64_t oc = 0;
	if (w + (double)cv.x < 0.0) oc = 1;
	if (w - (double)cv.x < 0.0) oc |= 2;
	if (w + (double)cv.y < 0.0) oc |= 4;
	if (w - (double)cv.y < 0.0) oc |= 8;
	if (w + (double)cv.z < 0.0) oc |= 16;
	if (w - (double)cv.z < 0.0) oc |= 32;
	prim_o[k] = oc;
	prim_c[k] = color;
	prim_u[k] = uv;
	prim_n = k + 1;
	switch (prim_type) {
		case 0:
			if (prim_n == 3) {
				tri(0, 1, 2);
				prim_n = 0;
			}
			break;
		case 1:
			if (prim_n == 4) {
				quad4(0, 1, 2, 3);
				prim_n = 0;
			}
			break;
		case 2:
			if (prim_n == 3) {
				if (strip_n & 1)
					tri(1, 0, 2);
				else
					tri(0, 1, 2);
				strip_n += 1;
				shift(1, 0);
				shift(2, 1);
				prim_n = 2;
			}
			break;
		case 3:
			if (prim_n == 4) {
				quad4(0, 1, 3, 2);
				shift(2, 0);
				shift(3, 1);
				prim_n = 2;
			}
			break;
	}
}

void DSGXNative::shift(int s, int d) {
	prim_p[d] = prim_p[s];
	prim_c[d] = prim_c[s];
	prim_u[d] = prim_u[s];
	prim_o[d] = prim_o[s];
}

double DSGXNative::dist(const Vector4 &p, int plane) {
	const int k = plane >> 1;
	const double v = k == 0 ? (double)p.x : (k == 1 ? (double)p.y : (double)p.z);
	return (plane & 1) == 0 ? (double)p.w + v : (double)p.w - v;
}

// facing from the clip-space (x, y, w) triple product (see ds_gx.gd _facing)
static double facing(const Vector4 &pa, const Vector4 &pb, const Vector4 &pc) {
	const double ax = pa.x, ay = pa.y, aw = pa.w, bx = pb.x, by = pb.y, bw = pb.w, cx = pc.x, cy = pc.y, cw = pc.w;
	const double nx = (ay - by) * (cw - bw) - (aw - bw) * (cy - by);
	const double ny = (aw - bw) * (cx - bx) - (ax - bx) * (cw - bw);
	const double nz = (ax - bx) * (cy - by) - (ay - by) * (cx - bx);
	return bx * nx + by * ny + bw * nz;
}

bool DSGXNative::culled(double dot) const {
	if (dot < 0.0) return (polyattr & 0x80) == 0;
	if (dot > 0.0) return (polyattr & 0x40) == 0;
	return false;
}

static const Vector4 L0(1, 0, 0, 0), L1(0, 1, 0, 0), L2(0, 0, 1, 0), L3(0, 0, 0, 1);

// register the polygon of vertex slots idx[0..n) and find it in the previous list (ds_gx.gd _poly_begin)
void DSGXNative::poly_begin(const int *idx, int n) {
	const size_t k = poly_key.size() / 3;
	poly_key.push_back(polyattr);
	poly_key.push_back(teximage);
	poly_key.push_back(pltt);
	for (int j = 0; j < 4; j++) {
		const int s = idx[j < n ? j : n - 1];
		poly_uv.push_back(prim_u[s]);
		poly_v.push_back(prim_p[s]);
	}
	pv_ok = k * 3 + 2 < prev_key.size() && prev_key[k * 3] == polyattr && prev_key[k * 3 + 1] == teximage &&
			prev_key[k * 3 + 2] == pltt;
	if (pv_ok)
		for (int j = 0; j < 4; j++)
			if (prev_uv[k * 4 + j] != poly_uv[k * 4 + j]) {
				pv_ok = false;
				break;
			}
	if (pv_ok)
		for (int j = 0; j < 4; j++) {
			pv[j] = prev_v[k * 4 + j];
			cv[j] = poly_v[k * 4 + j];
		}
}

Vector4 DSGXNative::prev_of(const Vector4 &lam) const {
	if (!pv_ok) return Vector4();
	const Vector4 p = pv[0] * lam.x + pv[1] * lam.y + pv[2] * lam.z + pv[3] * lam.w;
	const Vector4 c = cv[0] * lam.x + cv[1] * lam.y + cv[2] * lam.z + cv[3] * lam.w;
	const double w = p.w, wc = c.w;
	if (w <= 0.0 || wc <= 0.0) return Vector4();
	const double vw = (double)(vp_x2 - vp_x1 + 1);
	const double vh = (double)(vp_y2 - vp_y1 + 1);
	return Vector4((real_t)(((double)p.x + w) * vw / (2.0 * w) - ((double)c.x + wc) * vw / (2.0 * wc)),
			(real_t)((-(double)p.y + w) * vh / (2.0 * w) - (-(double)c.y + wc) * vh / (2.0 * wc)), 1.0f, 0.0f);
}

void DSGXNative::tri(int ia, int ib, int ic) {
	const int idx[3] = { ia, ib, ic };
	poly_begin(idx, 3);
	const Vector4 pa = prim_p[ia], pb = prim_p[ib], pc = prim_p[ic];
	const int64_t ca = prim_o[ia], cb = prim_o[ib], cc = prim_o[ic];
	if ((ca & cb & cc) != 0) return;
	if ((polyattr & 0xC0) != 0xC0 && culled(facing(pa, pb, pc))) return;
	const double alpha = (double)((polyattr >> 16) & 31) / 31.0;
	if ((ca | cb | cc) == 0) {
		emit_tri(pa, prim_c[ia], prim_u[ia], pb, prim_c[ib], prim_u[ib], pc, prim_c[ic], prim_u[ic], alpha, 0, L0, L1, L2);
		return;
	}
	std::vector<PV> poly = { { pa, prim_c[ia], prim_u[ia], L0 }, { pb, prim_c[ib], prim_u[ib], L1 }, { pc, prim_c[ic], prim_u[ic], L2 } };
	clip_emit(poly, alpha);
}

// a quad is one polygon on the DS: culled and clipped as a whole (see ds_gx.gd _quad4)
void DSGXNative::quad4(int i0, int i1, int i2, int i3) {
	const int idx[4] = { i0, i1, i2, i3 };
	poly_begin(idx, 4);
	const int64_t o0 = prim_o[i0], o1 = prim_o[i1], o2 = prim_o[i2], o3 = prim_o[i3];
	if ((o0 & o1 & o2 & o3) != 0) return;
	if ((polyattr & 0xC0) != 0xC0) {
		double dot = facing(prim_p[i0], prim_p[i1], prim_p[i2]);
		if (dot == 0.0) dot = facing(prim_p[i0], prim_p[i2], prim_p[i3]);
		if (culled(dot)) return;
	}
	const double alpha = (double)((polyattr >> 16) & 31) / 31.0;
	if ((o0 | o1 | o2 | o3) == 0) {
		emit_tri(prim_p[i0], prim_c[i0], prim_u[i0], prim_p[i1], prim_c[i1], prim_u[i1], prim_p[i2], prim_c[i2], prim_u[i2], alpha, 4, L0, L1, L2);
		emit_tri(prim_p[i0], prim_c[i0], prim_u[i0], prim_p[i2], prim_c[i2], prim_u[i2], prim_p[i3], prim_c[i3], prim_u[i3], alpha, 1, L0, L2, L3);
		return;
	}
	std::vector<PV> poly = { { prim_p[i0], prim_c[i0], prim_u[i0], L0 }, { prim_p[i1], prim_c[i1], prim_u[i1], L1 },
		{ prim_p[i2], prim_c[i2], prim_u[i2], L2 }, { prim_p[i3], prim_c[i3], prim_u[i3], L3 } };
	clip_emit(poly, alpha);
}

void DSGXNative::clip_emit(std::vector<PV> &poly, double alpha) {
	for (int plane = 0; plane < 6; plane++) {
		bool inside = true;
		for (const PV &v : poly) {
			if (dist(v.p, plane) < 0.0) {
				inside = false;
				break;
			}
		}
		if (!inside) {
			std::vector<PV> out;
			const size_t n = poly.size();
			for (size_t i = 0; i < n; i++) {
				const PV &cur = poly[i];
				const PV &nxt = poly[(i + 1) % n];
				const double dc = dist(cur.p, plane);
				const double dn = dist(nxt.p, plane);
				if (dc >= 0.0) out.push_back(cur);
				if ((dc >= 0.0) != (dn >= 0.0)) {
					const double t = dc / (dc - dn);
					out.push_back({ cur.p.lerp(nxt.p, (real_t)t), cur.c.lerp(nxt.c, (real_t)t), cur.u.lerp(nxt.u, (real_t)t),
							cur.l.lerp(nxt.l, (real_t)t) });
				}
			}
			poly.swap(out);
		}
		if (poly.size() < 3) return;
	}
	const size_t pn = poly.size();
	for (size_t i = 1; i + 1 < pn; i++) {
		const PV v0 = poly[0], v1 = poly[i], v2 = poly[i + 1];
		const int in = (i > 1 ? 1 : 0) | (i + 2 < pn ? 4 : 0);
		emit_tri(v0.p, v0.c, v0.u, v1.p, v1.c, v1.u, v2.p, v2.c, v2.u, alpha, in, v0.l, v1.l, v2.l);
	}
}

void DSGXNative::emit(const Vector4 &p, const Color &col, const Vector2 &uv, double alpha, const Vector4 &box, const Vector4 &prev) {
	acc.pos.push_back(p);
	acc.prev.push_back(prev);
	acc.col.push_back(Color(col.r, col.g, col.b, alpha));
	acc.uv.push_back(uv);
	acc.attr.push_back((int32_t)(uint32_t)(polyattr & 0xFFFFFFFF));
	acc.tex.push_back((int32_t)(uint32_t)(teximage & 0xFFFFFFFF));
	acc.pal.push_back((int32_t)(uint32_t)(pltt & 0xFFFFFFFF));
	acc.uvbox.push_back(box);
}

void DSGXNative::emit_tri(const Vector4 &pa, const Color &ca, const Vector2 &ua, const Vector4 &pb, const Color &cb,
		const Vector2 &ub, const Vector4 &pc, const Color &cc, const Vector2 &uc, double alpha, int inner,
		const Vector4 &la4, const Vector4 &lb4, const Vector4 &lc4) {
	const double wa = pa.w, wb = pb.w, wc = pc.w;
	if (wa <= 0.0 || wb <= 0.0 || wc <= 0.0) return;
	const double vw = (double)(vp_x2 - vp_x1 + 1);
	const double vh = (double)(vp_y2 - vp_y1 + 1);
	const double ox = (double)vp_x1;
	const double oy = (double)(191 - vp_y2);
	const double ax = std::floor(((double)pa.x + wa) * vw / (2.0 * wa) + 1e-4) + ox;
	const double ay = std::floor((-(double)pa.y + wa) * vh / (2.0 * wa) + 1e-4) + oy;
	const double bx = std::floor(((double)pb.x + wb) * vw / (2.0 * wb) + 1e-4) + ox;
	const double by = std::floor((-(double)pb.y + wb) * vh / (2.0 * wb) + 1e-4) + oy;
	const double cx = std::floor(((double)pc.x + wc) * vw / (2.0 * wc) + 1e-4) + ox;
	const double cy = std::floor((-(double)pc.y + wc) * vh / (2.0 * wc) + 1e-4) + oy;
	const double area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
	const Vector4 box(minf(ua.x, minf(ub.x, uc.x)), minf(ua.y, minf(ub.y, uc.y)), maxf(ua.x, maxf(ub.x, uc.x)),
			maxf(ua.y, maxf(ub.y, uc.y)));
	if (!dilate) {
		emit(Vector4((ax / 128.0 - 1.0) * wa, (1.0 - ay / 96.0) * wa, pa.z, wa), ca, ua, alpha, box, prev_of(la4));
		emit(Vector4((bx / 128.0 - 1.0) * wb, (1.0 - by / 96.0) * wb, pb.z, wb), cb, ub, alpha, box, prev_of(lb4));
		emit(Vector4((cx / 128.0 - 1.0) * wc, (1.0 - cy / 96.0) * wc, pc.z, wc), cc, uc, alpha, box, prev_of(lc4));
		return;
	}
	if (area == 0.0) return;
	double sx[3] = { ax, bx, cx }, sy[3] = { ay, by, cy };
	if (area < 0.0) {
		sx[1] = cx; sx[2] = bx;
		sy[1] = cy; sy[2] = by;
	}
	int qs[3];
	for (int i = 0; i < 3; i++) {
		const int j = (i + 1) % 3;
		qs[i] = quad(sy[j] - sy[i], sx[i] - sx[j]);
	}
	static const Vector2 CORNER[4] = { Vector2(DILATE, DILATE), Vector2(-DILATE, DILATE), Vector2(-DILATE, -DILATE),
		Vector2(DILATE, -DILATE) };
	// Pieces: the snapped triangle itself (corners on the pixel grid, so every GPU rebuilds its attribute planes
	// exactly), then the dilation ring: a band along each outer edge and a corner wedge at each vertex. Inner
	// edges get no band and the ring is cut back to their line (mirror of DSGX._emit_tri).
	const int ino[3] = { area > 0.0 ? (inner & 1) : (inner & 4), inner & 2, area > 0.0 ? (inner & 4) : (inner & 1) };
	Vector2 pc_[7][8];
	int pn[7];
	int np_ = 0;
	pc_[0][0] = Vector2((real_t)sx[0], (real_t)sy[0]);
	pc_[0][1] = Vector2((real_t)sx[1], (real_t)sy[1]);
	pc_[0][2] = Vector2((real_t)sx[2], (real_t)sy[2]);
	pn[np_++] = 3;
	for (int i = 0; i < 3; i++) {
		const Vector2 vi((real_t)sx[i], (real_t)sy[i]);
		if (ino[i] == 0) {
			const Vector2 o = CORNER[qs[i]];
			const Vector2 vj((real_t)sx[(i + 1) % 3], (real_t)sy[(i + 1) % 3]);
			pc_[np_][0] = vi;
			pc_[np_][1] = vj;
			pc_[np_][2] = vj + o;
			pc_[np_][3] = vi + o;
			pn[np_++] = 4;
		}
		int q = qs[(i + 2) % 3];
		const int qe = qs[i];
		if (q != qe) {
			int m = 0;
			pc_[np_][m++] = vi;
			pc_[np_][m++] = vi + CORNER[q];
			while (q != qe) {
				q = (q + 1) & 3;
				pc_[np_][m++] = vi + CORNER[q];
			}
			pn[np_++] = m;
		}
	}
	const double ex[3] = { ax, bx, cx }, ey[3] = { ay, by, cy };
	for (int e = 0; e < 3; e++) {
		if ((inner & (1 << e)) == 0) continue;
		const int e1 = (e + 1) % 3, e2 = (e + 2) % 3;
		const double dx = ex[e1] - ex[e], dy = ey[e1] - ey[e];
		const double ref = dx * (ey[e2] - ey[e]) - dy * (ex[e2] - ex[e]);   // > 0 side = the triangle's side
		for (int pi = 1; pi < np_; pi++) {
			Vector2 cut[8];
			int m = 0;
			const int n = pn[pi];
			for (int k = 0; k < n; k++) {
				const Vector2 p0 = pc_[pi][k], p1 = pc_[pi][(k + 1) % n];
				const double s0 = (dx * ((double)p0.y - ey[e]) - dy * ((double)p0.x - ex[e])) * ref;
				const double s1 = (dx * ((double)p1.y - ey[e]) - dy * ((double)p1.x - ex[e])) * ref;
				if (s0 >= 0.0) cut[m++] = p0;
				if ((s0 > 0.0 && s1 < 0.0) || (s0 < 0.0 && s1 > 0.0)) {
					const double t = s0 / (s0 - s1);
					cut[m++] = Vector2((real_t)((double)p0.x + ((double)p1.x - (double)p0.x) * t),
							(real_t)((double)p0.y + ((double)p1.y - (double)p0.y) * t));
				}
			}
			pn[pi] = m;
			for (int k = 0; k < m; k++) pc_[pi][k] = cut[k];
		}
	}
	const double ia = 1.0 / wa, ib = 1.0 / wb, ic = 1.0 / wc;
	const double za = (double)pa.z * ia, zb = (double)pb.z * ib, zc = (double)pc.z * ic;
	const double inv_area = 1.0 / area;
	const int32_t pa32 = (int32_t)(uint32_t)(polyattr & 0xFFFFFFFF);
	const int32_t tx32 = (int32_t)(uint32_t)(teximage & 0xFFFFFFFF);
	const int32_t pl32 = (int32_t)(uint32_t)(pltt & 0xFFFFFFFF);
	for (int pi = 0; pi < np_; pi++) {
		const int n = pn[pi];
		if (n < 3) continue;
		Vector4 op[8];
		Color oc[8];
		Vector2 ou[8];
		Vector4 ov[8];
		for (int k = 0; k < n; k++) {
			const double x = pc_[pi][k].x, y = pc_[pi][k].y;
			const double lb = ((x - ax) * (cy - ay) - (y - ay) * (cx - ax)) * inv_area;
			const double lc = ((bx - ax) * (y - ay) - (by - ay) * (x - ax)) * inv_area;
			const double la = 1.0 - lb - lc;
			double qa = la * ia, qb = lb * ib, qc = lc * ic;
			double qsum = qa + qb + qc;
			if (qsum <= 1e-12) {
				qa = (la >= lb && la >= lc) ? 1.0 : 0.0;
				qb = (qa == 0.0 && lb >= lc) ? 1.0 : 0.0;
				qc = 1.0 - qa - qb;
				qsum = qa * ia + qb * ib + qc * ic;
				qa *= ia;
				qb *= ib;
				qc *= ic;
			}
			const double w = 1.0 / qsum;
			const Color col = (ca * (real_t)qa + cb * (real_t)qb + cc * (real_t)qc) * (real_t)w;
			oc[k] = Color(clampf(col.r, 0.0, 1.0), clampf(col.g, 0.0, 1.0), clampf(col.b, 0.0, 1.0), alpha);
			ou[k] = (ua * (real_t)qa + ub * (real_t)qb + uc * (real_t)qc) * (real_t)w;
			ov[k] = prev_of((la4 * (real_t)qa + lb4 * (real_t)qb + lc4 * (real_t)qc) * (real_t)w);
			const double z = (la * za + lb * zb + lc * zc) * w;
			op[k] = Vector4((x / 128.0 - 1.0) * w, (1.0 - y / 96.0) * w, z, w);
		}
		for (int k = 1; k + 1 < n; k++) {
			const int ms[3] = { 0, k, k + 1 };
			for (int m : ms) {
				acc.pos.push_back(op[m]);
				acc.col.push_back(oc[m]);
				acc.uv.push_back(ou[m]);
				acc.prev.push_back(ov[m]);
				acc.attr.push_back(pa32);
				acc.tex.push_back(tx32);
				acc.pal.push_back(pl32);
				acc.uvbox.push_back(box);
			}
		}
	}
}

// ------------------------------------------------------------------------------------------------ surfaces

Array DSGXNative::arrays(const std::vector<int64_t> &tris) const {
	const int64_t nv = (int64_t)tris.size() * 3;
	PackedVector3Array v;
	PackedVector2Array w;
	PackedColorArray col;
	PackedVector2Array uv;
	PackedFloat32Array c0, c1, c2;
	v.resize(nv);
	w.resize(nv);
	col.resize(nv);
	uv.resize(nv);
	c0.resize(nv * 4);
	c1.resize(nv * 4);
	c2.resize(nv * 4);
	Vector3 *pv = v.ptrw();
	Vector2 *pw = w.ptrw();
	Color *pc = col.ptrw();
	Vector2 *pu = uv.ptrw();
	float *p0 = c0.ptrw();
	float *p1 = c1.ptrw();
	float *p2 = c2.ptrw();
	int64_t j = 0;
	for (int64_t t : tris) {
		const int64_t tp = out_tex[t];
		const int64_t pa = out_attr[t];
		const int64_t pl = out_pal[t];
		const Vector4 bx = out_uvbox[t];
		for (int k = 0; k < 3; k++) {
			const int64_t i = t + k;
			const Vector4 p = out_pos[i];
			pv[j] = Vector3(p.x, p.y, p.z);
			pw[j] = Vector2(p.w, 0.0);
			pc[j] = out_col[i];
			pu[j] = out_uv[i];
			const int64_t q = j * 4;
			p0[q] = (float)(tp & 0xFFFF);
			p0[q + 1] = (float)((tp >> 16) & 0xFFFF);
			p0[q + 2] = (float)pl;
			p0[q + 3] = (float)(pa & 0xFFFF);
			p1[q] = (float)((pa >> 16) & 0xFFFF);
			const Vector4 pr = i < (int64_t)out_prev.size() ? out_prev[i] : Vector4();
			p1[q + 1] = pr.x;   // previous screen position (smooth motion), valid flag
			p1[q + 2] = pr.y;
			p1[q + 3] = pr.z;
			p2[q] = bx.x;
			p2[q + 1] = bx.y;
			p2[q + 2] = bx.z;
			p2[q + 3] = bx.w;
			j += 1;
		}
	}
	Array arr;
	arr.resize(ARRAY_MAX);
	arr[ARRAY_VERTEX] = v;
	arr[ARRAY_TEX_UV2] = w;
	arr[ARRAY_COLOR] = col;
	arr[ARRAY_TEX_UV] = uv;
	arr[ARRAY_CUSTOM0] = c0;
	arr[ARRAY_CUSTOM1] = c1;
	arr[ARRAY_CUSTOM2] = c2;
	return arr;
}

// same split as DSRender3D._prepare: opaque surface, then translucent runs in order (depth write, polygon id)
Array DSGXNative::prepare() const {
	const int64_t n = (int64_t)out_pos.size();
	std::vector<int64_t> opaque;
	struct Run {
		bool dw;
		int64_t pid;
		std::vector<int64_t> tris;
	};
	std::vector<Run> runs;
	for (int64_t t = 0; t < n; t += 3) {
		const int64_t pa = out_attr[t];
		const int64_t tp = out_tex[t];
		const int64_t alpha = (pa >> 16) & 31;
		const int64_t fmt = (tp >> 26) & 7;
		const bool trans = (alpha > 0 && alpha < 31) || fmt == 1 || fmt == 6;
		if (!trans) {
			opaque.push_back(t);
		} else {
			const bool dw = (pa & 0x800) != 0;
			const int64_t pid = (pa >> 24) & 63;
			if (runs.empty() || runs.back().dw != dw || runs.back().pid != pid) runs.push_back({ dw, pid, {} });
			runs.back().tris.push_back(t);
		}
	}
	Array surf;
	if (!opaque.empty()) {
		Array s;
		s.append(arrays(opaque));
		s.append(0);
		s.append(false);
		s.append(0);
		surf.append(s);
	}
	for (const Run &r : runs) {
		Array s;
		s.append(arrays(r.tris));
		s.append(1);
		s.append(r.dw);
		s.append(r.pid);
		surf.append(s);
	}
	return surf;
}

// ------------------------------------------------------------------------------------------------ outputs

PackedVector4Array DSGXNative::get_out_pos() const {
	PackedVector4Array a;
	a.resize(out_pos.size());
	for (size_t i = 0; i < out_pos.size(); i++) a.set(i, out_pos[i]);
	return a;
}
PackedColorArray DSGXNative::get_out_col() const {
	PackedColorArray a;
	a.resize(out_col.size());
	for (size_t i = 0; i < out_col.size(); i++) a.set(i, out_col[i]);
	return a;
}
PackedVector2Array DSGXNative::get_out_uv() const {
	PackedVector2Array a;
	a.resize(out_uv.size());
	for (size_t i = 0; i < out_uv.size(); i++) a.set(i, out_uv[i]);
	return a;
}
static PackedInt32Array to_i32(const std::vector<int32_t> &v) {
	PackedInt32Array a;
	a.resize(v.size());
	for (size_t i = 0; i < v.size(); i++) a.set(i, v[i]);
	return a;
}
PackedInt32Array DSGXNative::get_out_attr() const { return to_i32(out_attr); }
PackedInt32Array DSGXNative::get_out_tex() const { return to_i32(out_tex); }
PackedInt32Array DSGXNative::get_out_pal() const { return to_i32(out_pal); }
PackedVector4Array DSGXNative::get_out_prev() const {
	PackedVector4Array a;
	a.resize(out_prev.size());
	for (size_t i = 0; i < out_prev.size(); i++) a.set(i, out_prev[i]);
	return a;
}

PackedVector4Array DSGXNative::get_out_uvbox() const {
	PackedVector4Array a;
	a.resize(out_uvbox.size());
	for (size_t i = 0; i < out_uvbox.size(); i++) a.set(i, out_uvbox[i]);
	return a;
}
