shader_type spatial;
// DS 3D polygons as produced by DSGX: VERTEX = clip xyz (viewport already applied), UV2.x = clip w,
// COLOR = vertex colour + polygon alpha, UV = texture coordinate in texels,
// CUSTOM0 = (TEXIMAGE_PARAM low16, high16, PLTT_BASE, POLYGON_ATTR low16), CUSTOM1.x = POLYGON_ATTR high16,
// CUSTOM2 = the triangle's texture coordinate range (min u, v, max u, v).
// Textures are decoded here straight from texture VRAM / texture palette VRAM (GBATEK "DS 3D Textures").
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix, skip_vertex_transform, fog_disabled;

uniform sampler2D texvram : filter_nearest;   // R8 1024x512 (4 slots x 128 KiB)
uniform sampler2D palvram : filter_nearest;   // R8 1024x96 (6 slots x 16 KiB)
uniform int disp3dcnt = 1;
uniform int alpha_ref = 0;
uniform bool opaque_rear = false;   // CLEAR_COLOR alpha > 0: translucent polygons blend over opaque pixels
uniform vec3 toon[32];
uniform float enc6[64];
// QoL smooth motion: < 1 draws this polygon list moved back toward the previous one. A GLOBAL uniform (project.godot
// [shader_globals]): one update per display frame for every material instead of one per material (part 20, speed)
global uniform float ds_interp_3d;
#define interp ds_interp_3d

// QoL WEIRD SETTINGS (part 21, picture only): DSRender3D compiles variants with these defined only while in use.
// FX_ANY: either of the next two. FX_FUZZY (TOUCH FUZZY in battles): the stage geometry (perspective polygons; battle
// sprites, effects and HUD pieces are orthographic quads with w = 1 and stay as they are) zoom-pulses with the 2D
// layers and its texture content waves per scanline (texture coordinates moved by the screen-space warp of
// ds_engine2d's fz_wave). FX_ID (BEVEL EMBOSS, the second "id" render): every polygon writes an object id instead of
// its colour: r = depth rank (orthographic sprites 32-63 by their z: clip z = -(sprite +0x3C z) / 1024, stage 0-31 by
// distance), g/b = a 12-bit hash of
// its texture / palette; the rear plane (UV2.y = 1) and faint translucent pixels write nothing.
#ifdef FX_FUZZY
global uniform vec4 ds_fx;   // x = time (s), y = TOUCH FUZZY strength 0..1 (DSDisplay)
vec2 fz_wave(float fy) {
	float t = ds_fx.x, s = ds_fx.y;
	return s * vec2(4.5 * sin(fy * 0.105 + t * 1.9) + 2.5 * sin(fy * 0.031 - t * 1.13),
		4.5 * sin(fy * 0.057 + t * 1.37));
}
float fz_zoom() { return 1.0 + ds_fx.y * 0.06 * (0.5 + 0.5 * sin(ds_fx.x * 0.83)); }
#endif
#ifdef FX_ANY
varying flat float fx_ortho;
varying flat float fx_z;
varying flat float fx_rear;
#endif
varying flat vec4 a0;
varying flat vec4 a1;
varying flat vec4 uvbox;

void vertex() {
	// clip space straight from DSGX. The render target is stored bottom-up, so the 2D compositor's row y
	// (0 = top, texelFetch) needs DS +y (up) mapped to the texture's last row: flip y. Godot's depth test is
	// reverse-Z (larger = nearer) while DS depth grows away from the viewer: map z/w in [-1, 1] to
	// (1 - z/w) / 2, which lies in [0, 1] (valid clip range for both the OpenGL and Vulkan back ends).
	float w = UV2.x;
	POSITION = vec4(VERTEX.x, -VERTEX.y, (w - VERTEX.z) * 0.5, w);
	// in-between frame: each vertex moves back by its screen motion since the previous list (CUSTOM1.yz), in
	// whole pixels so the image stays on the DS pixel grid; jumps over 32 px (cuts, teleports) are not blended
	if (interp < 1.0 && CUSTOM1.w > 0.5) {
		// moved back toward the previous frame's position by whole DS pixels (0 px = untouched)
		vec2 mv = CUSTOM1.yz;
		if (abs(mv.x) <= 32.0 && abs(mv.y) <= 32.0) {
			vec2 sh = -floor(-mv * (1.0 - interp) + 0.5);   // same rounding as ds_engine2d (round() is GPU-defined at .5)
			// a vertex on the screen's edge (where the polygon was clipped) stays on it: moving it inward would open a
			// strip of void / far background along that edge during fast camera moves (part 17). The polygon goes on
			// past the edge, so keeping the edge vertex there only stretches it by the in-between distance.
			vec2 sp = vec2((VERTEX.x / w + 1.0) * 128.0, (1.0 - VERTEX.y / w) * 96.0);
			if (sp.x <= 0.5) sh.x = min(sh.x, 0.0);
			if (sp.x >= 255.5) sh.x = max(sh.x, 0.0);
			if (sp.y <= 0.5) sh.y = min(sh.y, 0.0);
			if (sp.y >= 191.5) sh.y = max(sh.y, 0.0);
			POSITION.x += sh.x / 128.0 * w;
			POSITION.y += sh.y / 96.0 * w;
		}
	}
#ifdef FX_ANY
	// battle sprites: the game's orthographic projection (FUN_02011384: G3_OrthoW, scaleW 1.0) gives w = 1 and a
	// small z; stage vertices clipped at the near plane also have w = 1 but sit at z = -w
	bool ortho = abs(w - 1.0) < 0.0001 && abs(VERTEX.z) < 0.5;
	fx_ortho = ortho ? 1.0 : 0.0;
	fx_z = VERTEX.z / w;
	fx_rear = UV2.y;
#endif
#ifdef FX_FUZZY
	if (!ortho && ds_fx.y > 0.0) POSITION.xy *= fz_zoom();   // the stage zooms about the screen centre
#endif
	//DEPTH_BIAS
	a0 = CUSTOM0;
	a1 = CUSTOM1;
	uvbox = CUSTOM2;
}

int t8(int a) { return int(texelFetch(texvram, ivec2(a & 1023, (a >> 10) & 511), 0).r * 255.0 + 0.5); }
int t16(int a) { return t8(a) | (t8(a + 1) << 8); }
// texture palette memory is 96 KiB (6 slots of 16 KiB): addresses wrap at 0x18000 (an `& 0x17FFF` mask dropped bit 15,
// so every palette above 32 KiB read slot 0/1 - e.g. the Maximum rank bars drew black)
int p16(int a) { a = a % 0x18000; return int(texelFetch(palvram, ivec2(a & 1023, a >> 10), 0).r * 255.0 + 0.5)
	| (int(texelFetch(palvram, ivec2((a + 1) & 1023, (a + 1) >> 10), 0).r * 255.0 + 0.5) << 8); }
vec3 c15(int c) { return vec3(float(c & 31), float((c >> 5) & 31), float((c >> 10) & 31)) / 31.0; }

int wrapc(int v, int size, bool rep, bool flip) {
	if (!rep) return clamp(v, 0, size - 1);
	if (flip) { int m = v & (size * 2 - 1); return m >= size ? size * 2 - 1 - m : m; }
	return v & (size - 1);
}

// texel colour (rgb 0..1) and alpha (0..1)
vec4 texel(int tp, int pal, vec2 uv) {
	int fmt = (tp >> 26) & 7;
	int sw = 8 << ((tp >> 20) & 7), th = 8 << ((tp >> 23) & 7);
	int s = wrapc(int(floor(uv.x)), sw, (tp & 0x10000) != 0, (tp & 0x40000) != 0);
	int t = wrapc(int(floor(uv.y)), th, (tp & 0x20000) != 0, (tp & 0x80000) != 0);
	int base = (tp & 0xFFFF) * 8;
	bool c0t = (tp & 0x20000000) != 0;
	int pb = pal * 16;
	if (fmt == 1) {          // A3I5
		int b = t8(base + t * sw + s);
		int a = b >> 5;
		return vec4(c15(p16(pb + (b & 31) * 2)), float(a * 4 + a / 2) / 31.0);
	} else if (fmt == 2) {   // 4 colours
		int b = t8(base + ((t * sw + s) >> 2));
		int i = (b >> ((s & 3) * 2)) & 3;
		if (c0t && i == 0) return vec4(0.0);
		return vec4(c15(p16(pal * 8 + i * 2)), 1.0);
	} else if (fmt == 3) {   // 16 colours
		int b = t8(base + ((t * sw + s) >> 1));
		int i = (s & 1) != 0 ? b >> 4 : b & 15;
		if (c0t && i == 0) return vec4(0.0);
		return vec4(c15(p16(pb + i * 2)), 1.0);
	} else if (fmt == 4) {   // 256 colours
		int i = t8(base + t * sw + s);
		if (c0t && i == 0) return vec4(0.0);
		return vec4(c15(p16(pb + i * 2)), 1.0);
	} else if (fmt == 5) {   // 4x4 compressed
		int blk = (t >> 2) * (sw >> 2) + (s >> 2);
		int bits = t8(base + blk * 4 + (t & 3));
		int i = (bits >> ((s & 3) * 2)) & 3;
		int slot1 = 0x20000 + ((base & 0x1FFFF) >> 1) + (base >= 0x40000 ? 0x10000 : 0);
		int info = t16(slot1 + blk * 2);
		int pa = pb + (info & 0x3FFF) * 4;
		int mode = (info >> 14) & 3;
		vec3 c0 = c15(p16(pa)), c1 = c15(p16(pa + 2));
		if (i == 0) return vec4(c0, 1.0);
		if (i == 1) return vec4(c1, 1.0);
		if (mode == 0) return i == 2 ? vec4(c15(p16(pa + 4)), 1.0) : vec4(0.0);
		if (mode == 1) return i == 2 ? vec4((c0 + c1) * 0.5, 1.0) : vec4(0.0);
		if (mode == 2) return vec4(c15(p16(pa + i * 2)), 1.0);
		return i == 2 ? vec4((c0 * 5.0 + c1 * 3.0) / 8.0, 1.0) : vec4((c0 * 3.0 + c1 * 5.0) / 8.0, 1.0);
	} else if (fmt == 6) {   // A5I3
		int b = t8(base + t * sw + s);
		return vec4(c15(p16(pb + (b & 7) * 2)), float(b >> 3) / 31.0);
	} else if (fmt == 7) {   // direct colour
		int c = t16(base + (t * sw + s) * 2);
		return vec4(c15(c), (c & 0x8000) != 0 ? 1.0 : 0.0);
	}
	return vec4(1.0);
}

void fragment() {
	int tp = int(a0.x + 0.5) | (int(a0.y + 0.5) << 16);
	int pal = int(a0.z + 0.5);
	int pa = int(a0.w + 0.5) | (int(a1.x + 0.5) << 16);
	int mode = (pa >> 4) & 3;
	vec4 v = COLOR;
	vec4 c = v;
	int fmt = (tp >> 26) & 7;
	if (fmt != 0 && (disp3dcnt & 1) != 0) {
		// the DS evaluates attributes at the pixel's top-left corner, the GPU at its centre
		vec2 uvc = UV - 0.5 * dFdx(UV) - 0.5 * dFdy(UV) + vec2(1.0 / 512.0);   // + float error margin (texel units)
		// the DS interpolates between the span's edge values: never outside the polygon's own range
#ifdef FX_FUZZY
		if (fx_ortho < 0.5 && ds_fx.y > 0.0) {   // stage: sample where the warped screen position falls (whole DS px)
			vec2 wv = floor(fz_wave(FRAGCOORD.y) + 0.5);
			uvc += dFdx(UV) * wv.x + dFdy(UV) * wv.y;
		}
#endif
		uvc = clamp(uvc, uvbox.xy, max(uvbox.xy, uvbox.zw - vec2(1.0 / 256.0)));
		vec4 t = texel(tp, pal, uvc);
		if (t.a <= 0.0 && mode != 1) discard;   // transparent texel
		if (mode == 1) {        // decal
			c = vec4(mix(v.rgb, t.rgb, t.a), v.a);
		} else {                // modulate (6-bit maths: ((t+1)*(v+1)-1)/64)
			// 5-bit colours widened to 6 bits (c*2 + (c != 0)), integer products (GBATEK "DS 3D Texture Blending")
			vec3 t5 = floor(t.rgb * 31.0 + 0.5), v5 = floor(v.rgb * 31.0 + 0.5);
			vec3 t6 = t5 * 2.0 + step(0.5, t5), v6 = v5 * 2.0 + step(0.5, v5);
			c.rgb = floor(((t6 + 1.0) * (v6 + 1.0) - 1.0) / 64.0) / 63.0;
			float ta = floor(t.a * 31.0 + 0.5), va = floor(v.a * 31.0 + 0.5);
			c.a = floor(((ta + 1.0) * (va + 1.0) - 1.0) / 32.0) / 31.0;
		}
	} else if (mode == 2) {    // toon / highlight from the vertex red channel
		vec3 tc = toon[int(floor(v.r * 31.0 + 0.5))];
		c.rgb = (disp3dcnt & 2) != 0 ? min(v.rgb + tc, vec3(1.0)) : tc;
	}
	if (c.a <= 0.0) discard;
	if ((disp3dcnt & 4) != 0 && floor(c.a * 31.0 + 0.5) <= float(alpha_ref)) discard;
#ifdef FX_ID
	if (fx_rear > 0.5 || c.a < 0.6) discard;
	int tpk = tp & 0x3FFFFFFF;
	int hsh = ((tpk & 0xFFFF) * 1103 + (tpk >> 20) * 151 + pal * 37) & 4095;
	float rk = fx_ortho > 0.5 ? 32.0 + clamp(floor(-fx_z * 1024.0 + 0.5), 0.0, 31.0)
		: clamp(31.0 - floor(log2(max(1.0 / FRAGCOORD.w, 1.0)) * 3.0), 0.0, 31.0);
	c.rgb = vec3(rk, float(hsh >> 6), float(hsh & 63)) / 63.0;
#endif
	// The Compatibility renderer writes ALBEDO to the viewport unchanged; the other renderers convert
	// linear -> sRGB on output, so hand them the linear value of the exact DS colour.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Compatibility: ALBEDO goes through Godot's approximate srgb_to_linear then linear_to_srgb, which is
	// not an identity in the dark range; enc6[] holds the pre-image of each 6-bit level (DSRender3D).
	ivec3 k6 = ivec3(clamp(floor(c.rgb * 63.0 + 0.5), 0.0, 63.0));
	ALBEDO = vec3(enc6[k6.r], enc6[k6.g], enc6[k6.b]);
#else
	ALBEDO = mix(c.rgb / 12.92, pow((c.rgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c.rgb));
#endif
	//ALPHA_LINE
}
