shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// CITY-03: полиэтиленовый пакет-«майка». Сетка — две стенки (COLOR.r: +1 лицо, −1 спина), сшитые по бокам и дну;
// между ручками — вырез (discard), в ручках — прорези. Стенки раздуты ветром (puff), вся сетка трепещет бегущей
// волной (flutter): ручки и верх — сильнее, дно — слабее. Печать: полосы — процедурно, надпись — маска из
// SubViewport (print_tex, альфа), на спине зеркально не печатается (там только полосы). Только свой шейдер.

uniform vec3 base_color : source_color = vec3(0.80, 0.80, 0.78);
uniform vec3 band_color : source_color = vec3(0.80, 0.10, 0.08);
uniform vec3 band2_color : source_color = vec3(0.10, 0.52, 0.18);
uniform vec3 ink_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float band_mode = 0.0;       // 0 — без полос, 1 — красный верх и зелёный низ, 2 — тонкие полосы по бокам
uniform float gloss = 0.35;          // шероховатость пластика
uniform float backlight_k = 0.45;    // просвет тонкой плёнки
uniform sampler2D print_tex : source_color, filter_linear;
uniform float has_print = 0.0;
uniform vec2 bag_size = vec2(0.44, 0.64);

instance uniform float puff = 0.06;      // м, раздув стенок
instance uniform float flutter = 0.03;   // м, амплитуда трепета
instance uniform float phase = 0.0;
instance uniform float flap_speed = 9.0; // рад/с

varying float v_side;
varying vec2 v_uv;

void vertex() {
	v_side = COLOR.r;
	v_uv = UV;
	float u = UV.x;
	float v = UV.y;                       // 0 — дно, 1 — верх ручек
	float bulge = sin(PI * u) * smoothstep(0.0, 0.3, v) * (1.0 - 0.6 * smoothstep(0.7, 0.8, v));   // дно — шов, ручки тоньше
	float t = TIME * flap_speed + phase;
	float k = 0.25 + 0.9 * v;             // верх трепещет сильнее дна
	float wave = sin(v * 9.0 - t) * 0.6 + sin(u * 7.0 + t * 1.37 + phase * 0.5) * 0.4;
	float crinkle = sin(u * 23.0 + v * 17.0 + t * 2.1) * 0.15;
	VERTEX.z += v_side * puff * bulge + flutter * k * (wave + crinkle);
	VERTEX.x += flutter * 0.4 * k * sin(v * 6.0 - t * 0.8);
	VERTEX.y -= puff * 0.25 * bulge;      // раздутый пакет чуть короче
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }

void fragment() {
	float u = v_uv.x;
	float v = v_uv.y;
	// Вырез между ручками и прорези в ручках.
	if (v > 0.72) {
		float handle = step(abs(u - 0.16), 0.13) + step(abs(u - 0.84), 0.13);
		vec2 c = vec2(u < 0.5 ? 0.16 : 0.84, 0.86);
		float slot = step(abs(u - c.x), 0.055) * step(abs(v - c.y), 0.09);
		// Скруглённые верхушки ручек.
		float top = step(length((vec2(u, v) - vec2(c.x, 0.92)) * vec2(1.0, 1.6)), 0.15) + step(v, 0.92);
		if (handle < 0.5 || slot > 0.5 || top < 0.5) {
			discard;
		}
	}
	vec3 col = base_color;
	if (band_mode > 0.5 && band_mode < 1.5) {
		col = mix(band_color, band2_color, step(v, 0.22));            // красное тело, зелёное дно
		col = mix(col, base_color, step(abs(v - 0.235), 0.018));      // белая полоска-шов между ними
	} else if (band_mode > 1.5) {
		col = mix(col, band_color, step(abs(u - 0.5), 0.5) * step(0.44, abs(u - 0.5)));   // полосы у боковых швов
	}
	if (has_print > 0.5 && v_side > 0.0) {
		vec2 puv = vec2(u, 1.0 - clamp(v / 0.72, 0.0, 1.0));
		float ink = texture(print_tex, puv).a;
		col = mix(col, ink_color, ink);
	}
	// Мятая плёнка: светлые складки и мелкий «хруст» нормали.
	float fold = hash(floor(vec2(u * 9.0, v * 12.0)));
	col *= 0.9 + 0.12 * fold;
	ALBEDO = col;
	ROUGHNESS = gloss + 0.15 * fold;
	SPECULAR = 0.55;
	BACKLIGHT = col * backlight_k;
	NORMAL = normalize(NORMAL + vec3((fold - 0.5) * 0.25, (hash(floor(vec2(v * 11.0, u * 8.0))) - 0.5) * 0.25, 0.0));
}
