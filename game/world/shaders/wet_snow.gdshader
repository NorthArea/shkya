shader_type spatial;
// Мокрый снег (ART-02): хлопья MultiMesh падают в мировых координатах и «заворачиваются» в объём вокруг камеры.
// Поэтому снег всегда есть у камеры — сразу после появления, после телепорта и в машине (хлопья летят мимо).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec3 box = vec3(32.0, 12.0, 32.0);        // размер объёма вокруг камеры
uniform float lift = 2.0;                          // центр объёма выше камеры
uniform vec3 wind = vec3(0.45, 0.0, 0.2);          // м/с
uniform float fall_speed = 1.3;                    // м/с, мокрый снег падает медленно
uniform float flake_size = 0.075;                  // м
uniform vec4 flake_color : source_color = vec4(0.93, 0.95, 1.0, 0.85);
uniform float near_fade = 1.5;                     // м: ближе — хлопья прозрачные, не закрывают кадр

varying float alpha;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;               // случайная точка в [0, box) — задаётся один раз
	float r = hash(seed);
	float speed = fall_speed * (0.75 + 0.5 * r);
	vec3 p = seed + (wind - vec3(0.0, speed, 0.0)) * TIME;
	p.x += sin(TIME * (0.8 + r) + r * 6.28) * 0.35;
	p.z += cos(TIME * (0.6 + r) + r * 4.0) * 0.25;
	vec3 center = CAMERA_POSITION_WORLD + vec3(0.0, lift, 0.0);
	vec3 low = center - box * 0.5;
	vec3 world = low + mod(p - low, box);
	vec3 view = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// Плоский хлопок, всегда лицом к камере.
	VERTEX = view + VERTEX * flake_size * (0.7 + 0.6 * hash(seed.zyx));
	NORMAL = vec3(0.0, 0.0, 1.0);
	float dist = length(view);
	vec3 edge = abs(world - center) / (box * 0.5);
	float edge_fade = 1.0 - smoothstep(0.75, 1.0, max(edge.x, max(edge.y, edge.z)));
	alpha = smoothstep(near_fade, near_fade * 2.0, dist) * edge_fade;
}

void fragment() {
	float round_flake = 1.0 - smoothstep(0.25, 0.5, length(UV - vec2(0.5)));
	ALBEDO = flake_color.rgb;
	ALPHA = flake_color.a * alpha * round_flake;
}
