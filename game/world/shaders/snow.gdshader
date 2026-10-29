shader_type spatial;
// Снег (ART-02): рыхлый белый с грязными пятнами; trodden > 0 — затоптанный серый (тротуары, двор).
// roadside = 1 — вал у дороги (ART-05 по сверке ART-04, черта 10): серо-бурый, к низу почти чёрный, бурые пятна.

uniform vec3 clean : source_color = vec3(0.84, 0.87, 0.92);
uniform vec3 dirty : source_color = vec3(0.42, 0.42, 0.44);
uniform float trodden = 0.0;
uniform float scale = 0.35;
uniform float roadside = 0.0;
uniform vec3 grime : source_color = vec3(0.07, 0.09, 0.11);
uniform vec3 brown : source_color = vec3(0.36, 0.31, 0.25);
// CITY-02 L: блеск и холодная толща. Искры — редкие точки-«грани» со своим наклоном: в них вспыхивает блик ближайших
// фонарей (их позиции и цвета передаёт lighting.gd) и холодного неба — только под своим углом взгляда, поэтому мерцают
// при движении камеры. Блик — свечение (EMISSION), освещение снега не меняется (наклонная нормаль давала тёмные точки).
// Значения задаёт lighting.gd (SPARKLE_*, SNOW_COLD_*); значения по умолчанию совпадают с его константами.
uniform float sparkle_density = 0.10;     // доля ячеек с искрой на чистом снегу
uniform float sparkle_scale = 16.0;       // ячеек на метр
uniform float sparkle_size = 0.35;        // радиус искры, доля ячейки
uniform float sparkle_tilt = 0.6;         // разброс наклона грани
uniform float sparkle_sharp = 48.0;       // острота блика (степень)
uniform float sparkle_gain = 12.0;        // яркость блика (выше порога glow — искра светится)
uniform float sparkle_far = 1.2;          // ячейка меньше этой доли пикселя — искры гаснут (без мерцающего «шума»)
uniform vec4 sparkle_lamps[48];           // xyz — лампа, w — дальность
uniform vec4 sparkle_lamp_colors[48];     // rgb — цвет (линейный), a — сила
uniform int sparkle_lamp_count = 0;
uniform vec3 sparkle_sky_dir = vec3(0.0, 1.0, 0.0);   // направление на голубой направленный свет (мир)
uniform vec3 sparkle_sky_color = vec3(0.12, 0.17, 0.25);
uniform vec3 cold_tint : source_color = vec3(0.80, 0.91, 1.0);   // холодная толща снега на краях и в тени склона
uniform float cold_strength = 0.22;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
vec4 hash4(vec3 p) {
	return fract(sin(vec4(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6)), dot(p, vec3(19.7, 47.3, 389.2)))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz * scale + world_pos.y * 0.7;
	float n = noise(p) * 0.6 + noise(p * 3.1) * 0.3 + noise(p * 9.0) * 0.1;
	float dirt = smoothstep(0.55 - trodden * 0.35, 0.85, n);
	vec3 color = mix(clean, dirty, clamp(dirt + trodden * 0.35, 0.0, 1.0));
	if (roadside > 0.5) {
		// Вал — светлый слежавшийся снег (POLISH-02, п. 4: был темнее дороги). Грязь от колёс — только в нижних
		// 20–30 см с рваной кромкой, выше — редкие бурые брызги; сверху светлая шапка (ART-06, С1).
		vec3 packed = mix(clean, dirty, 0.32 + dirt * 0.25);   // проверка POLISH-02 B: вал/дорога ≈1,3, не 1,55
		color = mix(packed, brown * 1.6, smoothstep(0.62, 0.85, noise(p * 2.1 + 4.0)) * 0.35 * (1.0 - smoothstep(0.3, 0.7, world_pos.y)));
		float edge = 0.23 + (noise(p * 4.3 + world_pos.y) - 0.5) * 0.16;   // кромка грязи 0,15–0,31 м
		float low = 1.0 - smoothstep(edge - 0.06, edge + 0.04, world_pos.y);
		color = mix(color, mix(grime, brown, 0.35), low * 0.9);
		float cap = smoothstep(0.45, 0.85, world_normal.y) * smoothstep(0.25, 0.6, world_pos.y);
		color = mix(color, clean * 0.95, cap * 0.55);
	}
	// Холодная толща: на краях (взгляд по касательной) снег просвечивает голубым, как подповерхностное рассеяние.
	vec3 view_world = normalize(CAMERA_POSITION_WORLD - world_pos);
	float rim = pow(1.0 - clamp(dot(world_normal, view_world), 0.0, 1.0), 3.0);
	float clean_share = 1.0 - clamp(dirt + trodden * 0.6 + roadside * 0.4, 0.0, 1.0);
	color *= mix(vec3(1.0), cold_tint, cold_strength * rim * (0.4 + 0.6 * clean_share));
	ALBEDO = color;
	ROUGHNESS = mix(0.85, 0.45, trodden * dirt);
	// Искры: ячейка 3D-сетки, в ней точка-грань со своим наклоном; на затоптанном и грязном — реже.
	vec3 cell = floor(world_pos * sparkle_scale);
	vec4 h = hash4(cell);
	float footprint = length(fwidth(world_pos)) * sparkle_scale;
	float near = 1.0 - smoothstep(sparkle_far * 0.5, sparkle_far, footprint);
	if (h.x < sparkle_density * clean_share && near > 0.0) {
		vec3 centre = (cell + 0.25 + 0.5 * h.yzw) / sparkle_scale;
		float d = length(world_pos - centre) * sparkle_scale;
		float spark = (1.0 - smoothstep(sparkle_size * 0.5, sparkle_size, d)) * near;
		if (spark > 0.0) {
			vec3 tilt = (hash4(cell + 17.0).xyz - 0.5) * 2.0 * sparkle_tilt;
			vec3 facet = normalize(world_normal + tilt);
			vec3 glint = sparkle_sky_color * pow(max(dot(facet, normalize(sparkle_sky_dir + view_world)), 0.0), sparkle_sharp);
			for (int i = 0; i < sparkle_lamp_count; i++) {
				vec3 to_lamp = sparkle_lamps[i].xyz - world_pos;
				float dist = length(to_lamp);
				if (dist < sparkle_lamps[i].w) {
					float fall = 1.0 - dist / sparkle_lamps[i].w;
					vec3 half_v = normalize(to_lamp / dist + view_world);
					glint += sparkle_lamp_colors[i].rgb * sparkle_lamp_colors[i].a * fall * fall * pow(max(dot(facet, half_v), 0.0), sparkle_sharp);
				}
			}
			EMISSION = glint * spark * sparkle_gain;
		}
	}
}
