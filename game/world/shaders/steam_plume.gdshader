shader_type spatial;
// CITY-02 F: пар ТЭЦ, градирен и вытяжек на крышах (ART-06, Н7, Н9; С3 — белёсый, светлее неба, дымом не читается).
// Раньше — стопка полупрозрачных сфер с геометрическими краями; теперь мягкие клубы-билборды с рваной шумовой кромкой
// (по образцу steam_puff.gdshader), одним MultiMesh на вид пара. Клуб идёт по шлейфу: быстро поднимается, тормозит
// и сносится ветром, растёт и тает; клубы шлейфа сдвинуты по фазе — шлейф непрерывный и живой.
// Позиция экземпляра — устье трубы; INSTANCE_CUSTOM: x — фаза, y, z — разброс, w — множитель размера (0 → 1).
render_mode unshaded, fog_disabled, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec3 wind = vec3(-150.0, 0.0, -30.0);   // м: снос за жизнь клуба
uniform float life = 40.0;                       // с
uniform float rise = 30.0;                       // м: подъём за жизнь (с торможением)
uniform float size_start = 6.0;                  // м: поперечник у устья
uniform float size_end = 34.0;                   // м: поперечник в конце шлейфа
uniform float spread = 0.6;                      // разброс клубов поперёк шлейфа, доли size_end
uniform vec4 color : source_color = vec4(0.70, 0.72, 0.77, 0.55);
uniform vec3 under : source_color = vec3(0.60, 0.52, 0.45);   // низ клуба — в отсвете города
uniform vec3 haze : source_color = vec3(0.30, 0.37, 0.46);    // туман lighting.gd в свете неба
uniform float haze_dist = 0.0;                   // м: на этом расстоянии клуб наполовину в дымке; 0 — дымка в цвете
uniform float near_fade = 1.0;                   // м: у камеры клуб гаснет (не закрывает кадр)

varying float alpha;
varying float hz;
varying vec4 rnd;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.55 + noise(p * 2.3 + 5.1) * 0.3 + noise(p * 5.3 - 2.7) * 0.15; }

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec4 c = INSTANCE_CUSTOM;
	float ph = fract(TIME / life + c.x);
	float up = rise * (1.0 - (1.0 - ph) * (1.0 - ph));
	vec3 side = vec3(c.y - 0.5, (c.z - 0.5) * 0.4, c.z - 0.5) * size_end * spread * ph;
	vec3 pos = base + vec3(0.0, up, 0.0) + wind * ph * ph * 0.35 + wind * ph * 0.65 + side;
	float size = mix(size_start, size_end, pow(ph, 0.75)) * (0.8 + 0.4 * c.y) * mix(1.0, c.w, step(0.001, c.w));
	vec3 center = (VIEW_MATRIX * vec4(pos, 1.0)).xyz;
	VERTEX = center + VERTEX * size;
	NORMAL = vec3(0.0, 0.0, 1.0);
	float dist = length(center);
	alpha = smoothstep(0.0, 0.03, ph) * (1.0 - smoothstep(0.5, 1.0, ph)) * smoothstep(near_fade, near_fade * 2.0, dist);
	hz = haze_dist > 0.0 ? clamp(dist / (dist + haze_dist), 0.0, 0.75) : 0.0;
	rnd = vec4(c.yz, ph, c.x);
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	// Кромка рваная: шум сдвигает границу клуба, внутри — неровная плотность; шум медленно течёт.
	vec2 q = UV * 2.6 + rnd.xy * 17.0 + vec2(TIME * 0.012, -TIME * 0.02);
	float n = fbm(q);
	float n2 = fbm(UV * 6.5 - rnd.yx * 9.0 + TIME * 0.03);
	float edge = r + (n - 0.5) * 0.6 + (n2 - 0.5) * 0.22;
	float puff = 1.0 - smoothstep(0.25, 0.95, edge);
	puff *= 0.65 + 0.55 * n;
	// Верх светлее, низ — в отсвете города (UV.y растёт вниз).
	float low = smoothstep(-0.6, 0.9, d.y);
	vec3 c = mix(color.rgb * 1.06, mix(color.rgb * 0.82, under, 0.3), low);
	ALBEDO = mix(c, haze, hz);
	ALPHA = clamp(color.a * alpha * puff, 0.0, 1.0);
}
