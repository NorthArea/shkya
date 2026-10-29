shader_type spatial;
// Ближние хлопья с боке (CITY-02 L): крупные размытые диски в 0,4–3 м от камеры — снег «у самого объектива».
// MultiMesh, как wet_snow: точки заворачиваются в оболочку вокруг камеры, снос ветром — drift из lighting.gd.
// Мягкий диск с чуть более ярким краем (боке), складывается со сценой (только светлее фона). В середине кадра, где персонаж, ближние хлопья
// гаснут (center_clear): лица не закрываются (POLISH-02, п. 14; критерий CITY-01 — лица не темнее 1 %).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec3 box = vec3(6.0, 4.0, 6.0);       // объём вокруг камеры
uniform vec3 drift = vec3(0.0);               // м, накопленный снос (lighting.gd)
uniform float density = 1.0;
uniform float fall_speed = 1.3;
uniform float near = 0.45;                    // м: ближе — нет (не во весь кадр)
uniform float far = 3.0;                      // м: дальше — обычные хлопья wet_snow
uniform float size = 0.05;                    // м, диаметр диска на 1 м (растёт с удалением — размытие)
uniform vec4 color : source_color = vec4(0.90, 0.93, 1.0, 0.05);
uniform vec2 center_clear = vec2(0.28, 0.42);   // полуоси «окна» в центре кадра (доли экрана), где хлопьев нет

varying float alpha;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;
	float r = hash(seed);
	vec3 p = seed + drift - vec3(0.0, fall_speed * (0.8 + 0.4 * r) * TIME, 0.0);
	p.x += sin(TIME * (0.7 + r) + r * 6.28) * 0.12;
	p.z += cos(TIME * (0.5 + r) + r * 4.0) * 0.1;
	vec3 center = CAMERA_POSITION_WORLD;
	vec3 low = center - box * 0.5;
	vec3 world = low + mod(p - low, box);
	vec3 view = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	float dist = length(view);
	VERTEX = view + VERTEX * size * (0.6 + 0.8 * hash(seed.zyx)) * max(dist, 0.5);
	NORMAL = vec3(0.0, 0.0, 1.0);
	vec4 clip = PROJECTION_MATRIX * vec4(view, 1.0);
	vec2 ndc = clip.xy / max(clip.w, 1e-3);
	float in_front = step(0.0, -view.z);
	float centre = length(ndc / (center_clear * 2.0));
	float clear = smoothstep(1.0, 1.6, centre);
	float shell = smoothstep(near, near * 1.6, dist) * (1.0 - smoothstep(far * 0.7, far, dist));
	float shown = step(hash(seed.yxz + 3.7), density);
	alpha = shell * clear * shown * in_front;
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	// Боке: ровный диск, край чуть ярче и мягкий.
	float disc = 1.0 - smoothstep(0.82, 1.0, r);
	float rim = smoothstep(0.55, 0.9, r) * disc;
	ALBEDO = color.rgb * color.a * alpha * (disc * 0.75 + rim * 0.5);
}
