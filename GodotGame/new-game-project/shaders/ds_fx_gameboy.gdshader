shader_type canvas_item;
// QoL WEIRD SETTING "GAME BOY" (part 22, picture only): the whole 256x384 picture (both screens, the game's menus and
// the port's own overlays: this rect is on a CanvasLayer above everything) re-coloured with the original Game Boy's
// four shades of green, by luminance, with a light 4x4 ordered dither near the steps (one DS pixel per dither cell);
// edges whose contrast the 4 shades would lose get one shade apart (keeps red-on-olive menu text readable).
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float dither = 0.35;   // dither amplitude, in steps (0 = hard bands)

const vec3 GB0 = vec3(15.0, 56.0, 15.0) / 255.0;     // #0f380f darkest
const vec3 GB1 = vec3(48.0, 98.0, 48.0) / 255.0;     // #306230
const vec3 GB2 = vec3(139.0, 172.0, 15.0) / 255.0;   // #8bac0f
const vec3 GB3 = vec3(155.0, 188.0, 15.0) / 255.0;   // #9bbc0f lightest

const int BAYER[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
float bayer4(ivec2 p) { return (float(BAYER[(p.y & 3) * 4 + (p.x & 3)]) + 0.5) / 16.0 - 0.5; }

float lum(vec3 c) { return clamp((dot(c, vec3(0.299, 0.587, 0.114)) - 0.04) / 0.92, 0.0, 1.0); }   // full range
float shade(float l, float b) { return clamp(floor(l * 4.0 + b * dither), 0.0, 3.0); }

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = lum(c);
	float b = bayer4(ivec2(floor(UV * vec2(256.0, 384.0))));
	float k = shade(l, b);
	// contrast the 4 shades lost: a neighbour of a clearly different colour but the same shade (red text on an olive
	// chip, a red gi on a green field) - the darker of the two drops one shade (at the darkest, the lighter one rises)
	bool drop = false, rise = false;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) continue;
			vec3 q = texture(screen_tex, SCREEN_UV + vec2(float(dx), float(dy)) * SCREEN_PIXEL_SIZE).rgb;
			if (distance(c, q) <= 0.42) continue;
			float lq = lum(q);
			if (shade(lq, b) != k) continue;
			if (l < lq) drop = drop || k > 0.5; else rise = rise || k < 0.5;
		}
	}
	k = drop ? k - 1.0 : (rise ? k + 1.0 : k);
	vec3 o = k < 0.5 ? GB0 : (k < 1.5 ? GB1 : (k < 2.5 ? GB2 : GB3));
	COLOR = vec4(o, 1.0);
}
