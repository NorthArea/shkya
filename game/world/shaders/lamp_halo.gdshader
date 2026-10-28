shader_type spatial;
// Ореол фонаря в снегопаде (CITY-01 L): спрайт лицом к камере, яркое ядро и широкий слабый ореол, складывается со
// сценой. Цвет — из экземпляра MultiMesh, размер — масштаб экземпляра. Без тумана (иначе additive добавлял бы цвет
// тумана) и без записи глубины; вблизи камеры гаснет, чтобы не закрывать кадр пятном.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform float energy = 0.55;
uniform float core = 18.0;        // резкость ядра
uniform float wide = 3.5;         // резкость широкого ореола
uniform float wide_share = 0.35;
uniform float near_fade = 2.5;    // м
uniform float far_fade = 140.0;   // м

varying float fade;
varying vec3 tint;

void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	VERTEX = center + VERTEX * size;
	NORMAL = vec3(0.0, 0.0, 1.0);
	float dist = length(center);
	fade = smoothstep(near_fade, near_fade * 2.0, dist) * (1.0 - smoothstep(far_fade * 0.6, far_fade, dist));
	tint = COLOR.rgb;
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	float glow = exp(-r2 * core) + wide_share * exp(-r2 * wide);
	glow *= 1.0 - smoothstep(0.75, 1.0, sqrt(r2));
	ALBEDO = tint * glow * energy * fade;
}
