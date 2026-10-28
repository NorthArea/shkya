shader_type spatial;
// Пар из люка (CITY-01 L): клубы поднимаются, растут, тают и сносятся ветром. MultiMesh: позиция экземпляра — люк,
// INSTANCE_CUSTOM.x — фаза клуба, .yz — разброс. Без частиц: GPU-частицы оставляли шейдер при выходе (slush_spray.gd).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec3 wind = vec3(0.45, 0.0, 0.2);   // м/с, текущий ветер (lighting.gd)
uniform float life = 3.4;                   // с, жизнь клуба
uniform float rise = 2.4;                   // м за жизнь
uniform float size_start = 0.5;
uniform float size_end = 2.2;
uniform vec4 color : source_color = vec4(0.64, 0.67, 0.74, 0.26);
uniform float near_fade = 1.2;

varying float alpha;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec4 custom = INSTANCE_CUSTOM;
	float ph = fract(TIME / life + custom.x);
	vec3 pos = base + vec3(0.0, 0.15 + ph * rise, 0.0) + wind * ph * life * 0.6
		+ vec3(custom.y - 0.5, 0.0, custom.z - 0.5) * (0.2 + ph * 0.8);
	float size = mix(size_start, size_end, sqrt(ph)) * (0.8 + 0.4 * custom.y);
	vec3 center = (VIEW_MATRIX * vec4(pos, 1.0)).xyz;
	VERTEX = center + VERTEX * size;
	NORMAL = vec3(0.0, 0.0, 1.0);
	alpha = smoothstep(0.0, 0.15, ph) * (1.0 - ph) * smoothstep(near_fade, near_fade * 2.0, length(center));
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float puff = exp(-dot(d, d) * 3.0) * (1.0 - smoothstep(0.8, 1.0, length(d)));
	ALBEDO = color.rgb;
	ALPHA = color.a * alpha * puff;
}
