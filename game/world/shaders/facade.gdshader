shader_type spatial;
#include "res://game/world/shaders/apartment_interior.gdshaderinc"
// Панельный фасад (ART-02): сетка панелей и окон в мировых координатах, часть окон светится тёплым,
// грязь у земли, снег на крыше. Без текстур — всё процедурно.
// CITY-02 B: швы панелей и кирпичная кладка с рельефом (нормали считаются здесь же), окна утоплены в стену —
// откосы и нижний откос со снегом рисуются параллаксом, за стеклом — комната (interior mapping: пол, потолок
// с лампой, стены, шторы). Сетка окон та же, что у лоджий и подоконников buildings.gd: центр окна — (k + 0,5) × шаг.

uniform vec3 wall_color : source_color = vec3(0.52, 0.53, 0.55);
uniform vec3 seam_color : source_color = vec3(0.30, 0.31, 0.33);
uniform vec3 window_dark : source_color = vec3(0.08, 0.10, 0.14);
uniform vec3 window_lit : source_color = vec3(1.0, 0.68, 0.32);
uniform float lit_ratio = 0.38;
uniform float floor_height = 2.8;
uniform float window_spacing = 3.0;
uniform float window_width = 1.4;
uniform float window_height = 1.45;
uniform float ground_floor_shops = 0.0;   // 1 — первый этаж витринами
uniform float seed = 0.0;
uniform float seams = 1.0;   // 0 — оштукатуренный дом без швов панелей (И7)
uniform float stripes = 0.0; // 1 — серия 97: горизонтальные полосы голубых и серых панелей (ART-06, Н10)
uniform vec3 stripe_light : source_color = vec3(0.459, 0.545, 0.596);   // #758b98
uniform vec3 stripe_dark : source_color = vec3(0.259, 0.322, 0.373);    // #42525f
uniform vec3 frame_color : source_color = vec3(0.82, 0.83, 0.82);   // белые рамы (сверка ART-04, P3)
// CITY-01 L: температура света в горящих окнах и телевизоры (значения задаёт lighting.gd через materials.gd).
uniform vec3 window_amber : source_color = vec3(1.0, 0.56, 0.24);
uniform vec3 window_cool : source_color = vec3(0.92, 0.90, 0.80);
uniform float cool_ratio = 0.2;
uniform float tv_ratio = 0.12;
uniform vec3 tv_color : source_color = vec3(0.50, 0.66, 1.0);
uniform float tv_energy = 1.1;
// CITY-02 B.
uniform float brick = 0.0;    // 1 — кирпичная кладка 250×65 мм, шов 12 мм, перевязка в полкирпича
uniform vec3 mortar_color : source_color = vec3(0.60, 0.57, 0.53);
uniform float belts = 0.0;    // 1 — светлые пояса по перекрытиям (кирпичные башни, ART-06, Н11)
uniform vec3 belt_color : source_color = vec3(0.80, 0.79, 0.76);
uniform float reveal_depth = 0.2;   // глубина откоса, м
uniform vec3 reveal_color : source_color = vec3(0.66, 0.66, 0.64);
uniform float relief = 1.0;   // 0 — плоский фасад без нормалей (дальние «задники»)
uniform float interior = 1.0; // 0 — без комнаты за стеклом

const vec3 SNOW = vec3(0.80, 0.83, 0.88);

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453);
}

// Доля пикселя шириной px, покрытая полосой |d| < w (точное усреднение «ящиком»): линии тоньше пикселя вдали
// не рябят, а сливаются в средний тон.
float line_cover(float d, float w, float px) {
	return clamp((min(d + px * 0.5, w) - max(d - px * 0.5, -w)) / px, 0.0, 1.0);
}

// Комната за окном: луч из точки стекла g (метры в ячейке окна: x 0..шаг, y 0..этаж) уходит вглубь по dir
// (сдвиг по стене на метр глубины). Возвращает освещённость (около 1 у дальней стены) и номер грани.
vec3 room(vec2 g, vec2 dir, vec2 cell, float depth) {
	float w = window_spacing;
	float h = floor_height;
	float sx = dir.x > 0.001 ? g.x / dir.x : (dir.x < -0.001 ? (g.x - w) / dir.x : 1e6);
	float sy = dir.y > 0.001 ? g.y / dir.y : (dir.y < -0.001 ? (g.y - h) / dir.y : 1e6);
	float s = min(min(sx, sy), depth);
	vec2 p = g - dir * s;
	float tint = hash(cell + 2.2);
	vec3 wallpaper = mix(vec3(1.0, 0.92, 0.80), vec3(0.86, 0.95, 0.88), step(0.7, tint)) * (0.85 + 0.25 * hash(cell + 8.8));
	vec3 c;
	if (s == depth) {
		c = wallpaper;
		// Шкаф или ковёр на дальней стене — тёмное пятно у части комнат.
		float k = hash(cell + 5.5);
		if (k < 0.45 && abs(p.x - w * (0.3 + 0.4 * k)) < 0.55 && p.y < 2.0 && p.y > 0.4) {
			c *= k < 0.2 ? vec3(0.55, 0.30, 0.22) : vec3(0.55, 0.45, 0.35);
		}
	} else if (s == sy) {
		if (dir.y > 0.0) {
			c = vec3(0.55, 0.40, 0.30);   // пол
		} else {
			// Потолок и люстра посередине.
			float d = length(vec2(p.x - w * 0.5, s - depth * 0.5));
			c = vec3(1.0, 0.97, 0.92) * (0.9 + 1.4 * exp(-d * d * 2.0));
		}
	} else {
		c = wallpaper * 0.8;   // боковые стены
	}
	return c * mix(1.1, 0.75, s / depth);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = world_normal;
	if (n.y > 0.7) {
		// Крыша под снегом.
		float speck = hash(floor(world_pos.xz * 3.0));
		ALBEDO = mix(vec3(0.80, 0.83, 0.88), vec3(0.92, 0.94, 0.97), speck);
		ROUGHNESS = 0.85;
	} else {
		vec3 t = abs(n.x) > abs(n.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		float u = dot(world_pos, t);
		float v = world_pos.y;
		float px = max(max(fwidth(u), fwidth(v)), 1e-4);   // метров в пикселе
		vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
		float vn = max(dot(view, n), 0.08);
		vec2 dir = vec2(dot(view, t), view.y) / vn;   // сдвиг по стене на метр глубины
		vec3 nrm = n;
		float storey = floor(v / floor_height);
		vec2 cell = vec2(floor(u / window_spacing), storey);
		vec2 local = vec2(fract(u / window_spacing) * window_spacing, fract(v / floor_height) * floor_height);
		vec3 color = wall_color * (0.92 + 0.12 * hash(cell * 0.37));
		if (stripes > 0.5 && local.y < 0.85) {
			color = mod(storey, 2.0) < 0.5 ? stripe_light : stripe_dark;   // подоконная панель этажа
		}
		if (brick > 0.5) {
			// Кладка: тычки со сдвигом в полкирпича через ряд, кирпичи чуть разного обжига, вдали — средний тон.
			float course = 0.077;
			float len = 0.262;
			float row = floor(v / course);
			float uu = u + mod(row, 2.0) * len * 0.5;
			float bx = fract(uu / len) * len;
			float by = fract(v / course) * course;
			float dx = bx < len * 0.5 ? bx : bx - len;
			float dy = by < course * 0.5 ? by : by - course;
			vec2 bid = vec2(floor(uu / len), row);
			vec3 bc = wall_color * (0.82 + 0.3 * hash(bid));
			bc *= hash(bid + 3.7) > 0.92 ? 0.68 : 1.0;
			float mortar = max(line_cover(dx, 0.006, px), line_cover(dy, 0.006, px));
			float far = smoothstep(0.01, 0.03, px);
			color = mix(mix(bc, mortar_color, mortar), mix(wall_color, mortar_color, 0.14), far);
			float bevel = relief * (1.0 - far) * 0.7;
			nrm += (t * sign(dx) * (1.0 - smoothstep(0.004, 0.016, abs(dx))) + vec3(0.0, 1.0, 0.0) * sign(dy) * (1.0 - smoothstep(0.004, 0.016, abs(dy)))) * bevel;
			if (belts > 0.5 && local.y > floor_height - 0.32) {
				color = belt_color * (0.95 + 0.05 * hash(cell));
			}
		} else if (seams > 0.5) {
			// Шов панели: тёмный герметик в желобке шириной 7 см, края желобка ловят свет (рельеф).
			float dx = local.x < window_spacing * 0.5 ? local.x : local.x - window_spacing;
			float dy = local.y < floor_height * 0.5 ? local.y : local.y - floor_height;
			float seam = max(line_cover(dx, 0.035, px), line_cover(dy, 0.035, px));
			color = mix(color, seam_color, seam);
			float bevel = relief * (1.0 - smoothstep(0.02, 0.06, px)) * 0.9;
			nrm += (t * sign(dx) * (1.0 - smoothstep(0.0, 0.035, abs(dx))) + vec3(0.0, 1.0, 0.0) * sign(dy) * (1.0 - smoothstep(0.0, 0.035, abs(dy)))) * bevel;
		}
		// Грязь и сырость снизу.
		color *= mix(0.55, 1.0, smoothstep(0.0, 1.6, v));
		vec3 emission = vec3(0.0);
		// Витрины первого этажа: с простенками, часть ячеек — глухая стена или тёмная витрина
		// (ревью ART-02: сплошная светящаяся полоса читалась как торговый центр).
		bool shop = ground_floor_shops > 0.5 && storey < 0.5 && hash(cell + 7.7) > 0.3;
		float ww = shop ? window_spacing - 1.0 : window_width;
		float wh = shop ? 2.0 : window_height;
		float wx0 = (window_spacing - ww) * 0.5;
		float wy0 = shop ? 0.35 : 0.85;
		bool in_window = local.x > wx0 && local.x < wx0 + ww && local.y > wy0 && local.y < wy0 + wh && v > 0.3;
		ROUGHNESS = 0.9;
		if (in_window) {
			bool lit = shop ? hash(cell + 1.3) < 0.75 : hash(cell) < lit_ratio;
			// Откос: луч от точки стены уходит в проём; если он упирается в боковую, верхнюю или нижнюю грань
			// раньше стекла — видна грань откоса.
			float depth = shop ? 0.12 : reveal_depth;
			float sx = dir.x > 0.001 ? (local.x - wx0) / dir.x : (dir.x < -0.001 ? (local.x - wx0 - ww) / dir.x : 1e6);
			float sy = dir.y > 0.001 ? (local.y - wy0) / dir.y : (dir.y < -0.001 ? (local.y - wy0 - wh) / dir.y : 1e6);
			float s = min(sx, sy);
			if (s < depth) {
				float k = s / depth;
				if (sx < sy) {
					color = reveal_color * (0.95 - 0.3 * k);
					nrm = t * sign(dir.x);
				} else if (dir.y > 0.0) {
					color = shop ? reveal_color * 0.8 : SNOW * (1.0 - 0.15 * k);   // нижний откос — отлив под снегом
					nrm = vec3(0.0, 1.0, 0.0);
				} else {
					color = reveal_color * (0.8 - 0.3 * k);
					nrm = vec3(0.0, -1.0, 0.0);
				}
				if (lit) {
					emission = window_lit * 0.12 * k;   // свет из комнаты на откосе у стекла
				}
			} else {
				vec2 g = local - dir * depth;   // точка на стекле
				nrm = n;   // стекло ровное: рельеф кладки и швов на него не переносится
				float frame_line = line_cover(g.x - (wx0 + ww * 0.5), 0.04, px);
				// Рама по краю проёма и форточка сверху.
				float edge = min(min(g.x - wx0, wx0 + ww - g.x), min(g.y - wy0, wy0 + wh - g.y));
				frame_line = max(frame_line, step(edge, 0.05));
				if (!shop) {
					frame_line = max(frame_line, line_cover(g.y - (wy0 + wh * 0.72), 0.03, px) * step(g.x, wx0 + ww * 0.5));
				}
				vec3 glass = lit ? window_lit * (0.75 + 0.5 * hash(cell + 3.1)) : window_dark;
				float glass_energy = shop ? 1.25 : 1.1;
				if (lit && !shop) {
					float kind = hash(cell + 9.1);
					if (kind < tv_ratio) {
						// Телевизор в тёмной комнате: синеватое мерцание со сменой кадра ~6 раз в секунду.
						float tm = TIME * 6.0 + kind * 97.0;
						float flick = mix(hash(vec2(floor(tm), kind)), hash(vec2(floor(tm) + 1.0, kind)), smoothstep(0.7, 1.0, fract(tm)));
						glass = window_dark + tv_color * (0.2 + 0.3 * flick);
						glass_energy = tv_energy;
					} else if (kind < tv_ratio + cool_ratio) {
						glass = window_cool * (0.7 + 0.3 * hash(cell + 3.1));
					} else {
						glass = mix(glass, window_amber * (0.75 + 0.5 * hash(cell + 3.1)), step(0.6, hash(cell + 4.3)));
					}
				}
				if (interior > 0.5 && px < 0.06) {   // вдали (пиксель > 6 см) комнату не считаем — не видна
					vec2 room_cell = cell + vec2(n.x * 13.0 + n.z * 29.0, floor(dot(world_pos, n) * 0.07));
					vec3 inside;
					if (shop) {
						inside = room(g, dir, cell, 5.0);
					} else {
						inside = apartment_room(g, dir, room_cell, seed, vec3(window_spacing, floor_height, 3.6), vec4(wx0, wy0, ww, wh), 1.0 - step(0.035, px));
					}
					if (lit) {
						glass *= inside;
					} else {
						// Тёмное окно: еле видная комната и холодный отблеск неба под острым углом.
						glass = window_dark * (0.7 + 0.5 * inside) + vec3(0.10, 0.13, 0.18) * pow(1.0 - vn, 3.0);
					}
				}
				color = mix(glass, shop ? seam_color * 0.6 : frame_color * (0.7 + 0.3 * hash(cell + 5.0)), frame_line);
				if (lit) {
					emission = glass * glass_energy * (1.0 - frame_line);
				}
				ROUGHNESS = mix(0.15, 0.6, frame_line);
				SPECULAR = 0.6;
			}
		} else {
			// Снег на отливе под окном (сверка ART-04, черта 22); у домов квартала отлив ещё и объёмный (buildings.gd).
			bool sill = !shop && local.x > wx0 - 0.05 && local.x < wx0 + ww + 0.05 && local.y > wy0 - 0.07 && local.y < wy0 && v > 0.3;
			if (sill) {
				color = SNOW;
			}
		}
		ALBEDO = color;
		EMISSION = emission;
		if (relief > 0.5) {
			NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nrm), 0.0)).xyz);
		}
	}
}
