shader_type spatial;
// POLISH-03 A: силуэт патруля сквозь стены. Тот же рисунок, что у спрайта (CharacterSprite), billboard по Y; рисуется
// только там, где фигуру заслоняет геометрия (глубина сцены ближе своей больше чем на bias), — контур ярче, заливка
// бледнее. Где патруль виден сам, силуэт отброшен.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 tint : source_color = vec4(0.62, 0.86, 1.0, 1.0);
uniform float fill_alpha = 0.12;
uniform float edge_alpha = 0.95;
uniform float edge_px = 2.5;   // ширина контура в пикселях экрана
uniform float flip = 0.0;
uniform float bias = 0.4;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	float a = texture(albedo_tex, uv).a;
	if (a < 0.5) {
		discard;
	}
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	float scene = -view.z / view.w;
	float mine = -VERTEX.z;
	if (scene > mine - bias) {
		discard;
	}
	vec2 px = fwidth(uv) * edge_px;
	float inner = min(min(texture(albedo_tex, uv + vec2(px.x, 0.0)).a, texture(albedo_tex, uv - vec2(px.x, 0.0)).a),
		min(texture(albedo_tex, uv + vec2(0.0, px.y)).a, texture(albedo_tex, uv - vec2(0.0, px.y)).a));
	ALBEDO = tint.rgb;
	ALPHA = inner < 0.5 ? edge_alpha : fill_alpha;
}
