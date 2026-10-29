shader_type sky;
// Небо города Н. (CITY-02 L): градиент сумерек ART-05 — тот же, что давал ProceduralSkyMaterial (кривая sky_curve,
// ground_curve), плюс слой облаков и городское зарево у горизонта. Облака — шум fbm на плоскости над городом, снизу
// подсвечены тёплым заревом натрия, сверху — холодные. В проходе кубической карты (AT_CUBEMAP_PASS: из неё берётся
// общий свет сцены) облаков и зарева нет — общий свет остаётся как у прежнего неба, и карта не пересчитывается каждый кадр.
// Движение облаков — медленный поворот неба вокруг зенита (Environment.sky_rotation из lighting.gd), без TIME и без
// смены параметров: шейдер неба с TIME или новым параметром заставляет Godot пересчитывать кубическую карту, а поворот
// симметричного по кругу градиента общий свет не меняет. Все ручки — константы lighting.gd.

uniform vec3 top_color : source_color = vec3(0.08, 0.12, 0.22);
uniform vec3 horizon_color : source_color = vec3(0.36, 0.47, 0.58);
uniform vec3 ground_bottom : source_color = vec3(0.10, 0.11, 0.12);
uniform vec3 ground_horizon : source_color = vec3(0.36, 0.47, 0.58);
uniform float sky_curve = 0.15;          // как ProceduralSkyMaterial
uniform float ground_curve = 0.02;
// Зарево: тёплый натриевый отсвет города на нижнем слое воздуха; glow_height — высота полосы (доля sin угла).
uniform vec3 glow_color : source_color = vec3(0.62, 0.46, 0.32);
uniform float glow_strength = 0.35;
uniform float glow_height = 0.10;
// Облака: высота слоя (в единицах проекции), покрытие 0…1, мягкость края, цвета низа (зарево) и верха.
uniform float cloud_scale = 2.2;
uniform float cloud_cover = 0.48;
uniform float cloud_soft = 0.22;
uniform float cloud_alpha = 0.85;
uniform vec3 cloud_lit : source_color = vec3(0.52, 0.47, 0.44);    // низ облака у горизонта, в зареве
uniform vec3 cloud_dark : source_color = vec3(0.25, 0.28, 0.35);   // облако в зените: светлее неба (город подсвечивает), холодное
uniform vec2 cloud_offset = vec2(3.1, 7.4);   // сдвиг рисунка облаков (постоянный)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float v_angle = acos(clamp(dir.y, -1.0, 1.0));
	vec3 color;
	if (dir.y >= 0.0) {
		float c = 1.0 - v_angle / (PI * 0.5);
		color = mix(horizon_color, top_color, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
		if (!AT_CUBEMAP_PASS) {
			// Зарево — у самого горизонта; над крышами в кадре его край, выше — чистые сумерки ART-05.
			// В кубической карте зарева нет: общий свет сцены (тени на снегу, ART-04 черта 14) не теплеет.
			float glow = exp(-dir.y / glow_height);
			color = mix(color, glow_color, glow * glow_strength);
			// Проекция на слой облаков: дальние облака сжаты к горизонту и тают в дымке.
			vec2 uv = dir.xz / (dir.y + 0.12) * cloud_scale + cloud_offset;
			float n = clamp((fbm(uv) - 0.28) / 0.42, 0.0, 1.0);   // fbm собрано у 0,47 — растянуть на 0…1
			float shape = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + cloud_soft, n);
			float thick = smoothstep(1.0 - cloud_cover, 1.0, n);
			// Низ облака у горизонта — в зареве; в зените — тёмное холодное, с краем светлее (просвет неба).
			vec3 cloud = mix(cloud_lit, cloud_dark, smoothstep(0.0, 0.8, dir.y));
			cloud = mix(cloud, cloud * 0.8, thick);
			cloud = mix(cloud, glow_color, glow * glow_strength * 0.8);
			float haze = smoothstep(0.02, 0.18, dir.y);   // у горизонта облака уходят в дымку
			color = mix(color, cloud, shape * cloud_alpha * haze);
		}
	} else {
		float c = (v_angle - PI * 0.5) / (PI * 0.5);
		color = mix(ground_horizon, ground_bottom, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
	}
	COLOR = color;
}
