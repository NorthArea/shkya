shader_type spatial;
// Натоптанная тропинка (ART-05, черта 12) с мягкими рваными краями (POLISH-02, п. 19): раньше — коробка снега
// с резкими краями, у киоска под тёплым светом читалась светлой заплаткой. Плоскость PlaneMesh, UV 0..1 по ширине
// и длине; цвет — как затоптанный снег snow.gdshader, но матовый, к краям уходит в прозрачность.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 clean : source_color = vec3(0.84, 0.87, 0.92);
uniform vec3 dirty : source_color = vec3(0.42, 0.42, 0.44);
uniform float scale = 0.35;
uniform float width = 1.5;      // м: поперёк тропы — для кромки в метрах
uniform float length_m = 10.0;  // м: вдоль тропы
uniform float opacity = 0.85;
// CITY-02 L: следы с глубиной — вдоль тропы идут цепочки отпечатков (несколько прохожих, шаг ~0,7 м, левый/правый),
// старые оплывшие и мельче. Нормаль — разностями высоты в осях тропы, оси в мире — из производных UV (тропа может
// лежать под любым углом). Значения задаёт lighting.gd (PRINT_*); по умолчанию — те же числа.
uniform float print_depth = 0.035;        // м, глубина свежего отпечатка
uniform float print_step = 0.72;          // м, шаг
uniform vec2 print_size = vec2(0.055, 0.14);   // м, полуоси отпечатка (поперёк, вдоль)
uniform float print_walkers = 3.0;        // цепочек на тропе

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

// Глубина отпечатков (м, ≥ 0) в точке тропы: across — от оси, along — от начала, в метрах.
float print_height(float across, float along) {
	float depth = 0.0;
	for (int k = 0; k < 4; k++) {
		if (float(k) >= print_walkers) {
			break;
		}
		float lane = (float(k) - (print_walkers - 1.0) * 0.5) * width * 0.22 + (hash(vec2(float(k), 3.0)) - 0.5) * 0.15;
		float phase = hash(vec2(float(k), 7.0)) * print_step * 2.0;
		float sway = (noise(vec2(along * 0.4, float(k) * 5.0)) - 0.5) * 0.25;
		// Ближайшие два шага цепочки: левый и правый поочерёдно.
		float i0 = floor((along - phase) / print_step);
		for (int j = 0; j < 2; j++) {
			float i = i0 + float(j);
			float side = mod(i, 2.0) < 0.5 ? -1.0 : 1.0;
			vec2 c = vec2(lane + sway + side * 0.11, phase + i * print_step);
			vec2 jitter = (vec2(hash(vec2(i, float(k) + 1.0)), hash(vec2(float(k) + 2.0, i))) - 0.5) * vec2(0.05, 0.08);
			vec2 d = (vec2(across, along) - c - jitter) / print_size;
			float r = length(d);
			float age = mix(0.35, 1.0, hash(vec2(i + 0.5, float(k) * 3.0)));   // старые оплыли
			// Каблук глубже носка; край отпечатка — мягкий валик.
			float shape = (1.0 - smoothstep(0.55, 1.0, r)) * mix(0.75, 1.0, smoothstep(-1.0, 1.0, -d.y));
			depth = max(depth, shape * age);
		}
	}
	return depth * print_depth;
}

void fragment() {
	vec2 p = world_pos.xz * scale;
	float n = noise(p) * 0.6 + noise(p * 3.1) * 0.3 + noise(p * 9.0) * 0.1;
	float dirt = smoothstep(0.2, 0.85, n);
	ALBEDO = mix(clean, dirty * vec3(1.0, 0.97, 0.92), clamp(dirt + 0.55, 0.0, 1.0));
	// CITY-02 F: середина тропы утоптана плотнее и темнее, у кромки — рыхлый снег (тропа читается издалека).
	float mid = 1.0 - smoothstep(0.0, 0.4, abs(UV.x - 0.5) * 2.0 * 0.8);
	float rim = smoothstep(0.26, 0.4, abs(UV.x - 0.5)) * (1.0 - smoothstep(0.42, 0.5, abs(UV.x - 0.5)));
	ALBEDO *= (1.0 - 0.22 * mid) * (1.0 - 0.3 * rim) * 0.85;   // тень бортика рыхлого снега у кромки
	ROUGHNESS = 0.85;
	// Расстояние до края в метрах: поперёк — до боковой кромки, вдоль — до торца; кромка рваная по шуму.
	float side = (0.5 - abs(UV.x - 0.5)) * width;
	float end = (0.5 - abs(UV.y - 0.5)) * length_m;
	float d = min(side, end) + (noise(world_pos.xz * 2.7) - 0.5) * 0.35;
	ALPHA = opacity * smoothstep(0.0, 0.45, d);
	// Отпечатки: оси тропы в мире по производным UV, нормаль — разностями глубины (шаг 2 см).
	vec3 dp1 = dFdx(world_pos);
	vec3 dp2 = dFdy(world_pos);
	vec2 duv1 = dFdx(UV);
	vec2 duv2 = dFdy(UV);
	vec3 n0 = normalize(world_normal);
	vec3 dp2perp = cross(dp2, n0);
	vec3 dp1perp = cross(n0, dp1);
	vec3 axis_u = normalize(dp2perp * duv1.x + dp1perp * duv2.x + vec3(1e-6));
	vec3 axis_v = normalize(dp2perp * duv1.y + dp1perp * duv2.y + vec3(1e-6));
	float across = (UV.x - 0.5) * width;
	float along = UV.y * length_m;
	float e = 0.02;
	float h0 = -print_height(across, along);
	float hu = -print_height(across + e, along);
	float hv = -print_height(across, along + e);
	vec3 nrm = normalize(n0 - axis_u * (hu - h0) / e - axis_v * (hv - h0) / e);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	// Дно отпечатка темнее и плотнее (утрамбовано), без новых цветов.
	ALBEDO *= mix(1.0, 0.86, clamp(-h0 / print_depth, 0.0, 1.0));
}
