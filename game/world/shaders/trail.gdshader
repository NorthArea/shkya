shader_type spatial;
// Натоптанная тропинка (ART-05, черта 12) с мягкими рваными краями (POLISH-02, п. 19): раньше — коробка снега
// с резкими краями, у киоска под тёплым светом читалась светлой заплаткой. Плоскость PlaneMesh, UV 0..1 по ширине
// и длине; цвет — как затоптанный снег snow.gdshader, но матовый, к краям уходит в прозрачность.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 clean : source_color = vec3(0.84, 0.87, 0.92);
uniform vec3 dirty : source_color = vec3(0.42, 0.42, 0.44);
uniform float scale = 0.35;
uniform float width = 1.5;      // м: поперёк тропы — для кромки в метрах
uniform float length_m = 10.0;  // м: вдоль тропы
uniform float opacity = 0.85;

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * scale;
	float n = noise(p) * 0.6 + noise(p * 3.1) * 0.3 + noise(p * 9.0) * 0.1;
	float dirt = smoothstep(0.2, 0.85, n);
	ALBEDO = mix(clean, dirty, clamp(dirt + 0.35, 0.0, 1.0));
	ROUGHNESS = 0.85;
	// Расстояние до края в метрах: поперёк — до боковой кромки, вдоль — до торца; кромка рваная по шуму.
	float side = (0.5 - abs(UV.x - 0.5)) * width;
	float end = (0.5 - abs(UV.y - 0.5)) * length_m;
	float d = min(side, end) + (noise(world_pos.xz * 2.7) - 0.5) * 0.35;
	ALPHA = opacity * smoothstep(0.0, 0.45, d);
}
