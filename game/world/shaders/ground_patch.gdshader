shader_type spatial;
// CITY-02 E: пятна на тротуарах — наледь, проталины и каша (ART-04, черты 11, 12). Плоскость 1 × 1 в MultiMesh,
// INSTANCE_CUSTOM: r — вид (0 наледь, 1 проталина до асфальта, 2 бурая каша), g — seed кромки.
// Кромка рваная по шуму (discard, без прозрачности и сортировки). Только вид.

uniform vec3 ice_color : source_color = vec3(0.46, 0.52, 0.58);
uniform vec3 asphalt : source_color = vec3(0.20, 0.20, 0.19);   // мокрый асфальт #565650 днём (ART-04, черта 11), ночью темнее
uniform vec3 slush : source_color = vec3(0.50, 0.47, 0.40);     // каша #a7a18e (Тайгинская), приглушена
uniform vec3 snow_edge : source_color = vec3(0.70, 0.72, 0.76);

varying vec2 local;
varying vec2 extent;
varying float kind;
varying float seed;
varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	extent = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	local = VERTEX.xz * 2.0;   // −1…1
	kind = INSTANCE_CUSTOM.r;
	seed = INSTANCE_CUSTOM.g * 97.0;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = local * extent * 0.5;   // метры от центра
	float r = length(local);
	float wobble = noise(q * 1.3 + seed) * 0.45 + noise(q * 4.0 - seed) * 0.2;
	float shape = r + wobble - 0.45;
	if (shape > 0.55) {
		discard;
	}
	float rim = smoothstep(0.3, 0.55, shape);   // светлая кромка снега вокруг пятна
	vec3 c;
	float rough;
	float metal = 0.0;
	if (kind < 0.5) {
		// Наледь: гладкий лёд, сквозь него — тёмный асфальт, белёсые пузыри и царапины.
		float streak = smoothstep(0.7, 0.95, noise(vec2(q.x * 0.6, q.y * 12.0) + seed));
		c = mix(ice_color * 0.55, ice_color, noise(q * 2.0 + seed) * 0.6 + streak * 0.4);
		rough = 0.06 + 0.12 * streak;
		SPECULAR = 0.7;
	} else if (kind < 1.5) {
		// Проталина: мокрый асфальт с лужицами — темнее и глянцевее у середины.
		float puddle = 1.0 - smoothstep(0.1, 0.4, shape + noise(q * 2.5 + seed) * 0.2);
		c = asphalt * (0.8 + 0.3 * noise(q * 6.0 + seed)) * (1.0 - puddle * 0.35);
		rough = mix(0.45, 0.08, puddle);
	} else {
		// Каша: бурый подтаявший снег с песком.
		float grit = noise(q * 9.0 + seed);
		c = slush * (0.75 + 0.35 * grit);
		rough = 0.35;
	}
	c = mix(c, snow_edge, rim * 0.8);
	ALBEDO = c;
	ROUGHNESS = mix(rough, 0.85, rim);
	METALLIC = metal;
}
