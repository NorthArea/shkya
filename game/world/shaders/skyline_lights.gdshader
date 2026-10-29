shader_type spatial;
render_mode unshaded, fog_disabled, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// CITY-02 E: огни панорамы — точки-билборды в MultiMesh: заградительные огни башен и кранов (мигают), фонари моста,
// поток фар по мосту (точки бегут вдоль оси экземпляра). Цвет — COLOR экземпляра (a — яркость).
// INSTANCE_CUSTOM: r — режим (0 ровный, 1 мигает, 2 бежит по пути), g — фаза, b — скорость (доли пути в секунду).
// Размер точки не меньше min_px пикселей на любом расстоянии, иначе дальние огни пропадают между пикселями.

uniform float min_px = 3.0;

varying vec4 tint;
varying float bright;

void vertex() {
	vec4 custom = INSTANCE_CUSTOM;
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 path = MODEL_MATRIX[0].xyz;
	float size = length(MODEL_MATRIX[1].xyz);
	if (custom.r > 1.5) {
		center += path * (fract(TIME * custom.b + custom.g) - 0.5);
	}
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = length(center - cam);
	float px_world = dist * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	size = max(size, px_world * min_px);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + (right * VERTEX.x + up * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	tint = COLOR;
	bright = 1.0;
	if (custom.r > 0.5 && custom.r < 1.5) {
		bright = step(0.45, fract(TIME * 0.6 + custom.g)) * 0.9 + 0.1;
	}
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	if (d > 1.0) {
		discard;
	}
	float core = 1.0 - smoothstep(0.0, 1.0, d);
	ALBEDO = tint.rgb * tint.a * bright * core * core;
}
