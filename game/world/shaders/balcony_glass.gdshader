shader_type spatial;
// Остекление лоджий и окна лестничных клеток (ART-05). Цвет — из экземпляра MultiMesh;
// альфа экземпляра 1 — за стеклом горит свет, 0 — тёмное стекло.

varying vec4 tint;

void vertex() {
	tint = vec4(pow(COLOR.rgb, vec3(2.2)), COLOR.a);   // цвет экземпляра задан в sRGB (повторная сверка ART-05, Н8)
}

void fragment() {
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * tint.a * 1.1;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
