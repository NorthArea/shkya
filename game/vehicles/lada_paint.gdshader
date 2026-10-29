shader_type spatial;
// Краска кузовов (ART-03, CITY-02 V): цвет, ржавые потёки и грязь снизу, снежная пыль на горизонталях, лак с бликом.
// Координаты — модельные (VERTEX меша): начало на земле, y — высота над землёй в метрах, перед — −Z.
// Кузова строит game/vehicles/vehicle_mesh.gd лофтом сечений; координаты общие для всех деталей модели.

uniform vec3 paint : source_color = vec3(0.86, 0.85, 0.80);
uniform vec3 rust : source_color = vec3(0.42, 0.24, 0.12);
uniform vec3 dirt : source_color = vec3(0.30, 0.28, 0.25);
uniform float rust_amount = 0.55;
uniform float dirt_amount = 1.0;
uniform float dirt_top = 0.62;    // м: грязь от земли до этой высоты (брызги каши)
uniform float rust_top = 1.05;    // м: потёки ржавчины не выше
uniform float snow_amount = 0.0;  // 0…1: снежная пыль на почти горизонтальных поверхностях (крыша, капот)
uniform float gloss = 0.6;        // лак: старая краска — слабый, но заметный под фонарём

varying vec3 local_pos;
varying vec3 local_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 p = local_pos;
	// Горизонтальная координата вдоль поверхности: по бокам — z, спереди и сзади — x.
	float along = mix(p.z, p.x, abs(local_normal.z)) + p.x * 0.31;
	float h = p.y;
	// Потёки: вертикальные полосы шума, гуще к низу; выше rust_top — только редкие пятна.
	float streak = noise(vec2(along * 9.0, h * 1.5)) * noise(vec2(along * 3.0, 1.0));
	float low = 1.0 - smoothstep(0.2, rust_top, h);
	float r = smoothstep(0.25, 0.6, streak + low * 0.45) * rust_amount * (0.35 + 0.65 * low);
	r = max(r, smoothstep(0.82, 0.9, noise(p.xz * 6.0 + p.y * 3.0)) * rust_amount * 0.6);   // точки ржавчины
	float d = (1.0 - smoothstep(0.12, dirt_top, h)) * (0.55 + 0.45 * noise(vec2(along * 4.0, h * 6.0))) * dirt_amount;
	vec3 col = mix(paint, rust, r);
	col = mix(col, dirt, d * 0.75);
	col *= 0.93 + 0.07 * noise(vec2(along * 20.0, h * 20.0));
	// Снежная пыль: только на смотрящих вверх гранях, пятнами.
	float up = smoothstep(0.55, 0.9, local_normal.y);
	float flakes = noise(p.xz * 7.0) * 0.7 + noise(p.xz * 23.0) * 0.3;
	float s = up * smoothstep(0.45, 0.6, flakes + snow_amount * 0.6 - 0.25) * step(0.001, snow_amount);
	col = mix(col, vec3(0.85, 0.87, 0.91), s);
	float worn = max(r, d);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.3, 0.85, worn), 0.9, s);
	SPECULAR = 0.5;
	CLEARCOAT = gloss * (1.0 - worn) * (1.0 - s);
	CLEARCOAT_ROUGHNESS = 0.3;
}
