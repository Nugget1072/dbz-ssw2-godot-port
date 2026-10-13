shader_type canvas_item;
// QoL WEIRD STUFF 3 "CRT TV" (part 25, picture only): the whole 256x384 picture (both screens, every overlay; after
// GAME BOY) looks like an old TV, each DS screen its own little tube: soft scanlines (one per DS pixel row), a little
// glow around bright parts, a gentle vignette, dark rounded corners and, at 3x and more, a very faint RGB stripe mask.
// Two uses (scripts/qol/qol_crt.gd): DSPresenter draws the SubViewport with it at the window's resolution (`scale` =
// window pixels per DS pixel, sharp-bilinear sampling as the presenter's own shader), so the scanlines are always
// exactly one per DS row at any size; without the presenter (frame-exact captures, `snap=`, `present=0`) a rect on a
// CanvasLayer above GAME BOY runs the CRT_SCREEN variant on the 256x384 screen texture at scale 1, where a row is one
// pixel: no scanlines, only the glow, vignette and corners. `sharp0` / `sharp1` (DS px rects, x y w h; w 0 = none):
// left untouched (only the corners), so the port's settings menu stays sharp.
#ifdef CRT_SCREEN
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
#endif
uniform vec2 src = vec2(256.0, 384.0);
uniform float scale = 1.0;
uniform vec4 sharp0 = vec4(0.0);
uniform vec4 sharp1 = vec4(0.0);
uniform float scan = 0.42;        // darkening of the gap between rows (0..1)
uniform float gap = 0.42;         // the gap: the lower part of each DS row (fraction)
uniform float glow = 0.24;        // glow amount
uniform float vignette = 0.22;
uniform float corner = 9.0;       // corner radius (DS px)
uniform float mask = 0.07;        // RGB stripe mask strength (only at scale >= 3)

#ifdef CRT_SCREEN
#define TX screen_tex
#else
#define TX TEXTURE
#endif

vec3 pic(sampler2D tx, vec2 t) {   // filtered colour at t (DS px; between texel centres = the 2x2 average)
	return texture(tx, t / src).rgb;
}

// accumulated "gap" length from row 0 to y (DS rows): each row's [1 - gap, 1) part is gap
float gap_acc(float y) {
	return floor(y) * gap + max(fract(y) - (1.0 - gap), 0.0);
}

bool inside(vec2 p, vec4 r) {
	return r.z > 0.0 && p.x >= r.x && p.y >= r.y && p.x < r.x + r.z && p.y < r.y + r.w;
}

void fragment() {
	vec2 t = UV * src;                                   // DS px
	// the picture: sharp bilinear (the presenter's own sampling: nearest at whole multiples)
	vec2 c = fract(t) - 0.5;
	float r = max(0.5 - 0.5 / scale, 0.0);
	vec2 g = (c - clamp(c, -r, r)) * scale + 0.5;
#ifdef CRT_SCREEN
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
#else
	vec3 col = texture(TEXTURE, (floor(t) + g) / src).rgb;
#endif
	// each screen is its own tube: position inside it
	float sy = t.y >= 192.0 ? 192.0 : 0.0;
	vec2 s = vec2(t.x, t.y - sy);                        // 0..256, 0..192
	bool keep = inside(t, sharp0) || inside(t, sharp1);
	if (!keep) {
		// glow: the bright parts of a ~5x5 DS px neighbourhood (8 bilinear taps of 2x2 texels each, the same at
		// every scale, kept inside this screen), added on top
		vec2 tc = floor(t) + 0.5;
		vec2 lo = vec2(1.0, sy + 1.0), hi = vec2(255.0, sy + 191.0);
		vec3 b = vec3(0.0);
		b += max(pic(TX, clamp(tc + vec2(-1.5, -0.5), lo, hi)) - 0.5, 0.0);
		b += max(pic(TX, clamp(tc + vec2(0.5, -1.5), lo, hi)) - 0.5, 0.0);
		b += max(pic(TX, clamp(tc + vec2(1.5, 0.5), lo, hi)) - 0.5, 0.0);
		b += max(pic(TX, clamp(tc + vec2(-0.5, 1.5), lo, hi)) - 0.5, 0.0);
		vec3 b2 = vec3(0.0);
		b2 += max(pic(TX, clamp(tc + vec2(-2.5, -1.5), lo, hi)) - 0.5, 0.0);
		b2 += max(pic(TX, clamp(tc + vec2(1.5, -2.5), lo, hi)) - 0.5, 0.0);
		b2 += max(pic(TX, clamp(tc + vec2(2.5, 1.5), lo, hi)) - 0.5, 0.0);
		b2 += max(pic(TX, clamp(tc + vec2(-1.5, 2.5), lo, hi)) - 0.5, 0.0);
		col += (b * 0.25 * 0.65 + b2 * 0.25 * 0.35) * glow * 2.2;
		// scanlines: the fraction of this window pixel that lies in a row's gap (exact box filter, any scale);
		// bright pixels darken less (a brighter beam is wider). Faded out below 1.5x, where a row is ~1 pixel.
		float h = 0.5 / scale;
		float d = (gap_acc(t.y + h) - gap_acc(t.y - h)) / (2.0 * h);
		float k = scan * smoothstep(1.2, 1.9, scale);
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col *= (1.0 - k * d * (1.0 - 0.55 * clamp(l, 0.0, 1.0))) * (1.0 + k * gap * 0.55);
		// a very faint RGB stripe mask (window pixel columns), only when a DS pixel is 3+ window pixels wide
		if (scale >= 2.95) {
			int m = int(mod(FRAGCOORD.x, 3.0));
			vec3 mk = m == 0 ? vec3(1.0 + mask, 1.0 - mask, 1.0 - mask) : (m == 1 ? vec3(1.0 - mask, 1.0 + mask, 1.0 - mask) : vec3(1.0 - mask, 1.0 - mask, 1.0 + mask));
			col *= mk;
		}
		// vignette: darker toward the tube's edges
		vec2 v = (s - vec2(128.0, 96.0)) / vec2(128.0, 96.0);
		col *= 1.0 - vignette * pow(dot(v * vec2(0.85, 1.0), v * vec2(0.85, 1.0)) * 0.5, 1.5) * 2.0;
	}
	// dark rounded corners (+ a soft dark rim), anti-aliased at the window's resolution
	vec2 e = min(s, vec2(256.0, 192.0) - s);             // distance to the nearest edges
	vec2 q = max(vec2(corner) - e, 0.0);
	float dist = corner - length(q);                     // > 0 inside the rounded rect
	float aa = 0.5 / scale + 0.15;
	float inside_c = smoothstep(-aa, aa, dist);
	float rim = keep ? 1.0 : mix(0.72, 1.0, smoothstep(0.0, 2.5, dist));
	col *= inside_c * rim;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
