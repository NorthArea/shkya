shader_type spatial;
// Позёмка (CITY-01 L): штрихи снега у самой земли несёт ветер. Как хлопья wet_snow: MultiMesh без CPU-работы, точки
// «заворачиваются» в объём вокруг камеры. Штрих вытянут по ветру и развёрнут к камере с любой стороны.
// Снос (drift) накапливает lighting.gd: в порыв позёмка быстрее и гуще (density).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec3 box = vec3(36.0, 0.3, 36.0);
uniform vec3 drift = vec3(0.0);            // м, накопленный снос по ветру
uniform vec3 wind_dir = vec3(0.91, 0.0, 0.40);
uniform float density = 1.0;
uniform float streak_len = 0.8;            // м
uniform float streak_width = 0.05;         // м
uniform float height = 0.04;               // низ слоя над землёй
uniform vec4 color : source_color = vec4(0.86, 0.89, 0.96, 0.22);
uniform float near_fade = 1.5;             // м

varying float alpha;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;           // случайная точка в [0, box)
	float r = hash(seed);
	vec3 p = seed + drift + wind_dir * (r - 0.5) * 1.5 * TIME;
	vec2 center = CAMERA_POSITION_WORLD.xz;
	vec2 low = center - box.xz * 0.5;
	vec2 xz = low + mod(p.xz - low, box.xz);
	vec3 world = vec3(xz.x, height + seed.y + 0.05 * sin(TIME * 3.0 + r * 20.0), xz.y);
	float len = streak_len * (0.6 + 0.8 * hash(seed.zyx));
	vec3 a = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	vec3 b = (VIEW_MATRIX * vec4(world + wind_dir * len, 1.0)).xyz;
	vec3 dir = b - a;
	vec3 side = normalize(cross(dir, a)) * streak_width;
	VERTEX = a + dir * (VERTEX.y + 0.5) + side * VERTEX.x * 2.0;
	NORMAL = vec3(0.0, 0.0, 1.0);
	vec2 edge = abs(xz - center) / (box.xz * 0.5);
	float edge_fade = 1.0 - smoothstep(0.7, 1.0, max(edge.x, edge.y));
	float life = fract(TIME * 0.45 + r * 7.0);
	float shown = step(hash(seed.yzx + 1.3), density);
	alpha = sin(life * PI) * edge_fade * shown * smoothstep(near_fade, near_fade * 2.0, length(a));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(UV.y * PI);
	ALBEDO = color.rgb;
	ALPHA = color.a * alpha * across * along;
}
