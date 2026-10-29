shader_type spatial;
// CITY-02 E: вал и сугроб как слежавшийся грязный снег (ART-04, черта 10; ART-05/06). Форма — сетка с шумом
// (level_geometry._bank_mesh); цвет вершины: r — грязь к дороге (брызги колёс со стороны проезжей части),
// g — корка (подтаявшая и снова замёрзшая гладкая поверхность сверху), b — срез лопаты/отвала (плотный снег на
// гранях). Грязь у низа (кромка ~0,5 м) и светлая шапка — как в snow.gdshader для roadside, чтобы валы
// с сеткой и прежние валы читались одним снегом. Без текстур.

uniform vec3 clean : source_color = vec3(0.84, 0.87, 0.92);
uniform vec3 dirty : source_color = vec3(0.42, 0.42, 0.44);
uniform vec3 grime : source_color = vec3(0.07, 0.09, 0.11);   // гребень у дороги #1c2c39 в сумерках (ART-04, 10)
uniform vec3 brown : source_color = vec3(0.36, 0.31, 0.25);
uniform vec3 crust_tint : source_color = vec3(0.74, 0.80, 0.88);
uniform vec3 cold_tint : source_color = vec3(0.80, 0.91, 1.0);
uniform float roadside = 1.0;   // 0 — дворовый сугроб без брызг у низа
uniform float scale = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 marks;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	marks = COLOR.rgb;
}

void fragment() {
	vec2 p = world_pos.xz * scale + world_pos.y * 0.7;
	float n = noise(p) * 0.6 + noise(p * 3.1) * 0.3 + noise(p * 9.0) * 0.1;
	float fine = noise(world_pos.xz * 6.0 + world_pos.y * 4.0) * 0.6 + noise(world_pos.xz * 17.0 - world_pos.y * 9.0) * 0.4;
	float dirt = smoothstep(0.55, 0.85, n);
	// Слежавшийся снег серо-бурый, не открыточный (черта 10, концепт 05); дворовые сугробы чище.
	vec3 packed = mix(clean, mix(dirty, brown, 0.3), mix(0.3, 0.45, roadside) + dirt * 0.25);
	vec3 color = packed;
	// Срез лопаты и отвала: плотный, чуть голубоватый (под брызгами — их кидает поверх).
	color = mix(color, mix(clean * 0.92, crust_tint * 0.9, 0.5), marks.b * 0.6);
	// Брызги от колёс: со стороны дороги, гуще у низа, рваными пятнами.
	float splash = marks.r * smoothstep(0.3, 0.7, fine + marks.r * 0.3) * (1.0 - smoothstep(0.4, 1.4, world_pos.y) * 0.75);
	color = mix(color, mix(grime, brown, 0.45 + 0.3 * noise(p * 5.0)), clamp(splash, 0.0, 0.85));
	// Бурые пятна (реагент, песок) — редкие.
	color = mix(color, brown * 1.5, smoothstep(0.66, 0.86, noise(p * 2.1 + 4.0)) * 0.3);
	// Низ: кромка грязи 0,38–0,62 м рваной линией — только у валов у дороги (сверка CITY-02 F: было 0,15–0,31).
	float edge = 0.5 + (noise(p * 4.3 + world_pos.y) - 0.5) * 0.24;
	float low = (1.0 - smoothstep(edge - 0.06, edge + 0.04, world_pos.y)) * roadside;
	color = mix(color, mix(grime, brown, 0.35), low * 0.85);
	float cut = marks.b;
	// Шапка и корка сверху: светлая, на корке — глянец и мелкие трещины.
	float cap = smoothstep(0.45, 0.85, world_normal.y) * smoothstep(0.2, 0.55, world_pos.y);
	color = mix(color, clean * 0.95, cap * (0.5 - marks.r * 0.25));
	float crust = marks.g * cap;
	float crack = 1.0 - smoothstep(0.0, 0.025, abs(noise(world_pos.xz * 4.0) - 0.5));
	color = mix(color, crust_tint, crust * 0.45);
	color *= 1.0 - crack * crust * 0.25;
	// Холодная толща на краях — как snow.gdshader (часть L), без искр.
	vec3 view_world = normalize(CAMERA_POSITION_WORLD - world_pos);
	float rim = pow(1.0 - clamp(dot(world_normal, view_world), 0.0, 1.0), 3.0);
	color *= mix(vec3(1.0), cold_tint, 0.2 * rim * (1.0 - clamp(splash + low, 0.0, 1.0)));
	// Зернистость: мелкий рельеф нормали, сильнее на рыхлом, гладко на корке и срезе.
	float gx = noise(world_pos.xz * 9.0 + vec2(0.05, 0.0)) - noise(world_pos.xz * 9.0 - vec2(0.05, 0.0));
	float gz = noise(world_pos.xz * 9.0 + vec2(0.0, 0.05)) - noise(world_pos.xz * 9.0 - vec2(0.0, 0.05));
	float bump = 0.9 * (1.0 - crust * 0.7 - cut * 0.5);
	NORMAL_MAP = vec3(0.5 + gx * bump, 0.5 + gz * bump, 1.0);   // xy — наклон, z движок восстанавливает
	ALBEDO = color;
	ROUGHNESS = mix(0.9, 0.35, crust) - splash * 0.15;
}
