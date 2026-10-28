shader_type spatial;
// Мокрый асфальт со снежной кашей (ART-02): чёрные блестящие колеи по полосам, серая каша между ними и у обочин.

uniform float along_x = 1.0;     // 1 — дорога идёт вдоль x, 0 — вдоль z
uniform vec2 center = vec2(0.0);
uniform float width = 14.0;
uniform vec3 asphalt : source_color = vec3(0.045, 0.047, 0.055);
uniform vec3 slush : source_color = vec3(0.58, 0.56, 0.51);   // бежево-серая каша (сверка ART-04: #a7a18e)

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = along_x > 0.5 ? world_pos.z - center.y : world_pos.x - center.x;
	float along = along_x > 0.5 ? world_pos.x : world_pos.z;
	float half_w = width * 0.5;
	// Колеи: по две на каждую полосу, слегка виляют. Между ними — серая каша, чтобы пары следов
	// читались издалека (ревью ART-02: раньше колеи сливались в тёмные пятна).
	float lane = abs(across) - half_w * 0.5;
	float wobble = noise(vec2(along * 0.15, across * 0.5));
	// Колеи виляют и меняют ширину, край размыт: не «дорожная разметка» (повторная сверка ART-05, Н5).
	float sway = (noise(vec2(along * 0.08, sign(across) * 3.0)) - 0.5) * 0.7 + (noise(vec2(along * 0.5, across)) - 0.5) * 0.15;
	float rut_w = 0.22 + 0.14 * noise(vec2(along * 0.3, across * 0.8 + 11.0));
	float track = 1.0 - smoothstep(rut_w * 0.4, rut_w * 1.6, abs(abs(lane + sway) - 0.8));
	track *= mix(0.6, 1.0, noise(vec2(along * 0.4, across * 2.0)));   // пятна длиннее (И6)
	// Каша: между колеями, по оси и у бордюров.
	float edge = smoothstep(half_w - 2.2, half_w - 0.6, abs(across));
	float mid = 1.0 - smoothstep(0.3, 1.2, abs(across));
	// ART-05 по сверке ART-04 (черта 11): зимой проезд светлый — укатанная каша, тёмные только колеи.
	float between = (1.0 - track) * mix(0.62, 0.92, noise(vec2(along * 0.6, across * 1.7)));
	float slushiness = clamp(max(max(edge, mid * 0.8), between) - track * 0.9, 0.0, 1.0);
	slushiness *= mix(0.75, 1.0, wobble);
	vec3 color = mix(asphalt, slush, slushiness);
	ALBEDO = color;
	ROUGHNESS = mix(0.08, 0.88, slushiness);   // мокрые колеи отражают фонари, каша — матовая
	SPECULAR = mix(0.6, 0.3, slushiness);
}
