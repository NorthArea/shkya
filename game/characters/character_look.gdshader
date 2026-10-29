shader_type spatial;
// CHAR3D-01/02: облик объёмного персонажа ШКЯ. Без освещения сцены, как спрайты CharacterSprite (unshaded, без
// тумана): цвет детали × тон спрайта (tone × tint), мягкий двухтоновый «toon» от нормали в осях камеры (свет слева
// сверху, как светлые пятна рисунков). Деколь — проекция трёх рисунков SVG (фас, спина, бок) по осям облика:
// координаты вершины в метрах переводятся в единицы холста, где рисунок совпадает с объёмом.
// CHAR3D-02: все детали фигуры в одном меше группы; на вершине COLOR — цвет детали (там, где рисунок прозрачен),
// UV.x — деколь на детали (1) или нет (нос-объём), UV.y — макушка цветом убора (голова); UV.x = 0,5 — только фас и спина (руки-капсулы полицейского). Смешивание проекций —
// узкой полосой по преобладающей оси нормали (двоение черт на стыке фас/бок в 3/4 — CHAR3D-01).
render_mode unshaded, cull_back, fog_disabled;

uniform vec4 tone_color : source_color = vec4(0.72, 0.72, 0.72, 1.0);
uniform float shade = 0.18;           // насколько темнее теневая сторона
uniform sampler2D tex_front : source_color, filter_linear_mipmap;
uniform sampler2D tex_back : source_color, filter_linear_mipmap;
uniform sampler2D tex_side : source_color, filter_linear_mipmap;
// viewBox рисунков по x: начало и ширина (росгвардеец шире холста 400, ART-08); по y всегда 0…600.
uniform vec2 canvas_view = vec2(0.0, 400.0);
// Стёртые области рисунка (x, y, ширина, высота; ширина 0 — нет): нарисованное, что заменено объёмом.
uniform vec4 erase_front_a = vec4(0.0);
uniform vec4 erase_front_b = vec4(0.0);
uniform vec4 erase_back_a = vec4(0.0);
uniform vec4 erase_back_b = vec4(0.0);
uniform vec4 erase_side_a = vec4(0.0);
uniform vec4 erase_side_b = vec4(0.0);
// Стёртые «трубки» фасового рисунка: отрезок (ax, ay, bx, by) и радиус (нос-хобот Илюши, CHAR3D-02).
uniform vec4 caps_front[4];
uniform vec4 caps_r = vec4(0.0);
// Верх головы (макушка под шапкой, чалмой) — цветом убора, а не растянутым краем бокового рисунка.
uniform vec4 top_color : source_color = vec4(1.0);
uniform float top_y = 0.0;            // м: макушка цветом убора только выше подбородка (голова и тело — один лофт)
uniform float m_per_unit = 0.003333;
uniform float axis = 200.0;
uniform float side_axis = 200.0;
uniform float feet_y = 590.0;
uniform float band = 0.07;            // ширина полосы смешивания проекций (по разности компонент нормали)
// Выбор рисунка — по нормали, сдвинутой к камере (горизонтально): со стороны фаса почти всё видимое покрыто фасом,
// сбоку — боком; так в кадре один рисунок, а не два с двоением черт (CHAR3D-02). 0 — только нормаль.
uniform float view_k = 3.0;
// Фас и спина «сильнее» бока, как у спрайта (CharacterSprite.FRONT_DOT 0,55 ≈ 57°): в 3/4 — фасовый рисунок.
uniform float front_bias = 1.3;
// Сдвиг меша группы (рука, нога) от осей облика: вершины меша — от шарнира группы, деколь — в осях облика.
instance uniform vec3 group_offset = vec3(0.0);

varying vec3 lpos;
varying vec3 lnrm;
varying vec3 lview;
varying vec4 vflags;

void vertex() {
	lpos = VERTEX + group_offset;
	lnrm = NORMAL;
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	lview = cam - VERTEX;
	vflags = vec4(UV, 0.0, 0.0);
}

bool inside(vec2 c, vec4 r) {
	return r.z > 0.0 && c.x >= r.x && c.y >= r.y && c.x <= r.x + r.z && c.y <= r.y + r.w;
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
	return length(p - (a + ab * t));
}

vec4 pick(sampler2D t, vec2 c, vec4 erase_a, vec4 erase_b) {
	if (c.x < canvas_view.x || c.x > canvas_view.x + canvas_view.y || c.y < 0.0 || c.y > 600.0
			|| inside(c, erase_a) || inside(c, erase_b)) {
		return vec4(0.0);
	}
	return texture(t, vec2((c.x - canvas_view.x) / canvas_view.y, c.y / 600.0));
}

void fragment() {
	vec3 base = COLOR.rgb;
	if (vflags.x > 0.25) {
		vec3 n0 = normalize(lnrm);
		vec3 v = vec3(lview.x, 0.0, lview.z);
		vec3 n = normalize(n0 + view_k * (length(v) > 1e-4 ? normalize(v) : vec3(0.0)));
		vec3 a = abs(n);
		a.z *= front_bias;
		float cy = feet_y - lpos.y / m_per_unit;
		vec2 cf = vec2(axis - lpos.x / m_per_unit, cy);
		vec4 f = pick(tex_front, cf, erase_front_a, erase_front_b);
		for (int i = 0; i < 4; i++) {
			if (caps_r[i] > 0.0 && seg_dist(cf, caps_front[i].xy, caps_front[i].zw) < caps_r[i]) {
				f = vec4(0.0);
			}
		}
		vec4 b = pick(tex_back, vec2(axis + lpos.x / m_per_unit, cy), erase_back_a, erase_back_b);
		vec4 s = pick(tex_side, vec2(side_axis - lpos.z / m_per_unit, cy), erase_side_a, erase_side_b);
		float wz = smoothstep(-band, band, a.z - max(a.x, a.y));
		float wx = smoothstep(-band, band, a.x - max(a.z, a.y));
		// Верх и низ — по самой нормали (макушка цветом убора), бок — только у деталей с боковой деколью (UV.x = 1).
		vec3 a0 = abs(n0);
		float wy = smoothstep(-band, band, a0.y - max(a0.x, a0.z) * 1.4);
		wz *= 1.0 - wy;
		wx *= 1.0 - wy;
		float wf = wz * step(n.z, 0.0);
		float wb = wz * step(0.0, n.z);
		float wt = wy * step(0.0, n0.y);
		float wd = wy * step(n0.y, 0.0);
		if (vflags.x < 0.75) {
			s = vec4(0.0);
		}
		float total = wf + wb + wx + wt + wd + 1e-4;
		vec3 top = mix(base, top_color.rgb, vflags.y * step(top_y, lpos.y));
		base = (mix(base, f.rgb, f.a) * wf + mix(base, b.rgb, b.a) * wb + mix(base, s.rgb, s.a) * wx
				+ top * wt + base * wd) / total;
	}
	float lit = dot(normalize(NORMAL), normalize(vec3(-0.45, 0.55, 0.7)));
	float k = mix(1.0 - shade, 1.0, smoothstep(-0.2, 0.35, lit));
	ALBEDO = base * tone_color.rgb * k;
}
