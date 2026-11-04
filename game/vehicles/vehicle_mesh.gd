extends RefCounted
## Построитель кузовов транспорта (CITY-02 V): своя геометрия через SurfaceTool, без чужих моделей и текстур.
## Примитивы: лофт поперечных сечений (кузов с арками колёс, крыша, короб фургона), тело вращения (колёса, круглые
## фары), трубка (стойки, поручни, штанги, дворники), скруглённый брусок (бамперы, сиденья, зеркала), стекло с UV2 —
## размер в метрах (резинка и иней по кромке рисует шейдер), снежная подушка.
## Нормали — по сетке центральными разностями и наружу от опорной точки; обход треугольника подгоняется под нормаль
## (лицевая грань в Godot — по часовой стрелке), поэтому порядок точек в примитивах не важен.
## Меши и материалы общие: кэш в метаданных корня дерева — все экземпляры одной модели делят один ArrayMesh и уходят
## вместе с деревом, до рендер-сервера (как Materials.clear_cache).

const PAINT := preload("res://game/vehicles/lada_paint.gdshader")
const CACHE_META := &"vehicle_mesh_cache"

## Стекло: тонированное полупрозрачное, по кромке — чёрная резинка со скруглёнными углами и иней.
## UV — доли стекла (v = 0 — нижняя кромка), UV2 — размер стекла в метрах (одинаковая ширина кромки на любом стекле).
const GLASS_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
uniform vec4 tint : source_color = vec4(0.09, 0.13, 0.22, 0.55);
uniform vec3 frost_color : source_color = vec3(0.80, 0.84, 0.90);
uniform float frost = 0.06;      // м: ширина инея по кромке (снизу — вдвое шире)
uniform float seal = 0.022;      // м: резинка
uniform float corner = 0.05;     // м: радиус скругления угла
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void fragment() {
	vec2 size = max(UV2, vec2(0.05));
	vec2 p = UV * size;
	vec2 hs = size * 0.5;
	float c = min(corner, min(hs.x, hs.y) * 0.9);
	vec2 q = abs(p - hs) - (hs - vec2(c));
	float inside = -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - c);   // м до кромки
	if (inside < 0.0) discard;
	float n = noise(p * 14.0) * 0.6 + noise(p * 47.0) * 0.4;
	float width = frost * mix(2.0, 1.0, smoothstep(0.0, 0.35, UV.y)) * (0.45 + 1.1 * n);
	float f = 1.0 - smoothstep(width * 0.35, width, inside - seal);
	f *= step(0.0005, frost);
	float s = 1.0 - smoothstep(seal * 0.8, seal, inside);
	vec3 col = mix(tint.rgb, frost_color, f * 0.85);
	ALBEDO = mix(col, vec3(0.02, 0.02, 0.025), s);
	ALPHA = mix(mix(tint.a, 0.88, f), 1.0, s);
	ROUGHNESS = mix(mix(0.28, 0.75, f), 0.7, s);
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
"""

# --- кэш ---

static func cache() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return {}
	if not tree.root.has_meta(CACHE_META):
		tree.root.set_meta(CACHE_META, {})
	return tree.root.get_meta(CACHE_META)

static func cached(key: String) -> Variant:
	return cache().get(key)

static func store(key: String, value: Variant) -> Variant:
	cache()[key] = value
	return value

# --- материалы ---

## Краска кузова: свой материал на сочетание цвета, ржавчины, грязи и снега (общий для одинаковых машин).
static func paint(color: Color, rust := 0.55, dirt := 1.0, snow := 0.0, gloss := 0.6, rust_color := Color(0.42, 0.24, 0.12)) -> ShaderMaterial:
	var key := "paint_%s_%s_%s_%s_%s_%s" % [color, snf(rust), snf(dirt), snf(snow), snf(gloss), rust_color]
	var m: ShaderMaterial = cached(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = PAINT
		m.set_shader_parameter("paint", color)
		m.set_shader_parameter("rust", rust_color)
		m.set_shader_parameter("rust_amount", rust)
		m.set_shader_parameter("dirt_amount", dirt)
		m.set_shader_parameter("snow_amount", snow)
		m.set_shader_parameter("gloss", gloss)
		store(key, m)
	return m

static func snf(v: float) -> String:
	return "%.3f" % v

## Стекло с инеем по кромке (frost — ширина инея в метрах).
static func glass(frost := 0.06, tint := Color(0.09, 0.13, 0.22, 0.55)) -> ShaderMaterial:
	var key := "glass_%s_%s" % [snf(frost), tint]
	var m: ShaderMaterial = cached(key)
	if m == null:
		if cached("glass_shader") == null:
			var shader := Shader.new()
			shader.code = GLASS_SHADER
			store("glass_shader", shader)
		m = ShaderMaterial.new()
		m.shader = cached("glass_shader")
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("frost", frost)
		m.render_priority = 1   # после водителя-спрайта и салона
		store(key, m)
	return m

## Простые материалы деталей по имени слота.
const PLAIN := {
	"trim": [Color(0.07, 0.07, 0.075), 0.65, 0.0],          # чёрный пластик, резина молдингов
	"chrome": [Color(0.72, 0.73, 0.75), 0.22, 1.0],         # хром бамперов, ручки
	"alu": [Color(0.62, 0.63, 0.64), 0.38, 0.8],            # алюминий бампера «пятёрки»
	"rubber": [Color(0.045, 0.045, 0.048), 0.92, 0.0],      # шины
	"steel": [Color(0.27, 0.27, 0.28), 0.55, 0.5],          # штампованный диск
	"steel_dark": [Color(0.26, 0.25, 0.23), 0.6, 0.4],      # диски ЗиУ (#43413b)
	"cloth": [Color(0.17, 0.15, 0.14), 0.95, 0.0],          # обивка сидений
	"dark": [Color(0.05, 0.05, 0.055), 0.9, 0.0],           # днище, подкрылки, торпедо
	"lens_amber": [Color(0.95, 0.52, 0.10), 0.2, 0.0],
	"lens_white": [Color(0.80, 0.80, 0.78), 0.15, 0.0],
	"lens_red": [Color(0.45, 0.04, 0.03), 0.2, 0.0],        # стекло фонаря без света
	"plate": [Color(0.92, 0.92, 0.90), 0.5, 0.0],
	"pole": [Color(0.86, 0.66, 0.12), 0.4, 0.3],            # жёлтые поручни троллейбуса
	"seat_red": [Color(0.42, 0.14, 0.09), 0.6, 0.0],        # пластиковые сиденья ЗиУ
	"ceiling": [Color(0.78, 0.76, 0.70), 0.8, 0.0],         # потолок салона
	"grey_roof": [Color(0.67, 0.70, 0.73), 0.6, 0.0],       # короб на крыше ЗиУ (#abb3ba)
	"bumper_dark": [Color(0.12, 0.14, 0.18), 0.6, 0.0],     # бампер и юбка ЗиУ (#1e232e)
	"grille_light": [Color(0.73, 0.75, 0.77), 0.45, 0.3],   # решётка ЗиУ (#bbbec3)
}

static func mat(name: String) -> Material:
	if name == "snow":
		return preload("res://game/world/materials.gd").snow(0.0)
	var key := "mat_" + name
	var m: StandardMaterial3D = cached(key)
	if m == null:
		var spec: Array = PLAIN[name]
		m = StandardMaterial3D.new()
		m.albedo_color = spec[0]
		m.roughness = spec[1]
		m.metallic = spec[2]
		store(key, m)
	return m

## Светящееся стекло фары или фонаря: свой материал на машину — яркость меняется на ходу.
static func lamp(color: Color, glow: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.15
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = energy
	return m

## Тёплый свет салона (троллейбус, ГСУМ): светящиеся плафоны.
static func cabin_glow(energy := 2.0) -> StandardMaterial3D:
	var key := "cabin_glow_%s" % snf(energy)
	var m: StandardMaterial3D = cached(key)
	if m == null:
		m = lamp(Color(1.0, 0.9, 0.7), Color(1.0, 0.82, 0.55), energy)
		store(key, m)
	return m

## Меш из сборщика: слоты простых материалов и снега получают свои материалы, остальные — из materials.
static func finish(b: Builder, materials := {}) -> ArrayMesh:
	var all := materials.duplicate()
	for slot in b.order:
		if not all.has(slot) and (PLAIN.has(slot) or slot == "snow"):
			all[slot] = mat(slot)
	return b.commit(all)

# --- экземпляры ---

## MeshInstance3D с общим мешем; overrides — {слот: материал} поверх материалов меша.
static func instance(parent: Node3D, name: String, mesh: ArrayMesh, overrides := {}, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	if not overrides.is_empty():
		var slots: Array = mesh.get_meta("slots", [])
		for slot in overrides:
			var index := slots.find(slot)
			if index >= 0:
				mi.set_surface_override_material(index, overrides[slot])
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Колесо: шина с протектором, диск и колпак. Ось меша — Y, узел повёрнут на 90° по Z (как прежний цилиндр), поэтому
## вращение rotate_object_local(Vector3.UP, …) в path_vehicle.gd и city_van.gd работает без изменений.
## Меш симметричен: одинаковый с обеих сторон. style: steel, classic (2106), volga, truck, bus.
static func add_wheel(parent: Node3D, at: Vector3, radius: float, width: float, style := "steel") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Wheel"
	mi.mesh = wheel_mesh(radius, width, style)
	mi.position = at
	mi.rotation.z = PI * 0.5
	mi.visibility_range_end = 120.0
	parent.add_child(mi)
	return mi

static func wheel_mesh(radius: float, width: float, style: String) -> ArrayMesh:
	var key := "wheel_%s_%s_%s" % [snf(radius), snf(width), style]
	var mesh: ArrayMesh = cached(key)
	if mesh != null:
		return mesh
	var b := Builder.new()
	var hw := width * 0.5
	var rim_r := radius * (0.66 if style == "bus" else 0.62)
	# Шина: боковина, плечо, беговая дорожка с шашками протектора.
	var tyre := PackedVector2Array([
		Vector2(rim_r, -hw + 0.01), Vector2(radius - 0.04, -hw), Vector2(radius - 0.008, -hw + 0.02),
		Vector2(radius, -hw * 0.45), Vector2(radius, hw * 0.45),
		Vector2(radius - 0.008, hw - 0.02), Vector2(radius - 0.04, hw), Vector2(rim_r, hw - 0.01)])
	b.lathe("rubber", tyre, 40, Vector3.ZERO, PackedInt32Array([3, 4]), 0.013)
	# Диск: обод, выштамповка, ступица — с обеих сторон.
	var dish := 0.05 if style == "bus" else 0.03
	var rim_slot := "steel_dark" if style == "bus" else "steel"
	for side in [-1.0, 1.0]:
		var s: float = side
		var rim := PackedVector2Array([
			Vector2(rim_r + 0.005, s * (hw - 0.012)), Vector2(rim_r * 0.9, s * (hw - 0.024)),
			Vector2(rim_r * 0.72, s * (hw - dish)), Vector2(rim_r * 0.5, s * (hw - dish - 0.006)),
			Vector2(rim_r * 0.42, s * (hw - dish * 0.55)), Vector2(0.001, s * (hw - dish * 0.55))])
		b.lathe(rim_slot, rim, 20, Vector3.ZERO)
		var cap_r := rim_r * (0.9 if style == "volga" else (0.76 if style == "classic" else 0.36))
		var cap_slot := "chrome" if style != "bus" and style != "truck" else rim_slot
		var cap := PackedVector2Array([
			Vector2(cap_r, s * (hw - dish * 0.55)), Vector2(cap_r * 0.85, s * (hw - dish * 0.2)),
			Vector2(cap_r * 0.4, s * (hw + 0.004)), Vector2(0.001, s * (hw + 0.008))])
		if style == "bus":
			cap = PackedVector2Array([Vector2(cap_r, s * (hw - dish * 0.55)), Vector2(cap_r * 0.7, s * (hw + 0.01)),
				Vector2(cap_r * 0.25, s * (hw + 0.06)), Vector2(0.001, s * (hw + 0.065))])   # конус ступицы
		b.lathe(cap_slot, cap, 16, Vector3.ZERO)
		# Гайки и вентиляционные окна — чтобы было видно вращение.
		var bolts := 8 if style == "bus" else (6 if style == "truck" else (5 if style == "volga" else 4))
		for k in bolts:
			var a := TAU * k / bolts
			var at := Vector3(cos(a) * rim_r * 0.5, s * (hw - dish * 0.5), sin(a) * rim_r * 0.5)
			b.box("chrome" if style != "bus" else "steel", Vector3(0.022, 0.02, 0.022), at)
			if style != "volga":
				var hole := Vector3(cos(a + PI / bolts) * rim_r * 0.78, s * (hw - dish * 0.75), sin(a + PI / bolts) * rim_r * 0.78)
				b.box("dark", Vector3(radius * 0.13, 0.006, radius * 0.08), hole, Basis(Vector3.UP, -(a + PI / bolts)))
	mesh = finish(b)
	return store(key, mesh)

## Выхлоп на морозе: белёсые клубы, в мировых координатах — тянутся за машиной.
static func exhaust(parent: Node3D, at: Vector3) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.name = "Exhaust"
	e.amount = 16
	e.lifetime = 1.8
	e.local_coords = false
	e.mesh = _puff_mesh()
	e.direction = Vector3(0.0, 0.25, 1.0)
	e.spread = 14.0
	e.initial_velocity_min = 0.5
	e.initial_velocity_max = 1.0
	e.gravity = Vector3(0.0, 0.35, 0.0)   # тёплый пар поднимается
	e.damping_min = 0.6
	e.damping_max = 1.0
	e.scale_amount_min = 0.7
	e.scale_amount_max = 1.2
	e.scale_amount_curve = _cached_curve()
	e.color_ramp = _cached_ramp()
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.visibility_range_end = 70.0
	e.position = at
	parent.add_child(e)
	return e

## Клуб выхлопа: билборд частицы (как BILLBOARD_PARTICLES), мягкое пятно без текстуры, светлее ночного неба —
## иначе в темноте пар читается дымом (как Materials.steam); у самой камеры гаснет, чтобы не закрывать кадр.
const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.70, 0.72, 0.78);
uniform float near_fade = 1.5;
varying float fade;
void vertex() {
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * world * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	vec3 view = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	fade = smoothstep(near_fade, near_fade * 2.0, length(view));
}
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float puff = exp(-dot(d, d) * 2.6) * (1.0 - smoothstep(0.75, 1.0, length(d)));
	ALBEDO = tint;
	ALPHA = clamp(COLOR.a, 0.0, 1.0) * puff * fade;
}
"""

static func _puff_mesh() -> QuadMesh:
	var quad: QuadMesh = cached("puff_mesh")
	if quad == null:
		var shader := Shader.new()
		shader.code = PUFF_SHADER
		var m := ShaderMaterial.new()
		m.shader = shader
		quad = QuadMesh.new()
		quad.size = Vector2(0.45, 0.45)
		quad.material = m
		store("puff_mesh", quad)
	return quad

static func _cached_curve() -> Curve:
	var curve: Curve = cached("puff_curve")
	if curve == null:
		curve = Curve.new()
		curve.add_point(Vector2(0.0, 0.35))
		curve.add_point(Vector2(1.0, 1.0))
		curve.max_value = 1.0
		store("puff_curve", curve)
	return curve

static func _cached_ramp() -> Gradient:
	var ramp: Gradient = cached("puff_ramp")
	if ramp == null:
		ramp = Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 0.42))
		ramp.set_color(1, Color(1, 1, 1, 0.0))
		store("puff_ramp", ramp)
	return ramp

# --- профили ---

## Значение ломаной [[z, y], …] в точке z с плавными переходами (косинус между узлами).
static func profile(points: Array, z: float) -> float:
	if z <= float(points[0][0]):
		return points[0][1]
	for i in range(1, points.size()):
		var z1: float = points[i][0]
		if z <= z1:
			var z0: float = points[i - 1][0]
			var t := (z - z0) / maxf(z1 - z0, 0.0001)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(points[i - 1][1], points[i][1], t)
	return points[points.size() - 1][1]

## Станции лофта нижней части кузова: верх и низ по профилям, арки колёс вырезаны по кругу (axles — z осей,
## wheel_y — высота центра колеса, arch — радиус арки), углы в плане скруглены радиусом round_front/round_rear.
## Станция: [z, низ, верх, полуширина внизу, полуширина вверху, радиус нижних углов, радиус верхних углов].
static func hull_stations(length: float, half_w: float, top: Array, bottom: Array, axles: Array, wheel_y: float, arch: float,
		round_front: float, round_rear: float, tumble := 0.025, rb := 0.05, rt := 0.07, step := 0.08) -> Array:
	var hl := length * 0.5
	var zs: Array[float] = []
	var z := -hl
	while z < hl:
		zs.append(z)
		z += step
	zs.append(hl)
	for k in 5:
		var t := float(k) / 5.0
		zs.append(-hl + round_front * t * t)
		zs.append(hl - round_rear * t * t)
	for axle in axles:
		for d in [-arch - 0.012, -arch, -arch + 0.02, -arch * 0.75, -arch * 0.45, 0.0, arch * 0.45, arch * 0.75, arch - 0.02, arch, arch + 0.012]:
			zs.append(float(axle) + d)
	zs.sort()
	var stations: Array = []
	var last := -INF
	for zz in zs:
		if zz < -hl - 0.0001 or zz > hl + 0.0001 or zz - last < 0.004:
			continue
		last = zz
		var yt := profile(top, zz)
		var yb := profile(bottom, zz)
		for axle in axles:
			var dz := zz - float(axle)
			if absf(dz) <= arch:
				yb = maxf(yb, wheel_y + sqrt(arch * arch - dz * dz))
		var w := half_w
		var into := 0.0
		if zz < -hl + round_front:
			into = (-hl + round_front - zz) / round_front
			w -= round_front * (1.0 - sqrt(maxf(1.0 - into * into, 0.0)))
		elif zz > hl - round_rear:
			into = (zz - hl + round_rear) / round_rear
			w -= round_rear * (1.0 - sqrt(maxf(1.0 - into * into, 0.0)))
		stations.append([zz, yb, yt, w, w - tumble, rb, rt])
	return stations

## Сборщик одного меша из нескольких поверхностей (слот — материал). xf — текущее преобразование добавляемых деталей.
class Builder:
	var surfaces := {}
	var order: Array[String] = []
	var xf := Transform3D.IDENTITY

	## Поперечное сечение кузова: кольцо от низа по правому борту вверх и по левому вниз.
	func section(z: float, yb: float, yt: float, w: float, wt: float, rb: float, rt: float, seg := 4) -> PackedVector3Array:
		var h := yt - yb
		rb = minf(rb, minf(h * 0.45, w * 0.9))
		rt = minf(rt, minf(h * 0.45, wt * 0.9))
		var right := PackedVector3Array()
		right.append(Vector3(0.0, yb, z))
		for k in seg + 1:
			var a := -PI * 0.5 + PI * 0.5 * k / seg
			right.append(Vector3(w - rb + cos(a) * rb, yb + rb + sin(a) * rb, z))
		for k in seg + 1:
			var a := PI * 0.5 * k / seg
			right.append(Vector3(wt - rt + cos(a) * rt, yt - rt + sin(a) * rt, z))
		right.append(Vector3(0.0, yt, z))
		var ring := right.duplicate()
		for k in range(right.size() - 2, 0, -1):
			var p := right[k]
			ring.append(Vector3(-p.x, p.y, p.z))
		return ring

	func _st(slot: String) -> SurfaceTool:
		var st: SurfaceTool = surfaces.get(slot)
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[slot] = st
			order.append(slot)
		return st

	## Треугольник в текущих осях; обход подгоняется так, чтобы лицевая сторона смотрела по нормали.
	func tri(slot: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
			ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, uv2 := Vector2.ZERO) -> void:
		var pa := xf * a
		var pb := xf * b
		var pc := xf * c
		var nbasis := xf.basis.inverse().transposed()
		var wa := (nbasis * na).normalized()
		var wb := (nbasis * nb).normalized()
		var wc := (nbasis * nc).normalized()
		var st := _st(slot)
		if (pb - pa).cross(pc - pa).dot(wa + wb + wc) > 0.0:
			_vertex(st, pa, wa, ua, uv2)
			_vertex(st, pc, wc, uc, uv2)
			_vertex(st, pb, wb, ub, uv2)
		else:
			_vertex(st, pa, wa, ua, uv2)
			_vertex(st, pb, wb, ub, uv2)
			_vertex(st, pc, wc, uc, uv2)

	func _vertex(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, uv2: Vector2) -> void:
		st.set_normal(n)
		st.set_uv(uv)
		st.set_uv2(uv2)
		st.add_vertex(p)

	## Сетка точек rows[i][j]: нормали центральными разностями, наружу от refs[i]; closed — замкнута по j.
	func grid(slot: String, rows: Array, closed: bool, refs: PackedVector3Array, uv2 := Vector2.ZERO) -> void:
		var nr := rows.size()
		var first: PackedVector3Array = rows[0]
		var nc := first.size()
		var normals: Array = []
		for i in nr:
			var row: PackedVector3Array = rows[i]
			var prev_row: PackedVector3Array = rows[maxi(i - 1, 0)]
			var next_row: PackedVector3Array = rows[mini(i + 1, nr - 1)]
			var out := PackedVector3Array()
			out.resize(nc)
			for j in nc:
				var jl := (j - 1 + nc) % nc if closed else maxi(j - 1, 0)
				var jr := (j + 1) % nc if closed else mini(j + 1, nc - 1)
				var n := (row[jr] - row[jl]).cross(next_row[j] - prev_row[j])
				var away := row[j] - refs[i]
				if n.length_squared() < 1e-12:
					n = away
				n = n.normalized()
				if n.dot(away) < 0.0:
					n = -n
				out[j] = n
			normals.append(out)
		var ucount := nc if closed else nc - 1
		for i in nr - 1:
			var r0: PackedVector3Array = rows[i]
			var r1: PackedVector3Array = rows[i + 1]
			var n0: PackedVector3Array = normals[i]
			var n1: PackedVector3Array = normals[i + 1]
			var v0 := float(i) / float(nr - 1)
			var v1 := float(i + 1) / float(nr - 1)
			for j in ucount:
				var j2 := (j + 1) % nc
				var u0 := float(j) / float(ucount)
				var u1 := float(j + 1) / float(ucount)
				tri(slot, r0[j], r1[j], r1[j2], n0[j], n1[j], n1[j2], Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1), uv2)
				tri(slot, r0[j], r1[j2], r0[j2], n0[j], n1[j2], n0[j2], Vector2(u0, v0), Vector2(u1, v1), Vector2(u1, v0), uv2)

	## Плоская крышка кольца: веер от центра с нормалью normal.
	func cap(slot: String, ring: PackedVector3Array, normal: Vector3) -> void:
		var center := Vector3.ZERO
		for p in ring:
			center += p
		center /= ring.size()
		for k in ring.size():
			tri(slot, center, ring[k], ring[(k + 1) % ring.size()], normal, normal, normal)

	## Лофт по станциям [z, низ, верх, полуширина внизу, вверху, радиус нижних углов, верхних]; торцы закрыты.
	func loft(slot: String, stations: Array, caps := true, seg := 4) -> void:
		var rows: Array = []
		var refs := PackedVector3Array()
		for s in stations:
			rows.append(section(s[0], s[1], s[2], s[3], s[4], s[5], s[6], seg))
			refs.append(Vector3(0.0, (float(s[1]) + float(s[2])) * 0.5, s[0]))
		grid(slot, rows, true, refs)
		if caps:
			cap(slot, rows[0], Vector3(0, 0, -1))
			cap(slot, rows[rows.size() - 1], Vector3(0, 0, 1))

	## Скруглённый брусок size с центром at, повёрнутый basis; r — радиус скругления рёбер.
	func rbox(slot: String, size: Vector3, at: Vector3, r := 0.02, basis := Basis.IDENTITY) -> void:
		r = minf(r, minf(size.x, minf(size.y, size.z)) * 0.45)
		var keep := xf
		xf = xf * Transform3D(basis, at)
		var hx := size.x * 0.5
		var hy := size.y * 0.5
		var hz := size.z * 0.5
		var stations := []
		var cut := r * 0.3
		stations.append([-hz, -hy + cut, hy - cut, hx - cut, hx - cut, r, r])
		stations.append([-hz + r * 0.7, -hy, hy, hx, hx, r, r])
		stations.append([hz - r * 0.7, -hy, hy, hx, hx, r, r])
		stations.append([hz, -hy + cut, hy - cut, hx - cut, hx - cut, r, r])
		loft(slot, stations, true, 2)
		xf = keep

	## Прямоугольный брусок с плоскими гранями.
	func box(slot: String, size: Vector3, at: Vector3, basis := Basis.IDENTITY) -> void:
		var keep := xf
		xf = xf * Transform3D(basis, at)
		var h := size * 0.5
		for axis in 3:
			for sgn in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = sgn
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = h[(axis + 1) % 3]
				var v := Vector3.ZERO
				v[(axis + 2) % 3] = h[(axis + 2) % 3]
				var c: Vector3 = n * h[axis]
				tri(slot, c - u - v, c + u - v, c + u + v, n, n, n, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
				tri(slot, c - u - v, c + u + v, c - u + v, n, n, n, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))
		xf = keep

	## Плоский многоугольник (выпуклый) с нормалью normal; double — и с обратной стороны.
	func poly(slot: String, points: PackedVector3Array, normal: Vector3, double := false) -> void:
		for k in range(1, points.size() - 1):
			tri(slot, points[0], points[k], points[k + 1], normal, normal, normal)
			if double:
				tri(slot, points[0], points[k], points[k + 1], -normal, -normal, -normal)

	## Трубка от a до b радиуса r (sides граней); end_caps — закрыть торцы.
	func tube(slot: String, a: Vector3, b: Vector3, r: float, sides := 6, end_caps := false) -> void:
		var axis := (b - a).normalized()
		var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(axis).normalized()
		var ra := PackedVector3Array()
		var rb := PackedVector3Array()
		for k in sides:
			var t := TAU * k / sides
			var off := (side * cos(t) + up * sin(t)) * r
			ra.append(a + off)
			rb.append(b + off)
		grid(slot, [ra, rb], true, PackedVector3Array([a, b]))
		if end_caps:
			cap(slot, ra, -axis)
			cap(slot, rb, axis)

	## Тело вращения вокруг оси Y через center: profile — (радиус, y); строки tread — с шашками протектора глубины depth.
	func lathe(slot: String, profile: PackedVector2Array, segs: int, center: Vector3, tread := PackedInt32Array(), depth := 0.0) -> void:
		var rows: Array = []
		var refs := PackedVector3Array()
		for i in profile.size():
			var p := profile[i]
			var ring := PackedVector3Array()
			for k in segs:
				var a := TAU * k / segs
				var r := p.x
				if tread.has(i) and k % 2 == 1:
					r -= depth
				ring.append(center + Vector3(cos(a) * r, p.y, sin(a) * r))
			rows.append(ring)
			refs.append(center)
		grid(slot, rows, true, refs)

	## Стекло: четырёхугольник p00 (низ-лево), p10 (низ-право), p11, p01 с выпуклостью bulge по out; UV — доли,
	## UV2 — размер в метрах.
	func pane(slot: String, p00: Vector3, p10: Vector3, p11: Vector3, p01: Vector3, out: Vector3, bulge := 0.0, nu := 4, nv := 2) -> void:
		var size := Vector2((p10.distance_to(p00) + p11.distance_to(p01)) * 0.5, (p01.distance_to(p00) + p11.distance_to(p10)) * 0.5)
		var rows: Array = []
		var refs := PackedVector3Array()
		for i in nv + 1:
			var v := float(i) / nv
			var row := PackedVector3Array()
			for j in nu + 1:
				var u := float(j) / nu
				var p := p00.lerp(p10, u).lerp(p01.lerp(p11, u), v)
				p += out * bulge * (1.0 - pow(2.0 * u - 1.0, 2.0))
				row.append(p)
			rows.append(row)
			refs.append((p00 + p10 + p11 + p01) * 0.25 - out * 10.0)
		grid(slot, rows, false, refs, size)

	## Снежная подушка sx × sz над плоскостью: y_front/y_back — высота опоры у переднего (−z) и заднего края,
	## h — толщина посередине; края сходят на нет, поверхность бугристая (seed).
	func pillow(slot: String, at: Vector3, sx: float, sz: float, h: float, y_front: float, y_back: float, seed := 0, nx := 9, nz := 7) -> void:
		var rows: Array = []
		var refs := PackedVector3Array()
		for i in nz + 1:
			var v := float(i) / nz * 2.0 - 1.0
			var row := PackedVector3Array()
			for j in nx + 1:
				var u := float(j) / nx * 2.0 - 1.0
				var e := pow(pow(absf(u), 4.0) + pow(absf(v), 4.0), 0.25)
				var lump := 1.0 + 0.22 * sin(u * 5.3 + seed * 1.7) * sin(v * 4.1 + seed * 0.9)
				var t := sqrt(clampf(1.0 - pow(e, 5.0), 0.0, 1.0)) * lump
				var y := lerpf(y_front, y_back, (v + 1.0) * 0.5) + h * t - 0.006
				row.append(at + Vector3(u * sx * 0.5, y, v * sz * 0.5))
			rows.append(row)
			refs.append(at + Vector3(0, -10.0, v * sz * 0.5))
		grid(slot, rows, false, refs)

	## Готовый меш: поверхности в порядке слотов, материалы — из materials; имена слотов — в meta "slots".
	func commit(materials := {}) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var slots: Array = []
		var cpu_arrays: Array = []
		for slot in order:
			var st: SurfaceTool = surfaces[slot]
			st.commit(mesh)
			# Snapshot decoded/generated renderer attributes once at provider creation,
			# including default tangents; impacts never read back these shared meshes.
			cpu_arrays.append(mesh.surface_get_arrays(mesh.get_surface_count() - 1))
			var m: Material = materials.get(slot)
			if m != null:
				mesh.surface_set_material(mesh.get_surface_count() - 1, m)
			slots.append(slot)
		mesh.set_meta(&"vehicle_damage_cpu_arrays", cpu_arrays)
		mesh.set_meta("slots", slots)
		return mesh
