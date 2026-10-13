shader_type canvas_item;
// One DS 2D background layer rendered over a 256x192 rect, using the hardware's affine mapping:
//   tex = (ref + P * screen) / 256   with P = [[pa, pb], [pc, pd]] (8.8 fixed), ref in 1/256 px.
// Text-mode scrolling layers use pa = pd = 256, pb = pc = 0, ref = scroll * 256.
uniform sampler2D layer : filter_nearest, repeat_enable;
uniform vec2 layer_size = vec2(256.0, 256.0);
uniform vec2 ref = vec2(0.0);
uniform vec4 abcd = vec4(256.0, 0.0, 0.0, 256.0);
uniform bool wrap = true;

void fragment() {
	vec2 s = floor(UV * vec2(256.0, 192.0));
	vec2 t = floor((ref + vec2(abcd.x * s.x + abcd.y * s.y, abcd.z * s.x + abcd.w * s.y)) / 256.0);
	if (!wrap && (t.x < 0.0 || t.y < 0.0 || t.x >= layer_size.x || t.y >= layer_size.y)) {
		discard;
	}
	t = mod(t, layer_size);
	vec4 c = texelFetch(layer, ivec2(t), 0);
	if (c.a < 0.5) {
		discard;
	}
	COLOR = c;
}
