shader_type spatial;
// Остекление лоджий и окна лестничных клеток (ART-05). Цвет — из экземпляра MultiMesh;
// альфа экземпляра 1 — за стеклом горит свет, 0 — тёмное стекло.

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * tint.a * 1.1;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
