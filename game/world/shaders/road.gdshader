shader_type spatial;
// Мокрый асфальт со снежной кашей (ART-02): чёрные блестящие колеи по полосам, серая каша между ними и у обочин.

uniform float along_x = 1.0;     // 1 — дорога идёт вдоль x, 0 — вдоль z
uniform vec2 center = vec2(0.0);
uniform float width = 14.0;
uniform vec3 asphalt : source_color = vec3(0.045, 0.047, 0.055);
uniform vec3 slush : source_color = vec3(0.52, 0.54, 0.58);

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
	// Колеи: по две на каждую полосу.
	float lane = abs(across) - half_w * 0.5;
	float track = 1.0 - smoothstep(0.25, 0.45, abs(abs(lane) - 0.8));
	float wobble = noise(vec2(along * 0.15, across * 0.5));
	// Каша: между колеями, по оси и у бордюров.
	float edge = smoothstep(half_w - 2.2, half_w - 0.6, abs(across));
	float mid = 1.0 - smoothstep(0.3, 1.2, abs(across));
	float slushiness = clamp(max(edge, mid * 0.7) + (1.0 - track) * 0.35 * wobble - track * 0.8, 0.0, 1.0);
	slushiness *= smoothstep(0.25, 0.6, noise(vec2(along * 0.6, across * 1.7)) + edge * 0.5);
	vec3 color = mix(asphalt, slush, slushiness);
	ALBEDO = color;
	ROUGHNESS = mix(0.08, 0.75, slushiness);   // мокрые колеи отражают фонари
	SPECULAR = 0.6;
}
