shader_type canvas_item;
render_mode blend_disabled;
// QoL WEIRD SETTING "BEVEL EMBOSS" (part 21, picture only): Photoshop-style inner bevel & emboss on everything the
// two DS screens draw. Input: the two engines rendered into a 256x384 picture whose alpha holds the code of the top
// layer at each pixel (ds_engine2d with FX_BEVEL: rank by priority / layer order, +32 = 3D layer, 0 = backdrop), and
// for the 3D layer an object-id render (ds_poly with FX_ID: depth rank + texture hash per polygon).
// Every shape (a sprite, the visible part of a BG layer, each 3D object / texture) is lit as if raised: within
// BEVEL px of the shape's outline (where a layer BEHIND it shows), a highlight on the side facing the light (top
// left) and a shadow on the far side, fading inward. A neighbour in FRONT is not an outline (the shape continues
// under it), so only the front shape is bevelled. Thin strokes (outside on both sides) stay flat, which keeps small
// text legible. A light luminance emboss adds relief inside large flat layers (backgrounds).

uniform sampler2D src : filter_nearest;    // 256x384: rgb = picture, a = top layer code
uniform sampler2D ids : filter_nearest;    // 256x192: 3D object ids (6-bit r = rank, g/b = hash), a = 0 none
uniform bool has_ids = false;
uniform int a_y0 = 0;                     // where engine A (the 3D layer) is: 0 top screen, 192 bottom
uniform sampler2D regs_top : filter_nearest;   // per-line 2D registers of the engine on each screen (fades)
uniform sampler2D regs_bot : filter_nearest;
uniform bool a_flip = false;
uniform ivec2 a_shift = ivec2(0);        // SCREEN SHAKE: engine A's picture is moved by this (engine pixels)              // MIRROR MODE: engine A's screen is drawn flipped left-right
uniform float highlight = 0.75;           // screen-white strength at the outline
uniform float shadow = 0.62;              // multiply-black strength at the outline
uniform float relief = 0.22;              // luminance emboss
const int BEVEL = 3;                      // bevel width (DS px)

int r6(float v) { return int(floor(v * 63.0 + 0.5)); }

// the shape at a pixel: x = layer code, y = 3D object hash (+1; 0 = no 3D object) - which shape it is; z = depth order
// (layer rank * 128 + 3D depth rank) - which of two shapes is in front. The 3D depth rank of the stage varies per
// pixel (distance), so it only orders shapes, never separates them.
ivec3 shape_key(int x, int y) {
	int code = int(texelFetch(src, ivec2(x, y), 0).a * 255.0 + 0.5) & 63;
	int order = (code & 31) * 128;
	int h = 0;
	if ((code & 32) != 0 && has_ids) {
		vec4 d = texelFetch(ids, ivec2(clamp((a_flip ? 255 - x : x) - a_shift.x, 0, 255), clamp(y - a_y0 - a_shift.y, 0, 191)), 0);
		if (d.a > 0.5) { order += 1 + r6(d.r); h = 1 + r6(d.g) * 64 + r6(d.b); }
	}
	return ivec3(code, h, order);
}

int rg8(bool top, int line, int o) {
	return int((top ? texelFetch(regs_top, ivec2(o, line), 0).r : texelFetch(regs_bot, ivec2(o, line), 0).r) * 255.0 + 0.5);
}

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	int x = clamp(int(UV.x * 256.0), 0, 255);
	int y = clamp(int(UV.y * 384.0), 0, 383);
	int y0 = y < 192 ? 0 : 192;                 // the two screens are separate pictures
	vec3 c = texelFetch(src, ivec2(x, y), 0).rgb;
	ivec3 kp = shape_key(x, y);
	vec2 v = vec2(0.0);
	float dmin = 99.0;
	for (int dy = -BEVEL; dy <= BEVEL; dy++) {
		for (int dx = -BEVEL; dx <= BEVEL; dx++) {
			if (dx == 0 && dy == 0) continue;
			float d = length(vec2(float(dx), float(dy)));
			if (d > float(BEVEL) + 0.5) continue;
			int qx = x + dx, qy = y + dy;
			if (qx < 0 || qx > 255 || qy < y0 || qy >= y0 + 192) continue;   // screen edges: no outline
			ivec3 kq = shape_key(qx, qy);
			if (kq.xy != kp.xy && kq.z <= kp.z) {   // another shape, behind (or level: both get the outline)
				dmin = min(dmin, d);
				v += vec2(float(dx), float(dy)) / (d * d * d);
			}
		}
	}
	float sh = 0.0;
	if (dmin < 90.0 && length(v) > 0.05) {
		float prof = clamp(1.0 - (dmin - 1.0) / float(BEVEL), 0.0, 1.0);
		prof = prof * prof * (3.0 - 2.0 * prof);
		// v points out of the shape; light from the top left (Photoshop's default angle, ~120 deg): the rim facing it is lit
		sh = clamp(dot(normalize(v), normalize(vec2(-0.6, -0.8))) * 1.25, -1.0, 1.0) * prof;
	}
	// relief: luminance as a height field, lit from the top left
	int xa = max(x - 1, 0), ya = max(y - 1, y0), xb = min(x + 1, 255), yb = min(y + 1, y0 + 191);
	float e = lum(texelFetch(src, ivec2(xb, yb), 0).rgb) - lum(texelFetch(src, ivec2(xa, ya), 0).rgb);
	sh = clamp(sh + e * relief * 2.0, -1.0, 1.0);
	if (sh > 0.0) c = c + (1.0 - c) * highlight * sh;
	else c = c * (1.0 + shadow * sh);
	// fades last, so the bevel fades with the picture (part 22): the engines leave out the brightness effects when
	// FX_BEVEL is on - BLDY (BLDCNT mode 2 / 3 on the top layer; the engine marks those pixels with alpha bit 6) and
	// MASTER_BRIGHT (0x6C) - and they are applied here, per line, to the bevelled colour
	bool top = y < 192;
	int line = y - y0;
	if ((int(texelFetch(src, ivec2(x, y), 0).a * 255.0 + 0.5) & 64) != 0) {
		int bmode = (rg8(top, line, 0x50) >> 6) & 3;
		float ey = min(16.0, float(rg8(top, line, 0x54) & 31)) / 16.0;
		c = bmode == 2 ? c + (1.0 - c) * ey : c - c * ey;
	}
	int mb = rg8(top, line, 0x6C) | (rg8(top, line, 0x6D) << 8);
	int mm = (mb >> 14) & 3;
	float f = min(16.0, float(mb & 31)) / 16.0;
	if (mm == 1) c = c + (1.0 - c) * f;
	else if (mm == 2) c = c - c * f;
	COLOR = vec4(c, 1.0);
}
