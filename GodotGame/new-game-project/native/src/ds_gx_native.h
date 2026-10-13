// Native DS geometry engine: a C++ port of scripts/render/ds_gx.gd (DSGX) plus the surface preparation of
// DSRender3D (_prepare/_arrays). It mirrors the GDScript arithmetic exactly (Godot's float32 vector types where
// the script uses them, double where the script uses plain floats), so both produce identical output
// (tools/bench_gx.gd compares the md5 of the two). See ds_gx.gd for the meaning of every step.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/projection.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <cstdint>
#include <vector>

namespace godot {

class DSGXNative : public RefCounted {
	GDCLASS(DSGXNative, RefCounted)

protected:
	static void _bind_methods();

public:
	DSGXNative();

	void run(const Array &cmds);
	int64_t get_swaps() const { return swaps; }
	int64_t get_tri_count() const { return (int64_t)out_pos.size() / 3; }
	void set_dilate(bool d) { dilate = d; }
	bool get_dilate() const { return dilate; }
	Array prepare() const;
	PackedVector4Array get_out_pos() const;
	PackedColorArray get_out_col() const;
	PackedVector2Array get_out_uv() const;
	PackedInt32Array get_out_attr() const;
	PackedInt32Array get_out_tex() const;
	PackedInt32Array get_out_pal() const;
	PackedVector4Array get_out_uvbox() const;
	PackedVector4Array get_out_prev() const;

private:
	struct Out {
		std::vector<Vector4> pos;
		std::vector<Color> col;
		std::vector<Vector2> uv;
		std::vector<int32_t> attr, tex, pal;
		std::vector<Vector4> uvbox;
		std::vector<Vector4> prev;   // previous screen position (QoL smooth motion), see ds_gx.gd out_prev
		void clear() {
			pos.clear(); col.clear(); uv.clear(); attr.clear(); tex.clear(); pal.clear(); uvbox.clear(); prev.clear();
		}
	};
	struct PV {   // clipping: vertex with its attributes
		Vector4 p;
		Color c;
		Vector2 u;
		Vector4 l;   // clip-space weights over the polygon's (up to 4) vertices
	};

	int NP[256];
	int64_t swaps = 0;
	bool dilate = true;
	Out acc;
	std::vector<Vector4> out_pos;
	std::vector<Color> out_col;
	std::vector<Vector2> out_uv;
	std::vector<int32_t> out_attr, out_tex, out_pal;
	std::vector<Vector4> out_uvbox;
	std::vector<Vector4> out_prev;
	int64_t swap_params = 0;
	// polygons of the list being built / of the previous list (ds_gx.gd poly_key / poly_uv / poly_v)
	std::vector<int64_t> poly_key, prev_key;
	std::vector<Vector2> poly_uv, prev_uv;
	std::vector<Vector4> poly_v, prev_v;
	bool pv_ok = false;
	Vector4 pv[4], cv[4];

	int64_t mtx_mode = 0;
	Projection proj, pos, vec, tex;
	Projection proj_stack[1];
	Projection pos_stack[31], vec_stack[31];
	int64_t stack_ptr = 0;
	Projection clip;
	bool clip_dirty = true;

	Color color = Color(1, 1, 1);
	Vector2 texcoord, texcoord0;
	Vector3 vtx;
	int64_t polyattr_next = 0, polyattr = 0, teximage = 0, pltt = 0;
	Color dif = Color(0, 0, 0), amb = Color(0, 0, 0), spe = Color(0, 0, 0), emi = Color(0, 0, 0);
	bool use_shine = false;
	float shininess[128];
	Vector3 light_vec[4];
	Color light_col[4];
	int64_t vp_x1 = 0, vp_y1 = 0, vp_x2 = 255, vp_y2 = 191;
	bool light_dirty = true;
	Vector3 light_half[4];
	double light_k[36];

	int64_t prim_type = -1;
	Vector4 prim_p[4];
	Color prim_c[4];
	Vector2 prim_u[4];
	int64_t prim_o[4];
	int64_t prim_n = 0, strip_n = 0;

	std::vector<int32_t> fifo_cmds, fifo_params;
	int64_t fifo_need = 0;
	int64_t port_cmd = -1;
	std::vector<int32_t> port_params;

	void swap_buffers();
	void run_words(const int32_t *w, int64_t n);
	void port_write(int64_t addr, int64_t v);
	void fifo_word(int64_t w);
	void flush_fifo();
	void cur_set(const Projection &m);
	void mul(const Projection &n);
	void exec(int64_t cmd, const int32_t *p, int64_t np, int64_t o);
	void light_prep();
	void normal(int64_t v);
	void vertex();
	void shift(int s, int d);
	void tri(int ia, int ib, int ic);
	void quad4(int i0, int i1, int i2, int i3);
	void clip_emit(std::vector<PV> &poly, double alpha);
	bool culled(double dot) const;
	void emit_tri(const Vector4 &pa, const Color &ca, const Vector2 &ua, const Vector4 &pb, const Color &cb,
			const Vector2 &ub, const Vector4 &pc, const Color &cc, const Vector2 &uc, double alpha, int inner,
			const Vector4 &la4, const Vector4 &lb4, const Vector4 &lc4);
	void emit(const Vector4 &p, const Color &col, const Vector2 &uv, double alpha, const Vector4 &box, const Vector4 &prev);
	void poly_begin(const int *idx, int n);
	Vector4 prev_of(const Vector4 &lam) const;
	static double dist(const Vector4 &p, int plane);
	Array arrays(const std::vector<int64_t> &tris) const;
};

} // namespace godot
