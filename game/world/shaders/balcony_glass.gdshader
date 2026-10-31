shader_type spatial;
#include "res://game/world/shaders/apartment_interior.gdshaderinc"
// Остекление лоджий и окна лестничных клеток (ART-05). Цвет — из экземпляра MultiMesh;
// альфа экземпляра 1 — за стеклом горит свет, 0 — тёмное стекло.

varying vec4 tint;
varying flat vec4 apartment;
varying vec3 pane_point;
varying vec3 pane_normal;

void vertex() {
	tint = vec4(pow(COLOR.rgb, vec3(2.2)), COLOR.a);   // цвет экземпляра задан в sRGB (повторная сверка ART-05, Н8)
	apartment = INSTANCE_CUSTOM;
	pane_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - MODEL_MATRIX[3].xyz;
	pane_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
}

void fragment() {
	vec3 glass = tint.rgb;
	// Zero custom data denotes the small, unfurnished stairwell windows.
	if (apartment.r > 0.0 && abs(pane_normal.y) < 0.5) {
		vec3 n = pane_normal;
		vec3 tangent = abs(n.x) > abs(n.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 view = normalize(CAMERA_POSITION_WORLD - world);
		float vn = max(dot(view, n), 0.08);
		vec2 direction = vec2(dot(view, tangent), view.y) / vn;
		float room_width = apartment.r + 0.12;
		float room_height = apartment.g + apartment.b + 0.12;
		vec2 g = vec2(dot(pane_point, tangent) + room_width * 0.5, pane_point.y + apartment.b + apartment.g * 0.5);
		float px = max(max(fwidth(g.x), fwidth(g.y)), 0.0001);
		if (px < 0.06) {
			vec3 inside = apartment_room(g, direction, vec2(0.0), apartment.a * 1000.0, vec3(room_width, room_height, 3.8), vec4(0.06, apartment.b, apartment.r, apartment.g), 1.0 - step(0.035, px));
			glass *= tint.a > 0.5 ? inside : (vec3(0.65) + inside * 0.45);
		}
		glass += vec3(0.025, 0.035, 0.055) * pow(1.0 - vn, 3.0);
	}
	ALBEDO = glass;
	EMISSION = glass * tint.a * 1.1;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
