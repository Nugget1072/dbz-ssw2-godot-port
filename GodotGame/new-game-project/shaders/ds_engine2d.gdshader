shader_type canvas_item;
// One DS 2D graphics engine (A or B), rendered per pixel from the emulated hardware state:
// BG VRAM, OBJ VRAM, palette RAM, OAM, extended palettes and the engine's registers captured per scanline
// (so HBlank raster effects work). Follows GBATEK "DS Video": text/affine/extended BGs, OBJs (normal/affine,
// 1D/2D mapping, bitmap OBJs), windows, blending, master brightness, the 3D layer on engine A's BG0.
// The quad must cover 256x192 pixels; UV (0,0) = top-left.

uniform sampler2D bgvram : filter_nearest;    // R8, 1024 wide (engine A: 512 KiB, B: 128 KiB)
uniform sampler2D objvram : filter_nearest;   // R8, 1024 wide (A: 256 KiB, B: 128 KiB)
uniform sampler2D pal : filter_nearest;       // R8 1024x1: this engine's BG (0..511) + OBJ (512..1023) palettes
uniform sampler2D oam : filter_nearest;       // R8 1024x1
uniform sampler2D bgext : filter_nearest;     // R8 1024x32: BG extended palettes, 4 slots x 8 KiB
uniform sampler2D objext : filter_nearest;    // R8 1024x8: OBJ extended palette 8 KiB
uniform sampler2D regs : filter_nearest;      // R8 128x192: registers 0x00-0x7F as seen on each line
uniform sampler2D layer3d : filter_nearest;   // engine A: 3D render (RGBA, alpha = coverage)
uniform bool engine_a = true;
uniform bool has3d = false;
uniform bool premul3d = true;   // transparent rear plane: Godot stored polygon colour * alpha
// QoL smooth motion: in-between frames (interp < 1) move background scrolling and sprites back toward the previous
// frame's registers / OAM, by whole pixels; only when the layer / sprite is otherwise unchanged and moved <= 32 px
global uniform float ds_interp_2d;   // global (project.godot [shader_globals]): set once per display frame (part 20)
#define interp ds_interp_2d
uniform int layer_keep = 0x1F00;   // QoL: DISPCNT layer bits (BG0-3, OBJ) allowed on screen (behind the settings menu)
uniform sampler2D regs_prev : filter_nearest;
uniform sampler2D oam_prev : filter_nearest;
// QoL WEIRD SETTINGS (part 21, picture effects only). DSDisplay compiles variants of this shader with FX_BEVEL /
// FX_FUZZY defined (DSDisplay._engine_shader) only while a setting is in use; without them this is the plain shader.
// FX_BEVEL: alpha = the top layer's code (rank 1..20 by priority / layer order, +32 = the 3D layer, 0 = backdrop) for
// the bevel pass (shaders/ds_fx_bevel.gdshader). FX_FUZZY (engine A, battles): BG2 / BG3 sampled through a slow
// per-scanline sine warp + zoom pulse, and a light rainbow tint over the whole screen.
#ifdef FX_BEVEL
render_mode blend_disabled;
#define FX_ARG , inout int fx_code
#define FX_PASS , fx_code
#define FX_SET(v) fx_code = (v);
#else
#define FX_ARG
#define FX_PASS
#define FX_SET(v)
#endif
#ifdef FX_SHAKE
uniform ivec2 fx_shake;   // SCREEN SHAKE (part 23): the picture moved by this many DS px, edge pixels repeated
#endif
#ifdef FX_FUZZY
global uniform vec4 ds_fx;   // x = time (s), y = TOUCH FUZZY strength 0..1 (DSDisplay registers it at runtime)
// per-scanline offset of a layer (DS px) at line fy (same functions as ds_poly's FX_FUZZY: keep them in step)
vec2 fz_wave(float fy) {
	float t = ds_fx.x, s = ds_fx.y;
	return s * vec2(4.5 * sin(fy * 0.105 + t * 1.9) + 2.5 * sin(fy * 0.031 - t * 1.13),
		4.5 * sin(fy * 0.057 + t * 1.37));
}
float fz_zoom() { return 1.0 + ds_fx.y * 0.06 * (0.5 + 0.5 * sin(ds_fx.x * 0.83)); }   // only ever magnifies
// where the warped layer's pixel (x, y) is sampled
ivec2 fz_warp(int x, int y) {
	vec2 p = vec2(128.0, 96.0) + (vec2(float(x), float(y)) + 0.5 - vec2(128.0, 96.0)) / fz_zoom();
	p += fz_wave(float(y) + 0.5);
	return ivec2(int(floor(p.x)), clamp(int(floor(p.y)), 0, 191));
}
// light rainbow filter: a pastel hue drifting over time (period 6.5 s) and across the screen
vec3 fz_tint(vec3 c6, int x, int y) {
	float s = ds_fx.y, t = ds_fx.x;
	if (s <= 0.0) return c6;
	float h = fract(t / 6.5 + (float(x) * 0.7 + float(y)) / 420.0 + 0.06 * sin(t * 0.7 + float(x) * 0.025));
	vec3 rb = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	vec3 c = c6 / 63.0;
	vec3 o = c * mix(vec3(1.0), rb, 0.24) + mix(vec3(1.0), rb, 0.75) * 0.11;
	return clamp(floor(mix(c, o, s) * 63.0 + 0.5), 0.0, 63.0);
}
#endif
int lerp_pos(int cur, int prev, int mask) {   // cur moved back toward prev (wrapping coordinates)
	int half = (mask + 1) >> 1;
	int d = ((cur - prev + half) & mask) - half;
	if (d < -32 || d > 32) return cur;
	return (cur - int(floor(float(d) * (1.0 - interp) + 0.5))) & mask;   // same rounding as ds_poly
}

int r8(sampler2D t, int a) { return int(texelFetch(t, ivec2(a & 1023, a >> 10), 0).r * 255.0 + 0.5); }
int r16(sampler2D t, int a) { return r8(t, a) | (r8(t, a + 1) << 8); }
int rg8(int line, int o) { return int(texelFetch(regs, ivec2(o, line), 0).r * 255.0 + 0.5); }
int rg16(int line, int o) { return rg8(line, o) | (rg8(line, o + 1) << 8); }
int rg32(int line, int o) { return rg16(line, o) | (rg16(line, o + 2) << 16); }
int sx(int v, int bits) { int s = 1 << (bits - 1); return (v & (s * 2 - 1)) - ((v & s) != 0 ? s * 2 : 0); }
// colours are carried in the LCD's 6-bit scale (x/63): 2D colours are 5-bit << 1, the 3D layer is native 6-bit
vec3 c15(int c) { return vec3(float(c & 31), float((c >> 5) & 31), float((c >> 10) & 31)) * 2.0 / 63.0; }

// result of one layer at a pixel: color (15-bit), opaque flag
struct Px { int col; bool ok; int prio; };

Px pal_bg(int idx) { Px p; p.col = r16(pal, idx * 2); p.ok = true; p.prio = 0; return p; }

// ---------------------------------------------------------------- text BG
Px text_bg(int line, int bg, int x, int y, int dispcnt) {
	Px p; p.ok = false; p.col = 0;
	int cnt = rg16(line, 8 + bg * 2);
	p.prio = cnt & 3;
	int hofs = rg16(line, 0x10 + bg * 4) & 511;
	int vofs = rg16(line, 0x12 + bg * 4) & 511;
	if (interp < 1.0) {
		int pcnt = int(texelFetch(regs_prev, ivec2(8 + bg * 2, line), 0).r * 255.0 + 0.5) | (int(texelFetch(regs_prev, ivec2(9 + bg * 2, line), 0).r * 255.0 + 0.5) << 8);
		if (pcnt == cnt) {
			int ph = int(texelFetch(regs_prev, ivec2(0x10 + bg * 4, line), 0).r * 255.0 + 0.5) | (int(texelFetch(regs_prev, ivec2(0x11 + bg * 4, line), 0).r * 255.0 + 0.5) << 8);
			int pv = int(texelFetch(regs_prev, ivec2(0x12 + bg * 4, line), 0).r * 255.0 + 0.5) | (int(texelFetch(regs_prev, ivec2(0x13 + bg * 4, line), 0).r * 255.0 + 0.5) << 8);
			hofs = lerp_pos(hofs, ph & 511, 511);
			vofs = lerp_pos(vofs, pv & 511, 511);
		}
	}
	int px = (x + hofs), py = (y + vofs);
	int size = (cnt >> 14) & 3;
	int w = (size & 1) != 0 ? 512 : 256;
	int h = (size & 2) != 0 ? 512 : 256;
	px &= w - 1; py &= h - 1;
	int charbase = ((cnt >> 2) & 15) * 0x4000;
	int scrbase = ((cnt >> 8) & 31) * 0x800;
	if (engine_a) { charbase += ((dispcnt >> 24) & 7) * 0x10000; scrbase += ((dispcnt >> 27) & 7) * 0x10000; }
	int blk = (px >> 8) + ((py >> 8) * (w >> 8));
	int ent = r16(bgvram, scrbase + blk * 0x800 + (((py & 255) >> 3) * 32 + ((px & 255) >> 3)) * 2);
	int tx = px & 7, ty = py & 7;
	if ((ent & 0x400) != 0) tx = 7 - tx;
	if ((ent & 0x800) != 0) ty = 7 - ty;
	int tile = ent & 1023;
	if ((cnt & 0x80) != 0) {   // 256 colours
		int ci = r8(bgvram, charbase + tile * 64 + ty * 8 + tx);
		if (ci == 0) return p;
		if ((dispcnt & 0x40000000) != 0) {   // extended palettes: slot = bg (BG0/1 may use slot 2/3)
			int slot = bg;
			if (bg < 2 && (cnt & 0x2000) != 0) slot = bg + 2;
			p.col = r16(bgext, slot * 0x2000 + ((ent >> 12) & 15) * 512 + ci * 2);
		} else {
			p.col = r16(pal, ci * 2);
		}
	} else {
		int b = r8(bgvram, charbase + tile * 32 + ty * 4 + (tx >> 1));
		int ci = (tx & 1) != 0 ? (b >> 4) : (b & 15);
		if (ci == 0) return p;
		p.col = r16(pal, (((ent >> 12) & 15) * 16 + ci) * 2);
	}
	p.ok = true;
	return p;
}

// ---------------------------------------------------------------- affine / extended BG (bg = 2 or 3)
// kind: 1 affine (8-bit map), 2 extended (16-bit map / bitmaps)
Px affine_bg(int line, int bg, int x, int dispcnt, int kind) {
	Px p; p.ok = false; p.col = 0;
	int cnt = rg16(line, 8 + bg * 2);
	p.prio = cnt & 3;
	int o = bg == 2 ? 0x20 : 0x30;
	int pa = sx(rg16(line, o), 16), pc = sx(rg16(line, o + 4), 16);
	int refx = sx(rg32(line, o + 8), 28), refy = sx(rg32(line, o + 12), 28);   // internal reference (per line)
	int tx = (refx + pa * x) >> 8;
	int ty = (refy + pc * x) >> 8;
	bool wrap = (cnt & 0x2000) != 0;
	int size = (cnt >> 14) & 3;
	int charbase = ((cnt >> 2) & 15) * 0x4000;
	int scrbase = ((cnt >> 8) & 31) * 0x800;
	if (engine_a) { charbase += ((dispcnt >> 24) & 7) * 0x10000; scrbase += ((dispcnt >> 27) & 7) * 0x10000; }
	if (kind == 1 || (cnt & 0x80) == 0) {
		int n = kind == 1 ? (128 << size) : (128 << size);
		if (wrap) { tx &= n - 1; ty &= n - 1; } else if (tx < 0 || ty < 0 || tx >= n || ty >= n) return p;
		if (kind == 1) {
			int tile = r8(bgvram, scrbase + (ty >> 3) * (n >> 3) + (tx >> 3));
			int ci = r8(bgvram, charbase + tile * 64 + (ty & 7) * 8 + (tx & 7));
			if (ci == 0) return p;
			p.col = r16(pal, ci * 2);
		} else {   // extended, 16-bit map entries
			int ent = r16(bgvram, scrbase + ((ty >> 3) * (n >> 3) + (tx >> 3)) * 2);
			int px = tx & 7, py = ty & 7;
			if ((ent & 0x400) != 0) px = 7 - px;
			if ((ent & 0x800) != 0) py = 7 - py;
			int ci = r8(bgvram, charbase + (ent & 1023) * 64 + py * 8 + px);
			if (ci == 0) return p;
			if ((dispcnt & 0x40000000) != 0) p.col = r16(bgext, bg * 0x2000 + ((ent >> 12) & 15) * 512 + ci * 2);
			else p.col = r16(pal, ci * 2);
		}
		p.ok = true;
		return p;
	}
	// bitmaps: size 0..3 = 128x128, 256x256, 512x256, 512x512
	int bw = size == 0 ? 128 : (size == 1 ? 256 : 512);
	int bh = size == 0 ? 128 : (size == 3 ? 512 : 256);
	if (wrap) { tx &= bw - 1; ty &= bh - 1; } else if (tx < 0 || ty < 0 || tx >= bw || ty >= bh) return p;
	int base = ((cnt >> 8) & 31) * 0x4000;
	if ((cnt & 4) != 0) {   // direct colour
		int c = r16(bgvram, base + (ty * bw + tx) * 2);
		if ((c & 0x8000) == 0) return p;
		p.col = c & 0x7FFF;
	} else {
		int ci = r8(bgvram, base + ty * bw + tx);
		if (ci == 0) return p;
		p.col = r16(pal, ci * 2);
	}
	p.ok = true;
	return p;
}

// ---------------------------------------------------------------- OBJ
// out: col, prio, semi (semi-transparent), win (part of OBJ window)
struct Obj { int col; int prio; bool ok; bool semi; bool win; };

Obj sprites(int x, int y, int dispcnt) {
	Obj r; r.ok = false; r.win = false; r.semi = false; r.col = 0; r.prio = 4;
	for (int i = 0; i < 128; i++) {
		int a0 = r16(oam, i * 8), a1 = r16(oam, i * 8 + 2), a2 = r16(oam, i * 8 + 4);
		bool affine = (a0 & 0x100) != 0;
		if (!affine && (a0 & 0x200) != 0) continue;   // disabled
		int mode = (a0 >> 10) & 3;
		int shape = (a0 >> 14) & 3, sz = (a1 >> 14) & 3;
		int w = 8, h = 8;
		if (shape == 0) { w = 8 << sz; h = w; }
		else if (shape == 1) { w = sz == 0 ? 16 : (sz == 1 ? 32 : (sz == 2 ? 32 : 64)); h = sz == 0 ? 8 : (sz == 1 ? 8 : (sz == 2 ? 16 : 32)); }
		else if (shape == 2) { h = sz == 0 ? 16 : (sz == 1 ? 32 : (sz == 2 ? 32 : 64)); w = sz == 0 ? 8 : (sz == 1 ? 8 : (sz == 2 ? 16 : 32)); }
		else continue;
		bool dbl = affine && (a0 & 0x200) != 0;
		int bw = dbl ? w * 2 : w, bh = dbl ? h * 2 : h;
		int oy = a0 & 255; int ox = a1 & 511;
		if (interp < 1.0) {
			int b0 = r16(oam_prev, i * 8), b1 = r16(oam_prev, i * 8 + 2), b2 = r16(oam_prev, i * 8 + 4);
			if ((b0 & 0xFF00) == (a0 & 0xFF00) && (b1 & 0xFE00) == (a1 & 0xFE00) && b2 == a2) {
				oy = lerp_pos(oy, b0 & 255, 255);
				ox = lerp_pos(ox, b1 & 511, 511);
			}
		}
		if (ox >= 256) ox -= 512;
		int ly = (y - oy) & 255;
		if (ly >= bh) continue;
		int lx = x - ox;
		if (lx < 0 || lx >= bw) continue;
		int tx, ty;
		if (affine) {
			int g = (a1 >> 9) & 31;
			int pa = sx(r16(oam, g * 32 + 6), 16), pb = sx(r16(oam, g * 32 + 14), 16);
			int pc = sx(r16(oam, g * 32 + 22), 16), pd = sx(r16(oam, g * 32 + 30), 16);
			int cx = lx - bw / 2, cy = ly - bh / 2;
			tx = ((pa * cx + pb * cy) >> 8) + w / 2;
			ty = ((pc * cx + pd * cy) >> 8) + h / 2;
			if (tx < 0 || ty < 0 || tx >= w || ty >= h) continue;
		} else {
			tx = (a1 & 0x1000) != 0 ? w - 1 - lx : lx;
			ty = (a1 & 0x2000) != 0 ? h - 1 - ly : ly;
		}
		int tile = a2 & 1023;
		int col = -1;
		if (mode == 3) {   // bitmap OBJ
			int addr;
			if ((dispcnt & 0x40) != 0) addr = tile * (((dispcnt >> 22) & 1) != 0 ? 256 : 128) + (ty * w + tx) * 2;
			else {   // 2D: a 128- or 256-dot wide bitmap of 16-bit pixels
				int m = ((dispcnt >> 5) & 1) != 0 ? 0x1F : 0x0F;
				int stride = (m + 1) * 16;
				addr = (tile & m) * 0x10 + (tile & ~m) * 0x80 + ty * stride + tx * 2;
			}
			int c = r16(objvram, addr);
			if ((c & 0x8000) == 0) continue;
			col = c & 0x7FFF;
		} else {
			bool c256 = (a0 & 0x2000) != 0;
			int bpt = c256 ? 64 : 32;
			int toff;
			if ((dispcnt & 0x10) != 0) {   // 1D mapping
				int bound = 32 << ((dispcnt >> 20) & 3);
				toff = tile * bound + ((ty >> 3) * (w >> 3) + (tx >> 3)) * bpt;
			} else {
				toff = tile * 32 + (ty >> 3) * 1024 + (tx >> 3) * bpt;   // 2D: 32x32-tile sheet
			}
			int ci;
			if (c256) ci = r8(objvram, toff + (ty & 7) * 8 + (tx & 7));
			else { int b = r8(objvram, toff + (ty & 7) * 4 + ((tx & 7) >> 1)); ci = (tx & 1) != 0 ? b >> 4 : b & 15; }
			if (ci == 0) continue;
			if (c256) {
				if ((dispcnt & 0x80000000) != 0) col = r16(objext, ((a2 >> 12) & 15) * 512 + ci * 2);
				else col = r16(pal, 512 + ci * 2);
			} else col = r16(pal, 512 + (((a2 >> 12) & 15) * 16 + ci) * 2);
		}
		if (mode == 2) { r.win = true; continue; }
		if (!r.ok) {
			r.ok = true; r.col = col; r.prio = (a2 >> 10) & 3; r.semi = mode == 1;
		}
	}
	return r;
}

vec3 shade(int x, int y FX_ARG) {
	int dispcnt = rg32(y, 0);
	dispcnt &= ~0x1F00 | layer_keep;
	int dmode = (dispcnt >> 16) & 3;
	if (dmode == 0) return vec3(1.0);
	if ((dispcnt & 0x80) != 0) return vec3(1.0);   // forced blank
	int bgmode = dispcnt & 7;
	// window
	int winmask = 0x3F;
	bool anywin = (dispcnt & 0xE000) != 0;
	Obj ob = sprites(x, y, dispcnt);
	if (anywin) {
		winmask = rg8(y, 0x4A);   // outside
		bool done = false;
		for (int w = 0; w < 2; w++) {
			if (done || (dispcnt & (0x2000 << w)) == 0) continue;
			int h = rg16(y, 0x40 + w * 2), v = rg16(y, 0x44 + w * 2);
			int x1 = h >> 8, x2 = h & 255, y1 = v >> 8, y2 = v & 255;
			bool inx = x1 <= x2 ? (x >= x1 && x < x2) : (x >= x1 || x < x2);
			bool iny = y1 <= y2 ? (y >= y1 && y < y2) : (y >= y1 || y < y2);
			if (inx && iny) { winmask = rg8(y, 0x48 + w); done = true; }
		}
		if (!done && (dispcnt & 0x8000) != 0 && ob.win) winmask = rg8(y, 0x4B);
	}
	// collect layers: up to two topmost (for blending). layer ids: 0-3 BG, 4 OBJ, 5 backdrop
	int top_col = r16(pal, 0), top_id = 5, top_prio = 9;
	int sec_col = top_col, sec_id = 5, sec_prio = 9;
	vec3 top_v = c15(top_col), sec_v = top_v;
	bool top_semi = false;
	bool top3d = false; float a3d = 1.0;
	for (int prio = 3; prio >= 0; prio--) {
		for (int bg = 3; bg >= 0; bg--) {
			if ((dispcnt & (0x100 << bg)) == 0 || (winmask & (1 << bg)) == 0) continue;
			int cnt = rg16(y, 8 + bg * 2);
			if ((cnt & 3) != prio) continue;
			Px p; p.ok = false;
			bool is3d = false; vec4 c3 = vec4(0.0);
			if (bg == 0 && engine_a && (dispcnt & 8) != 0) {
				if (has3d) { c3 = texelFetch(layer3d, ivec2(x, y), 0); if (c3.a > 0.0) { p.ok = true; is3d = true; if (premul3d && c3.a < 1.0) c3.rgb = min(c3.rgb / c3.a, vec3(1.0)); } }
			} else if (bg < 2 || bgmode == 0 || (bg == 2 && bgmode == 1) || (bg == 2 && bgmode == 3)) {
#ifdef FX_FUZZY
				if (engine_a && bg >= 2 && ds_fx.y > 0.0) { ivec2 fw = fz_warp(x, y); p = text_bg(fw.y, bg, fw.x, fw.y, dispcnt); } else
#endif
				p = text_bg(y, bg, x, y, dispcnt);
			} else {
				int kind = 1;
				if (bg == 3 && (bgmode == 3 || bgmode == 4 || bgmode == 5)) kind = 2;
				if (bg == 2 && bgmode == 5) kind = 2;
#ifdef FX_FUZZY
				if (engine_a && ds_fx.y > 0.0) { ivec2 fw = fz_warp(x, y); p = affine_bg(fw.y, bg, clamp(fw.x, 0, 255), dispcnt, kind); } else   // the sky's map ends just off screen: never sample past the screen edge
#endif
				p = affine_bg(y, bg, x, dispcnt, kind);
			}
			if (!p.ok) continue;
			sec_col = top_col; sec_id = top_id; sec_v = top_v;
			if (is3d) {
				top_v = floor(c3.rgb * 63.0 + 0.5) / 63.0;
				top3d = true; a3d = c3.a;
			} else { top_col = p.col; top_v = c15(p.col); top3d = false; }
			top_id = bg; top_semi = false;
			FX_SET(1 + (3 - prio) * 5 + (3 - bg) + (is3d ? 32 : 0))
		}
		if (ob.ok && ob.prio == prio && (dispcnt & 0x1000) != 0 && (winmask & 16) != 0) {
			sec_col = top_col; sec_id = top_id; sec_v = top_v;
			top_col = ob.col; top_v = c15(ob.col); top_id = 4; top_semi = ob.semi; top3d = false;
			FX_SET(1 + (3 - prio) * 5 + 4)
		}
	}
	// blending and brightness in the 6-bit integer domain (melonDS GPU2D: ColorBlend4/5,
	// ColorBrightnessUp/Down; the down step is checked against melonDS captures of the intro fades)
	vec3 c = floor(top_v * 63.0 + 0.5);
	vec3 c2 = floor(sec_v * 63.0 + 0.5);
	int bldcnt = rg16(y, 0x50);
	int bmode = (bldcnt >> 6) & 3;
	bool fx = (winmask & 32) != 0;
	bool second = (bldcnt & (0x100 << sec_id)) != 0;
	if (fx && (top_semi || top3d) && second) {
		if (top3d) {
			float a5 = floor(a3d * 31.0 + 0.5);
			c = floor((c * (a5 + 1.0) + c2 * (31.0 - a5) + 16.0) / 32.0);
		} else { int ba = rg16(y, 0x52); float eva = min(16.0, float(ba & 31)), evb = min(16.0, float((ba >> 8) & 31));
			c = min(floor((c * eva + c2 * evb + 8.0) / 16.0), vec3(63.0)); }
	} else if (fx && (bldcnt & (1 << top_id)) != 0 && bmode != 0) {
		int ba = rg16(y, 0x52);
		if (bmode == 1 && second) {
			float eva = min(16.0, float(ba & 31)), evb = min(16.0, float((ba >> 8) & 31));
			c = min(floor((c * eva + c2 * evb + 8.0) / 16.0), vec3(63.0));
		} else if (bmode == 2 || bmode == 3) {
#ifdef FX_BEVEL
			FX_SET(fx_code | 64)   // brightness fade: applied by the bevel pass after the bevel (part 22)
#else
			float ey = min(16.0, float(rg8(y, 0x54) & 31));
			if (bmode == 2) c = c + floor((63.0 - c) * ey / 16.0);
			else c = c - ceil(c * ey / 16.0);
#endif
		}
	}
// master brightness (with FX_BEVEL the bevel pass applies it after the bevel, part 22)
#ifndef FX_BEVEL
	int mb = rg16(y, 0x6C);
	int mm = (mb >> 14) & 3;
	float f = min(16.0, float(mb & 31));
	if (mm == 1) c = c + floor((63.0 - c) * f / 16.0);
	else if (mm == 2) c = c - ceil(c * f / 16.0);
#endif
	return c / 63.0;
}

void fragment() {
	int x = clamp(int(UV.x * 256.0), 0, 255);
	int y = clamp(int(UV.y * 192.0), 0, 191);
#ifdef FX_SHAKE
	x = clamp(x - fx_shake.x, 0, 255);
	y = clamp(y - fx_shake.y, 0, 191);
#endif
	// the LCD gets 6 bits per channel (2D colours are 5-bit << 1); expand like the panel/melonDS: c6 << 2 | c6 >> 4
#ifdef FX_BEVEL
	int fx_code = 0;
#endif
	vec3 c6 = floor(shade(x, y FX_PASS) * 63.0 + 0.5);
#ifdef FX_FUZZY
	if (engine_a) c6 = fz_tint(c6, x, y);
#endif
	COLOR = vec4((c6 * 4.0 + floor(c6 / 16.0)) / 255.0, 1.0);
#ifdef FX_BEVEL
	COLOR.a = float(fx_code) / 255.0;
#endif
}
