shader_type spatial;
// CHAR3D-01: облик объёмного персонажа ШКЯ. Без освещения сцены, как спрайты CharacterSprite (unshaded, без
// тумана): цвет паспорта × тон спрайта (tone × tint), мягкий двухтоновый «toon» от нормали в осях камеры
// (свет слева сверху, как светлые пятна рисунков). Деколь — проекция трёх рисунков SVG (фас, спина, бок) по осям
// облика: координаты вершины в метрах переводятся в единицы холста 400×600, где рисунок совпадает с объёмом.
render_mode unshaded, cull_back, fog_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 tone_color : source_color = vec4(0.72, 0.72, 0.72, 1.0);
uniform float shade = 0.18;           // насколько темнее теневая сторона
uniform bool use_decal = false;
uniform sampler2D tex_front : source_color, filter_linear_mipmap;
uniform sampler2D tex_back : source_color, filter_linear_mipmap;
uniform sampler2D tex_side : source_color, filter_linear_mipmap;
uniform vec4 crop_front = vec4(0.0, 0.0, 400.0, 600.0);   // x, y, ширина, высота в единицах холста
uniform vec4 crop_back = vec4(0.0, 0.0, 400.0, 600.0);
uniform vec4 crop_side = vec4(0.0, 0.0, 400.0, 600.0);
// Стёртые области рисунка (x, y, ширина, высота; ширина 0 — нет): нарисованное, что заменено объёмом (нос Илюши).
uniform vec4 erase_front_a = vec4(0.0);
uniform vec4 erase_front_b = vec4(0.0);
uniform vec4 erase_back_a = vec4(0.0);
uniform vec4 erase_back_b = vec4(0.0);
uniform vec4 erase_side_a = vec4(0.0);
uniform vec4 erase_side_b = vec4(0.0);
// Чернильные швы одежды без деколи (стёжка куртки, борт): до 4 колец на высотах lines_y (м, 0 — нет) с провисом
// к середине переда line_sag и вертикальный шов спереди seam = (x, верх, низ, 1 — есть), толщина line_w, м.
uniform vec4 lines_y = vec4(0.0);
uniform float line_sag = 0.0;
uniform float line_half = 0.3;
uniform vec4 seam = vec4(0.0);
uniform float line_w = 0.008;
// Верх головы (макушка под шапкой, чалмой) — цветом убора, а не растянутым краем бокового рисунка.
uniform vec4 top_color : source_color = vec4(1.0);
uniform float m_per_unit = 0.003333;
uniform float axis = 200.0;
uniform float side_axis = 200.0;
uniform float feet_y = 590.0;
uniform float blend_power = 16.0;

varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

bool inside(vec2 c, vec4 r) {
	return r.z > 0.0 && c.x >= r.x && c.y >= r.y && c.x <= r.x + r.z && c.y <= r.y + r.w;
}

vec4 pick(sampler2D t, vec2 c, vec4 crop, vec4 erase_a, vec4 erase_b) {
	if (!inside(c, crop) || inside(c, erase_a) || inside(c, erase_b)) {
		return vec4(0.0);
	}
	return texture(t, c / vec2(400.0, 600.0));
}

void fragment() {
	vec3 base = albedo.rgb;
	if (use_decal) {
		vec3 n = normalize(lnrm);
		float cy = feet_y - lpos.y / m_per_unit;
		vec4 f = pick(tex_front, vec2(axis - lpos.x / m_per_unit, cy), crop_front, erase_front_a, erase_front_b);
		vec4 b = pick(tex_back, vec2(axis + lpos.x / m_per_unit, cy), crop_back, erase_back_a, erase_back_b);
		vec4 s = pick(tex_side, vec2(side_axis - lpos.z / m_per_unit, cy), crop_side, erase_side_a, erase_side_b);
		float wf = pow(max(-n.z, 0.0), blend_power);
		float wb = pow(max(n.z, 0.0), blend_power);
		float ws = pow(abs(n.x), blend_power);
		float wt = pow(max(n.y, 0.0), blend_power);
		float wd = pow(max(-n.y, 0.0), blend_power);
		float total = wf + wb + ws + wt + wd + 1e-4;
		base = (mix(base, f.rgb, f.a) * wf + mix(base, b.rgb, b.a) * wb + mix(base, s.rgb, s.a) * ws
				+ top_color.rgb * wt + base * wd) / total;
	}
	float ink = 0.0;
	float front = step(lpos.z, 0.0);
	for (int i = 0; i < 4; i++) {
		if (lines_y[i] > 0.0) {
			float t = clamp(abs(lpos.x) / line_half, 0.0, 1.0);
			float y = lines_y[i] - line_sag * (1.0 - t * t) * front;
			ink = max(ink, 1.0 - smoothstep(line_w * 0.5, line_w, abs(lpos.y - y)));
		}
	}
	if (seam.w > 0.0 && lpos.y < seam.y && lpos.y > seam.z) {
		ink = max(ink, front * (1.0 - smoothstep(line_w * 0.5, line_w, abs(lpos.x - seam.x))));
	}
	base = mix(base, vec3(0.078, 0.071, 0.075), ink);
	float lit = dot(normalize(NORMAL), normalize(vec3(-0.45, 0.55, 0.7)));
	float k = mix(1.0 - shade, 1.0, smoothstep(-0.2, 0.35, lit));
	ALBEDO = base * tone_color.rgb * k;
}
