shader_type canvas_item;
// DS text-mode background (engine A/B BG in "text" mode), rendered per pixel from the raw hardware data:
//   tiles   : L8 texture 8 x (n*8), texel = colour index (4bpp: 0..15, 8bpp: 0..255), tile t at rows t*8..t*8+7
//   map     : RGBA8 texture map_w x map_h tiles; entry = R | G<<8 (tile 0-9, hflip 10, vflip 11, palette 12-15)
//   palette : RGBA 16 x N (row = 16-colour palette; 8bpp uses rows 0..15 as one 256-colour palette)
// Colour index 0 is transparent (backdrop), as on hardware.
uniform sampler2D tiles : filter_nearest;
uniform sampler2D map : filter_nearest;
uniform sampler2D palette : filter_nearest;
uniform int bpp = 4;
uniform vec2 scroll = vec2(0.0);
uniform vec2 view_size = vec2(256.0, 192.0);
uniform bool wrap = true;

void fragment() {
	ivec2 msize = textureSize(map, 0);
	vec2 p = floor(UV * view_size) + scroll;
	ivec2 ip = ivec2(p);
	ivec2 mpx = msize * 8;
	if (!wrap && (ip.x < 0 || ip.y < 0 || ip.x >= mpx.x || ip.y >= mpx.y)) {
		discard;
	}
	ip = ((ip % mpx) + mpx) % mpx;
	vec4 me = texelFetch(map, ip / 8, 0);
	int e = int(me.r * 255.0 + 0.5) | (int(me.g * 255.0 + 0.5) << 8);
	int t = e & 1023;
	int lx = ip.x & 7;
	int ly = ip.y & 7;
	if ((e & 1024) != 0) lx = 7 - lx;
	if ((e & 2048) != 0) ly = 7 - ly;
	int idx = int(texelFetch(tiles, ivec2(lx, t * 8 + ly), 0).r * 255.0 + 0.5);
	if (idx == 0) {
		discard;
	}
	vec4 c;
	if (bpp == 4) {
		c = texelFetch(palette, ivec2(idx, e >> 12), 0);
	} else {
		c = texelFetch(palette, ivec2(idx & 15, idx >> 4), 0);
	}
	COLOR = vec4(c.rgb, 1.0);
}
