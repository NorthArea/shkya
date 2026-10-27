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
		// Швы панелей.
		float seam = step(local.x, 0.06) + step(local.y, 0.06);
		color = mix(color, seam_color, clamp(seam, 0.0, 1.0));
		// Грязь и сырость снизу.
		color *= mix(0.55, 1.0, smoothstep(0.0, 1.6, v));
		vec3 emission = vec3(0.0);
		bool shop = ground_floor_shops > 0.5 && storey < 0.5;
		float ww = shop ? window_spacing - 0.5 : window_width;
		float wh = shop ? 2.0 : window_height;
		float wx0 = (window_spacing - ww) * 0.5;
		float wy0 = shop ? 0.35 : 0.85;
		bool in_window = local.x > wx0 && local.x < wx0 + ww && local.y > wy0 && local.y < wy0 + wh && v > 0.3;
		if (in_window) {
			bool lit = shop || hash(cell) < lit_ratio;
			float frame_line = step(abs(local.x - (wx0 + ww * 0.5)), 0.04);
			vec3 glass = lit ? window_lit * (0.75 + 0.5 * hash(cell + 3.1)) : window_dark;
			color = mix(glass, seam_color * 0.6, frame_line);
			if (lit) {
				emission = glass * (shop ? 1.6 : 1.1) * (1.0 - frame_line);
			}
			ROUGHNESS = 0.2;
		} else {
			ROUGHNESS = 0.9;
		}
		ALBEDO = color;
		EMISSION = emission;
	}
}
