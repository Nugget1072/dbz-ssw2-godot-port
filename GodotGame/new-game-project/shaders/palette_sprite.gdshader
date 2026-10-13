shader_type canvas_item;
// DS 4bpp/8bpp texture with a separate palette: the atlas stores the palette index (0..255) in R,
// the palette texture holds one 16-colour sub-palette per row. Index 0 = transparent (DS texparam bit 29).
uniform sampler2D palette : filter_nearest;
uniform int pal_row = 0;
uniform vec4 modulate_color : source_color = vec4(1.0);

void fragment() {
	int idx = int(texture(TEXTURE, UV).r * 255.0 + 0.5);
	if (idx == 0) {
		discard;
	}
	COLOR = texelFetch(palette, ivec2(idx & 15, pal_row + (idx >> 4)), 0) * modulate_color;
}
