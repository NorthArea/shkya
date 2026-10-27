shader_type spatial;
// Краска «Лады» (ART-03): грязно-белый кузов, ржавые потёки и грязь снизу, слабый блеск мокрой краски.
// Координаты — VERTEX меша (бокс с центром в своём начале): y — высота внутри бокса, z — вдоль кузова.

uniform vec3 paint : source_color = vec3(0.86, 0.85, 0.80);
uniform vec3 rust : source_color = vec3(0.42, 0.24, 0.12);
uniform vec3 dirt : source_color = vec3(0.30, 0.28, 0.25);
uniform float rust_amount = 0.55;
uniform float dirt_amount = 1.0;
uniform float half_height = 0.31;

varying vec3 local_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 p = local_pos;
	float along = p.z + p.x * 0.7;
	float h = clamp(p.y / half_height * 0.5 + 0.5, 0.0, 1.0);  // 0 — низ бокса, 1 — верх
	// Потёки: вертикальные полосы шума, гуще к низу.
	float streak = noise(vec2(along * 9.0, p.y * 1.5)) * noise(vec2(along * 3.0, 1.0));
	float r = smoothstep(0.25, 0.6, streak + (1.0 - h) * 0.4) * rust_amount;
	float d = (1.0 - smoothstep(0.0, 0.45, h)) * (0.55 + 0.45 * noise(vec2(along * 4.0, p.y * 6.0))) * dirt_amount;
	vec3 col = mix(paint, rust, r);
	col = mix(col, dirt, d * 0.75);
	col *= 0.92 + 0.08 * noise(vec2(along * 20.0, p.y * 20.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.35, 0.85, max(r, d));
	SPECULAR = 0.5;
}
