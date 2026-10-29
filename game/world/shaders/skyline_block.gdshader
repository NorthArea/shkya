shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled;
// CITY-02 E: дальние дома панорамы (второй слой, 90–260 м за краем карты) одним MultiMesh. Коробка 1 × 1 × 1,
// растянутая экземпляром; окна — сетка по метрам грани (этаж 2,8 м, шаг 3 м), горит доля lit по хешу окна.
// INSTANCE_CUSTOM: r — seed, g — доля горящих, b — дымка (0 ближе, 1 у горизонта), a — тон стены.
// Без света и тумана сцены: дымку и цвет ночи задаёт сам шейдер (как Materials.far, ART-06, С2) — тон стены
// подобран к ближнему ряду в тумане, иначе дальние дома читались чёрными коробками над ним.

uniform vec3 wall_dark : source_color = vec3(0.17, 0.20, 0.25);
uniform vec3 wall_light : source_color = vec3(0.27, 0.31, 0.37);
uniform vec3 haze : source_color = vec3(0.30, 0.37, 0.46);   // туман lighting.gd в свете неба
uniform vec3 lit_warm : source_color = vec3(1.0, 0.68, 0.32);
uniform vec3 lit_cool : source_color = vec3(0.95, 0.91, 0.78);
uniform float lit_energy = 1.6;
uniform float floor_h = 2.8;
uniform float bay = 3.0;

varying vec3 local;     // метры от центра коробки
varying vec3 ext;
varying vec3 nrm;
varying vec4 custom;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void vertex() {
	ext = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	local = VERTEX * ext;
	nrm = NORMAL;
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	float seed = custom.r * 113.0;
	vec3 wall = mix(wall_dark, wall_light, custom.a);
	vec3 c = wall;
	vec3 e = vec3(0.0);
	if (abs(nrm.y) < 0.5) {
		float u = abs(nrm.x) > 0.5 ? local.z : local.x;
		float y = local.y + ext.y * 0.5;
		float fl = floor(y / floor_h);
		float col = floor(u / bay);
		vec2 f = vec2(fract(u / bay), fract(y / floor_h));
		float px = fwidth(u / bay);
		bool win = f.x > 0.22 && f.x < 0.78 && f.y > 0.3 && f.y < 0.8 && fl > 0.0 && y < ext.y - 1.2;
		float side = abs(nrm.x) > 0.5 ? sign(nrm.x) * 3.0 : sign(nrm.z) * 7.0;
		float h = hash(vec2(col + side * 31.0, fl) + seed);
		if (win || px > 0.45) {
			// Вдали окна сливаются: средний свет по доле горящих, без мерцающего муара.
			float on = px > 0.45 ? custom.g * 0.5 : step(h, custom.g);
			vec3 lc = hash(vec2(fl, col) * 1.7 + seed) < 0.15 ? lit_cool : lit_warm * (0.75 + 0.35 * hash(vec2(col, fl) + seed * 0.3));
			c = px > 0.45 ? wall : mix(wall * 0.55, wall * 0.3, 0.5);
			e = lc * on * lit_energy;
		}
		// Межэтажные швы панелей и лестничные клетки — тёмнее.
		c *= 0.92 + 0.08 * step(0.06, f.y);
	} else {
		c = wall * 0.6;
	}
	float k = custom.b;
	ALBEDO = mix(c, haze, 0.25 + k * 0.6) + e * (1.0 - k * 0.55);
}
