shader_type spatial;
// Снег (ART-02): рыхлый белый с грязными пятнами; trodden > 0 — затоптанный серый (тротуары, двор).
// roadside = 1 — вал у дороги (ART-05 по сверке ART-04, черта 10): серо-бурый, к низу почти чёрный, бурые пятна.

uniform vec3 clean : source_color = vec3(0.84, 0.87, 0.92);
uniform vec3 dirty : source_color = vec3(0.42, 0.42, 0.44);
uniform float trodden = 0.0;
uniform float scale = 0.35;
uniform float roadside = 0.0;
uniform vec3 grime : source_color = vec3(0.07, 0.09, 0.11);
uniform vec3 brown : source_color = vec3(0.36, 0.31, 0.25);

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz * scale + world_pos.y * 0.7;
	float n = noise(p) * 0.6 + noise(p * 3.1) * 0.3 + noise(p * 9.0) * 0.1;
	float dirt = smoothstep(0.55 - trodden * 0.35, 0.85, n);
	vec3 color = mix(clean, dirty, clamp(dirt + trodden * 0.35, 0.0, 1.0));
	if (roadside > 0.5) {
		// Вал — светлый слежавшийся снег (POLISH-02, п. 4: был темнее дороги). Грязь от колёс — только в нижних
		// 20–30 см с рваной кромкой, выше — редкие бурые брызги; сверху светлая шапка (ART-06, С1).
		vec3 packed = mix(clean, dirty, 0.32 + dirt * 0.25);   // проверка POLISH-02 B: вал/дорога ≈1,3, не 1,55
		color = mix(packed, brown * 1.6, smoothstep(0.62, 0.85, noise(p * 2.1 + 4.0)) * 0.35 * (1.0 - smoothstep(0.3, 0.7, world_pos.y)));
		float edge = 0.23 + (noise(p * 4.3 + world_pos.y) - 0.5) * 0.16;   // кромка грязи 0,15–0,31 м
		float low = 1.0 - smoothstep(edge - 0.06, edge + 0.04, world_pos.y);
		color = mix(color, mix(grime, brown, 0.35), low * 0.9);
		float cap = smoothstep(0.45, 0.85, world_normal.y) * smoothstep(0.25, 0.6, world_pos.y);
		color = mix(color, clean * 0.95, cap * 0.55);
	}
	ALBEDO = color;
	ROUGHNESS = mix(0.85, 0.45, trodden * dirt);
}
