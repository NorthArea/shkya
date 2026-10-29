shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;
// CITY-02 E: город у горизонта — кольцо-билборд вокруг карты (третий и четвёртый слои панорамы, 450–900 м).
// Каждая «колонка» кольца — дом своей высоты; кварталы выше и ниже по шуму, редкие башни с мачтой и красным огнём.
// Выше силуэта — discard (видно небо части L). Окна — точки по доле горящих; вдали сливаются в средний свет.
// Внизу — натриевое зарево и дымка (ART-04, черта 21: слой дымки и пара у горизонта).

uniform float layer = 0.0;             // 0 — ближнее кольцо, 1 — дальнее
uniform float columns = 640.0;          // домов по кругу
uniform vec3 sil_near : source_color = vec3(0.21, 0.26, 0.33);   // темнее горизонта неба, светлее среднего слоя
uniform vec3 sil_far : source_color = vec3(0.27, 0.33, 0.41);
uniform vec3 glow : source_color = vec3(0.62, 0.42, 0.22);    // зарево натрия
uniform vec3 lit : source_color = vec3(1.0, 0.70, 0.36);
uniform float lit_ratio = 0.24;

varying vec3 local;

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	float ang = atan(local.z, local.x);
	float cols = columns * (1.0 + layer * 0.6);
	float a = (ang / 6.28318 + 0.5) * cols;
	float y = local.y + 100.0;   // кольцо высотой 200, основание на земле
	// Дом — 1–3 колонки (по хешу начала), высота по кварталу.
	float col = floor(a);
	float block = col - floor(hash(col * 0.37 + layer * 7.0) * 2.0);
	float district = vnoise(block * 0.035 + layer * 31.0) * 0.7 + vnoise(block * 0.11 + 5.0) * 0.3;
	float h1 = hash(block + layer * 101.0);
	float bh = mix(16.0, 30.0, layer) + h1 * h1 * mix(40.0, 55.0, layer) * (0.35 + 1.3 * district);
	float tower = step(0.94, hash(block * 1.31 + 3.0));
	bh *= 1.0 + tower * 0.7;
	vec3 c = mix(sil_near, sil_far, layer);
	vec3 e = vec3(0.0);
	float fx = fract(a);
	if (y > bh) {
		// Мачта на башне: тонкая, с красным мигающим огнём сверху.
		float mast = tower * step(abs(fx - 0.5), 0.05);
		if (mast < 0.5 || y > bh + 14.0) {
			discard;
		}
		if (y > bh + 12.5) {
			float blink = step(0.5, fract(TIME * 0.5 + hash(block) ));
			e = vec3(1.0, 0.08, 0.04) * 3.0 * blink;
		}
	} else {
		// Окна: две колонки окон на колонку, этаж 2,9 м.
		float wx = fract(a * 2.0);
		float fl = floor(y / 2.9);
		float wy = fract(y / 2.9);
		float px = fwidth(a * 2.0);
		float on = step(hash2(vec2(floor(a * 2.0), fl) + layer * 17.0), lit_ratio * (0.6 + 0.8 * district));
		vec3 lc = lit * (0.7 + 0.4 * hash2(vec2(fl, floor(a * 2.0))));
		if (px < 0.4) {
			float win = step(0.3, wx) * step(wx, 0.7) * step(0.35, wy) * step(wy, 0.8) * step(1.0, fl);
			e = lc * on * win;
		} else {
			e = lit * lit_ratio * 0.18;
		}
		// Крыша чуть светлее неба у горизонта нет — край силуэта тёмный; верхний этаж — техэтаж без окон.
		e *= step(y, bh - 2.0);
		e *= mix(1.1, 0.6, layer);
	}
	// Зарево и дымка у земли.
	float haze = exp(-max(y, 0.0) / mix(22.0, 30.0, layer));
	c = mix(c, glow * 0.55, haze * mix(0.55, 0.75, layer));
	ALBEDO = c + e;
}
