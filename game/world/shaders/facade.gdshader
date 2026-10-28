shader_type spatial;
// Панельный фасад (ART-02): сетка панелей и окон в мировых координатах, часть окон светится тёплым,
// грязь у земли, снег на крыше. Без текстур — всё процедурно.

uniform vec3 wall_color : source_color = vec3(0.52, 0.53, 0.55);
uniform vec3 seam_color : source_color = vec3(0.30, 0.31, 0.33);
uniform vec3 window_dark : source_color = vec3(0.08, 0.10, 0.14);
uniform vec3 window_lit : source_color = vec3(1.0, 0.68, 0.32);
uniform float lit_ratio = 0.38;
uniform float floor_height = 2.8;
uniform float window_spacing = 3.0;
uniform float window_width = 1.4;
uniform float window_height = 1.45;
uniform float ground_floor_shops = 0.0;   // 1 — первый этаж витринами
uniform float seed = 0.0;
uniform float seams = 1.0;   // 0 — оштукатуренный дом без швов панелей (И7)
uniform float stripes = 0.0; // 1 — серия 97: горизонтальные полосы голубых и серых панелей (ART-06, Н10)
uniform vec3 stripe_light : source_color = vec3(0.459, 0.545, 0.596);   // #758b98
uniform vec3 stripe_dark : source_color = vec3(0.259, 0.322, 0.373);    // #42525f
uniform vec3 frame_color : source_color = vec3(0.82, 0.83, 0.82);   // белые рамы (сверка ART-04, P3)
// CITY-01 L: температура света в горящих окнах и телевизоры (значения задаёт lighting.gd через materials.gd).
uniform vec3 window_amber : source_color = vec3(1.0, 0.56, 0.24);
uniform vec3 window_cool : source_color = vec3(0.92, 0.90, 0.80);
uniform float cool_ratio = 0.2;
uniform float tv_ratio = 0.12;
uniform vec3 tv_color : source_color = vec3(0.50, 0.66, 1.0);
uniform float tv_energy = 1.1;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = world_normal;
	if (n.y > 0.7) {
		// Крыша под снегом.
		float speck = hash(floor(world_pos.xz * 3.0));
		ALBEDO = mix(vec3(0.80, 0.83, 0.88), vec3(0.92, 0.94, 0.97), speck);
		ROUGHNESS = 0.85;
	} else {
		float u = abs(n.x) > abs(n.z) ? world_pos.z : world_pos.x;
		float v = world_pos.y;
		float storey = floor(v / floor_height);
		vec2 cell = vec2(floor(u / window_spacing), storey);
		vec2 local = vec2(fract(u / window_spacing) * window_spacing, fract(v / floor_height) * floor_height);
		vec3 color = wall_color * (0.92 + 0.12 * hash(cell * 0.37));
		if (stripes > 0.5 && local.y < 0.85) {
			color = mod(storey, 2.0) < 0.5 ? stripe_light : stripe_dark;   // подоконная панель этажа
		}
		// Швы панелей.
		float seam = (step(local.x, 0.06) + step(local.y, 0.06)) * seams;
		color = mix(color, seam_color, clamp(seam, 0.0, 1.0));
		// Грязь и сырость снизу.
		color *= mix(0.55, 1.0, smoothstep(0.0, 1.6, v));
		vec3 emission = vec3(0.0);
		// Витрины первого этажа: с простенками, часть ячеек — глухая стена или тёмная витрина
		// (ревью ART-02: сплошная светящаяся полоса читалась как торговый центр).
		bool shop = ground_floor_shops > 0.5 && storey < 0.5 && hash(cell + 7.7) > 0.3;
		float ww = shop ? window_spacing - 1.0 : window_width;
		float wh = shop ? 2.0 : window_height;
		float wx0 = (window_spacing - ww) * 0.5;
		float wy0 = shop ? 0.35 : 0.85;
		bool in_window = local.x > wx0 && local.x < wx0 + ww && local.y > wy0 && local.y < wy0 + wh && v > 0.3;
		if (in_window) {
			bool lit = shop ? hash(cell + 1.3) < 0.75 : hash(cell) < lit_ratio;
			float frame_line = step(abs(local.x - (wx0 + ww * 0.5)), 0.04);
			// Рама по краю проёма и форточка сверху.
			float edge = min(min(local.x - wx0, wx0 + ww - local.x), min(local.y - wy0, wy0 + wh - local.y));
			frame_line = max(frame_line, step(edge, 0.05));
			if (!shop) {
				frame_line = max(frame_line, step(abs(local.y - (wy0 + wh * 0.72)), 0.03) * step(local.x, wx0 + ww * 0.5));
			}
			vec3 glass = lit ? window_lit * (0.75 + 0.5 * hash(cell + 3.1)) : window_dark;
			float glass_energy = shop ? 1.25 : 1.1;
			if (lit && !shop) {
				float kind = hash(cell + 9.1);
				if (kind < tv_ratio) {
					// Телевизор в тёмной комнате: синеватое мерцание со сменой кадра ~6 раз в секунду.
					float t = TIME * 6.0 + kind * 97.0;
					float flick = mix(hash(vec2(floor(t), kind)), hash(vec2(floor(t) + 1.0, kind)), smoothstep(0.7, 1.0, fract(t)));
					glass = window_dark + tv_color * (0.2 + 0.3 * flick);
					glass_energy = tv_energy;
				} else if (kind < tv_ratio + cool_ratio) {
					glass = window_cool * (0.7 + 0.3 * hash(cell + 3.1));
				} else {
					glass = mix(glass, window_amber * (0.75 + 0.5 * hash(cell + 3.1)), step(0.6, hash(cell + 4.3)));
				}
			}
			color = mix(glass, shop ? seam_color * 0.6 : frame_color * (0.7 + 0.3 * hash(cell + 5.0)), frame_line);
			if (lit) {
				emission = glass * glass_energy * (1.0 - frame_line);
			}
			ROUGHNESS = 0.2;
		} else {
			ROUGHNESS = 0.9;
			// Снег на отливе под окном (сверка ART-04, черта 22).
			bool sill = !shop && local.x > wx0 - 0.05 && local.x < wx0 + ww + 0.05 && local.y > wy0 - 0.07 && local.y < wy0 && v > 0.3;
			if (sill) {
				color = vec3(0.80, 0.83, 0.88);
			}
		}
		ALBEDO = color;
		EMISSION = emission;
	}
}
