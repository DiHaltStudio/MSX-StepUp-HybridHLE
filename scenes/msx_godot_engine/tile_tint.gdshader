shader_type canvas_item;

uniform bool purple_enabled = false;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (purple_enabled) {
		// MSX Screen 1 (16x16 grid): tiles 248 and 249
		// Tile 248 -> Col 8, Row 15
		// Tile 249 -> Col 9, Row 15

		float col = floor(UV.x * 16.0);
		float row = floor(UV.y * 16.0);

		if (row == 15.0 && (col == 8.0 || col == 9.0)) {
			// Tinte púrpura optimizado
			tex.rgb *= vec3(1.8, 0.6, 1.8);
		}
	}

	COLOR = tex;
}
