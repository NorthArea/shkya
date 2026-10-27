shader_type spatial;
// Снег (ART-02): рыхлый белый с грязными пятнами; trodden > 0 — затоптанный серый (тротуары, двор).

uniform vec3 clean : source_color = vec3(0.84, 0.87, 0.92);
uniform vec3 dirty : source_color = vec3(0.42, 0.42, 0.44);
uniform float trodden = 0.0;
uniform float scale = 0.35;

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
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
	vec2 p = world_pos.xz * scale + world_pos.y * 0.7;
	float n = noise(p) * 0.6 + noise(p * 3.1) * 0.3 + noise(p * 9.0) * 0.1;
	float dirt = smoothstep(0.55 - trodden * 0.35, 0.85, n);
	ALBEDO = mix(clean, dirty, clamp(dirt + trodden * 0.35, 0.0, 1.0));
	ROUGHNESS = mix(0.85, 0.45, trodden * dirt);
}
