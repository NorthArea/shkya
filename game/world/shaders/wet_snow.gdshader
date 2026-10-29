shader_type spatial;
// Мокрый снег (ART-02): хлопья MultiMesh падают в мировых координатах и «заворачиваются» в объём вокруг камеры.
// Поэтому снег всегда есть у камеры — сразу после появления, после телепорта и в машине (хлопья летят мимо).
// CITY-01 L: снос ветром накапливает lighting.gd (drift — порывы меняют скорость и направление без скачков), доля
// видимых хлопьев density растёт в порыв, хлопья у ламп подсвечены их светом — ореол в снегопаде.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec3 box = vec3(32.0, 12.0, 32.0);        // размер объёма вокруг камеры
uniform float lift = 2.0;                          // центр объёма выше камеры
uniform vec3 drift = vec3(0.0);                    // м, накопленный снос ветром (lighting.gd)
uniform float density = 1.0;                       // доля видимых хлопьев 0…1
uniform float fall_speed = 1.3;                    // м/с, мокрый снег падает медленно
uniform float flake_size = 0.0525;                 // м (×0,7 от 0,075: ближние хлопья были ≈40 px, POLISH-02 п. 14)
uniform vec4 flake_color : source_color = vec4(0.93, 0.95, 1.0, 0.85);
uniform float near_fade = 3.5;                     // м: ближе — хлопья прозрачные, не закрывают лица (было 1,5)
uniform vec4 lamps[48];                            // xyz — лампа, w — радиус подсветки хлопьев
uniform int lamp_count = 0;
uniform vec3 lamp_tint : source_color = vec3(1.0, 0.74, 0.10);
uniform float lamp_gain = 1.6;
uniform float big_share = 0.0;                     // CITY-02 L: доля крупных (слипшихся) хлопьев
uniform float big_scale = 1.8;

varying float alpha;
varying float lit;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;               // случайная точка в [0, box) — задаётся один раз
	float r = hash(seed);
	float speed = fall_speed * (0.75 + 0.5 * r);
	vec3 p = seed + drift - vec3(0.0, speed * TIME, 0.0);
	p.x += sin(TIME * (0.8 + r) + r * 6.28) * 0.35;
	p.z += cos(TIME * (0.6 + r) + r * 4.0) * 0.25;
	vec3 center = CAMERA_POSITION_WORLD + vec3(0.0, lift, 0.0);
	vec3 low = center - box * 0.5;
	vec3 world = low + mod(p - low, box);
	vec3 view = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// Плоский хлопок, всегда лицом к камере.
	float big = hash(seed.xzy + 5.1) < big_share ? big_scale : 1.0;
	VERTEX = view + VERTEX * flake_size * (0.45 + 1.1 * hash(seed.zyx)) * big;   // разброс 0,45–1,55: не одинаковые диски
	NORMAL = vec3(0.0, 0.0, 1.0);
	float dist = length(view);
	vec3 edge = abs(world - center) / (box * 0.5);
	float edge_fade = 1.0 - smoothstep(0.75, 1.0, max(edge.x, max(edge.y, edge.z)));
	float shown = step(hash(seed.yxz + 3.7), density);
	alpha = smoothstep(near_fade, near_fade * 1.6, dist) * edge_fade * shown;
	lit = 0.0;
	for (int i = 0; i < lamp_count; i++) {
		float d = length(world - lamps[i].xyz) / lamps[i].w;
		lit += max(1.0 - d, 0.0) * max(1.0 - d, 0.0);
	}
	lit = min(lit, 1.0);
}

void fragment() {
	float round_flake = 1.0 - smoothstep(0.25, 0.5, length(UV - vec2(0.5)));
	ALBEDO = mix(flake_color.rgb, lamp_tint, lit * 0.55) * (1.0 + lit * lamp_gain);
	ALPHA = min(flake_color.a * (1.0 + lit * 0.3), 1.0) * alpha * round_flake;
}
