shader_type spatial;
// Мокрый асфальт со снежной кашей (ART-02): чёрные блестящие колеи по полосам, серая каша между ними и у обочин.

uniform float along_x = 1.0;     // 1 — дорога идёт вдоль x, 0 — вдоль z
uniform vec2 center = vec2(0.0);
uniform float width = 14.0;
uniform vec3 asphalt : source_color = vec3(0.045, 0.047, 0.055);
uniform vec3 slush : source_color = vec3(0.58, 0.56, 0.51);   // бежево-серая каша (сверка ART-04: #a7a18e)
// Угол кольца (ARENA-01): колеи идут по дуге вокруг внутреннего угла corner_point; на краях плитки поперечная
// координата и координата вдоль совпадают с прямыми улицами, поэтому шва нет. corner_sign — знак направления от угла
// к оси улицы вдоль x (по z) и к оси улицы вдоль z (по x).
uniform float corner = 0.0;
uniform vec2 corner_point = vec2(0.0);
uniform vec2 corner_sign = vec2(1.0);
// Мокрый асфальт (CITY-01 L): у перекрёстков и остановок каша темнеет и блестит, в лужах отражаются фонари (SSR).
// xy — центр x/z, z — радиус, w — сила; задаёт lighting.gd (WET_SPOTS) через materials.gd.
uniform vec4 wet_spots[8];
uniform int wet_count = 0;
uniform float wet_gloss = 0.9;
uniform float wet_darken = 0.55;
uniform float wet_roughness = 0.16;
// CITY-02 L: колеи с глубиной. Высота — доля каши (колея ниже наката на rut_depth) плюс мелкие комья каши; нормаль —
// разностями высоты в мире. В мокрых пятнах колеи залиты водой: дно ровное и гладкое (puddle_roughness), SSR даёт
// отражения фонарей и окон. Значения задаёт lighting.gd (RUT_*, PUDDLE_*); по умолчанию — те же числа.
uniform float rut_depth = 0.07;           // м, накат каши над колеёй
uniform float slush_bump = 0.012;         // м, комья каши
uniform float puddle_roughness = 0.04;
uniform float puddle_level = 0.45;        // доля каши, до которой колею в мокром пятне заливает вода

// POLISH-03 C: блеск мокрых колей под фонарями (концепты 05/06/e05) — отражение светильника полосой, вытянутой к
// камере: по азимуту узко (glint_width), по высоте широко (glint_stretch). Только в колеях и лужах, цвет — натрий.
// Лампы (xyz — светильник, w — дальность, м) и ручки задаёт lighting.gd (GLINT_*); glint_gain = 0 — выключено.
uniform vec4 glint_lamps[16];
uniform int glint_count = 0;
uniform vec3 glint_color = vec3(1.0, 0.35, 0.01);
uniform float glint_gain = 0.0;
uniform float glint_width = 0.0025;
uniform float glint_stretch = 0.06;

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Доля каши (0 — чёрная колея, 1 — каша) в точке с поперечной координатой across и продольной along.
float slushiness_at(float across, float along, float half_w) {
	// Колеи: по две на каждую полосу, слегка виляют. Между ними — серая каша, чтобы пары следов
	// читались издалека (ревью ART-02: раньше колеи сливались в тёмные пятна).
	float lane = abs(across) - half_w * 0.5;
	float wobble = noise(vec2(along * 0.15, across * 0.5));
	// Колеи виляют и меняют ширину, край размыт: не «дорожная разметка» (повторная сверка ART-05, Н5).
	float sway = (noise(vec2(along * 0.08, sign(across) * 3.0)) - 0.5) * 0.7 + (noise(vec2(along * 0.5, across)) - 0.5) * 0.15;
	float rut_w = 0.22 + 0.14 * noise(vec2(along * 0.3, across * 0.8 + 11.0));
	float track = 1.0 - smoothstep(rut_w * 0.4, rut_w * 1.6, abs(abs(lane + sway) - 0.8));
	track *= mix(0.6, 1.0, noise(vec2(along * 0.4, across * 2.0)));   // пятна длиннее (И6)
	// Каша: между колеями, по оси и у бордюров.
	float edge = smoothstep(half_w - 2.2, half_w - 0.6, abs(across));
	float mid = 1.0 - smoothstep(0.3, 1.2, abs(across));
	// ART-05 по сверке ART-04 (черта 11): зимой проезд светлый — укатанная каша, тёмные только колеи.
	float between = (1.0 - track) * mix(0.62, 0.92, noise(vec2(along * 0.6, across * 1.7)));
	float s = clamp(max(max(edge, mid * 0.8), between) - track * 0.9, 0.0, 1.0);
	return s * mix(0.75, 1.0, wobble);
}

// Доля каши в точке мира xz (прямая плитка или угол кольца).
float slushiness_xz(vec2 xz) {
	float half_w = width * 0.5;
	if (corner > 0.5) {
		vec2 d = xz - corner_point;
		float r = length(d);
		// 0 — у края, которым плитка примыкает к улице вдоль x; 1 — к улице вдоль z.
		float t = atan(abs(d.x), abs(d.y) + 1e-4) / (PI * 0.5);
		float s_x = slushiness_at(corner_sign.x * (r - half_w), xz.x, half_w);
		float s_z = slushiness_at(corner_sign.y * (r - half_w), xz.y, half_w);
		return mix(s_x, s_z, smoothstep(0.0, 1.0, t));
	}
	float across = along_x > 0.5 ? xz.y - center.y : xz.x - center.x;
	float along = along_x > 0.5 ? xz.x : xz.y;
	return slushiness_at(across, along, half_w);
}

float wetness(vec2 xz) {
	float wet = 0.0;
	for (int i = 0; i < wet_count; i++) {
		float d = length(xz - wet_spots[i].xy) / wet_spots[i].z;
		wet = max(wet, (1.0 - smoothstep(0.45, 1.0, d)) * wet_spots[i].w);
	}
	if (wet > 0.0) {
		// Пятна и лужи рваные: шум, а не ровный круг.
		float patches = smoothstep(0.3, 0.65, noise(xz * 0.45) * 0.7 + noise(xz * 1.7) * 0.3);
		wet *= mix(0.45, 1.0, patches);
	}
	return wet;
}

// Высота поверхности над асфальтом, м: накат каши и комья; в мокром пятне колею заливает вода до puddle_level.
float surface_height(vec2 xz, float wet) {
	float s = slushiness_xz(xz);
	float h = s * rut_depth + noise(xz * 7.0) * slush_bump * s;
	return max(h, puddle_level * rut_depth * step(0.05, wet));
}

void fragment() {
	vec2 xz = world_pos.xz;
	float slushiness = slushiness_xz(xz);
	vec3 color = mix(asphalt, slush, slushiness);
	float roughness = mix(0.08, 0.88, slushiness);   // мокрые колеи отражают фонари, каша — матовая
	float specular = mix(0.6, 0.3, slushiness);
	float wet = wetness(xz);
	float puddle = 0.0;
	if (wet > 0.0) {
		color = mix(color, color * wet_darken, wet * slushiness);
		roughness = mix(roughness, wet_roughness, wet * wet_gloss);   // не зеркало: блик фонаря — мягкая полоса, не точка
		specular = mix(specular, 0.45, wet);
		// Вода в колее: ниже уровня заливки — гладкое зеркало (отражения SSR).
		puddle = (1.0 - smoothstep(puddle_level - 0.15, puddle_level, slushiness)) * smoothstep(0.2, 0.6, wet);
		roughness = mix(roughness, puddle_roughness, puddle);
	}
	// Глубина колеи: нормаль по разностям высоты (шаг 4 см), вода в луже — ровная.
	float e = 0.04;
	float h0 = surface_height(xz, wet);
	float hx = surface_height(xz + vec2(e, 0.0), wet);
	float hz = surface_height(xz + vec2(0.0, e), wet);
	vec3 n = normalize(vec3(-(hx - h0) / e, 1.0, -(hz - h0) / e));
	n = normalize(mix(n, vec3(0.0, 1.0, 0.0), puddle));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float rut = max(1.0 - smoothstep(0.12, 0.6, slushiness), puddle);
	if (glint_gain > 0.0 && rut > 0.02) {
		vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 r = vec3(-v.x, v.y, -v.z);   // отражённый луч взгляда от горизонтальной глади
		vec2 rh = normalize(r.xz + vec2(1e-5));
		float glint = 0.0;
		for (int i = 0; i < glint_count; i++) {
			vec3 to = glint_lamps[i].xyz - world_pos;
			float d2 = dot(to, to);
			float reach = glint_lamps[i].w;
			if (d2 > reach * reach) {
				continue;
			}
			vec3 l = to * inversesqrt(d2);
			float az = 1.0 - dot(normalize(l.xz + vec2(1e-5)), rh);
			float el = l.y - r.y;
			glint += exp(-az / glint_width - el * el / glint_stretch) * (1.0 - d2 / (reach * reach));
		}
		EMISSION = glint_color * glint * glint_gain * rut;
	}
	ALBEDO = color;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
