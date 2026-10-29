class_name CharacterBody3DLook
extends Node3D
## CHAR3D-01/02 (вариант A): объёмный облик персонажа ШКЯ по паспорту assets/art/characters/passports.json
## (tools/character_passports.py: ручные паспорта Илюши, Бабки и полицейского, остальные — авто-паспорта из SVG).
## Голова, тело, руки и ноги — «лофт» по двум силуэтам рисунка (ширина среза по фасу, глубина по боку), у ручных —
## ещё капсулы, эллипсоиды, коробки и кольца «фестонов». Всё тело покрыто деколью трёх SVG (фас/спина/бок,
## character_look.gdshader), так что рисованные детали — пуговицы, лацканы, галстук, стёжка, карманы — на месте.
## CHAR3D-02: все детали одной группы (тело, рука, нога) — один меш с цветом детали в вершинах, на облик один
## материал + оболочка-контур (inverted hull: cull front, grow outline_m, чернила INK × tone): 5 групп → ≤10 отрисовок
## на фигуру. Меши и материалы — общие для всех фигур одного персонажа (статический кэш).
## Ходьба — маятник ног и рук по пройденному пути; set_walk_speed() — скорость снаружи (кувырок KNOCK-01: 0 —
## замереть); set_flail() — руки и ноги в стороны (полёт сбитого). Дыхание и поворот к собеседнику — снаружи
## (npc.gd масштабирует и поворачивает родителя Visual), как со спрайтом.
## Совместим с CharacterSprite по полям: character, height_m, walk_stride, shadow_size, tone, tint, view, frame.
## Выбор облика — wanted(): по умолчанию 3D (LOOK_3D в npc.gd/ilyusha.gd = true), аргумент --sprites или
## force_sprites (ART01 — набор про CharacterSprite) возвращают спрайты; --look3d и force_3d оставлены для старых
## скриптов (включают 3D и при LOOK_3D = false).

const PASSPORTS := "res://assets/art/characters/passports.json"
const LookShader = preload("res://game/characters/character_look.gdshader")
const INK := Color(0.078, 0.071, 0.075)   # #141213, чернила генератора
const WALK_SPEED_MIN := 0.4   # м/с: медленнее — стойка (как CharacterSprite)
const SEGMENTS := 20          # граней по кругу у лофта и эллипсоида
const ELLIPSOID_RINGS := 12
const FLAG := "--look3d"
const SPRITES_FLAG := "--sprites"
const GROUPS: Array[String] = ["body", "arm_r", "arm_l", "leg_r", "leg_l"]
const FLAIL_ARM := 1.25       # рад: руки в стороны в полёте
const FLAIL_LEG := 0.4        # рад: ноги врозь

static var force_3d := false
static var force_sprites := false
static var _passports := {}
static var _loaded := false
static var _mesh_cache := {}
static var _material_cache := {}

@export var character := "ilyusha"
@export var height_m := 2.4     # высота холста в метрах, как у спрайта; паспорт масштабируется под неё
@export var walk_stride := 0.32 # совместимость с CharacterSprite (шаг кадра); длина шага — паспорт walk.stride_m
@export var shadow_size := Vector2(1.1, 0.75)
@export var tone := 0.72
@export var tint := Color.WHITE
## Толщина контура, м (grow оболочки): 1,2 см ≈ чернильная линия спрайта с игровой камеры.
@export var outline_m := 0.012

var passport: Dictionary
var model: Node3D        # масштаб паспорт → height_m
var body: Node3D         # тело, голова и руки: покачивание при ходьбе
var groups := {}         # body, arm_r, arm_l, leg_r, leg_l → узел-шарнир
var parts := {}          # имя детали → MeshInstance3D её группы (детали группы в одном меше)
var meshes := {}         # группа → MeshInstance3D
var view := &"front"
var frame := -1          # -1 — стойка, 0..3 — четверть шага (как кадры спрайта)
var walk_speed := 0.0
var walk_override := -1.0
var flail := 0.0         # 0 — стоит/идёт, 1 — руки и ноги врозь (полёт)
var standing_height := 0.0   # рост фигуры в стойке, м (кэш для KNOCK-01)
var lie_half := 0.0          # полутолщина фигуры спереди назад в стойке, м
var _phase := 0.0
var _blend := 0.0
var _clock := 0.0
var _last := Vector3.INF

## Включать ли 3D-облик: константа узла (LOOK_3D), force_3d или --look3d — и не --sprites/force_sprites; паспорт есть.
static func wanted(flag: bool, name: String) -> bool:
	if force_sprites or sprites_flag():
		return false
	return (flag or force_3d or cmdline_flag()) and has_passport(name)

static func cmdline_flag() -> bool:
	return FLAG in OS.get_cmdline_args() or FLAG in OS.get_cmdline_user_args()

static func sprites_flag() -> bool:
	return SPRITES_FLAG in OS.get_cmdline_args() or SPRITES_FLAG in OS.get_cmdline_user_args()

static func passports() -> Dictionary:
	if not _loaded:
		_loaded = true
		var text := FileAccess.get_file_as_string(PASSPORTS)
		var data = JSON.parse_string(text) if text != "" else null
		if data is Dictionary and data.has("characters"):
			_passports = data
	return _passports.get("characters", {})

static func has_passport(name: String) -> bool:
	return passports().has(name)

func _ready() -> void:
	passport = passports().get(character, {})
	if passport.is_empty():
		push_warning("CharacterBody3DLook: нет паспорта для %s" % character)
		return
	model = Node3D.new()
	model.name = "Model"
	model.scale = Vector3.ONE * (height_m / float(passport["height_m"]))
	add_child(model)
	body = Node3D.new()
	body.name = "Body"
	model.add_child(body)
	groups["body"] = body
	var pivots: Dictionary = passport.get("pivots", {})
	for group in pivots:
		var pivot := Node3D.new()
		pivot.name = String(group).capitalize().replace(" ", "")
		pivot.position = _v(pivots[group])
		(body if String(group).begins_with("arm") else model).add_child(pivot)
		groups[group] = pivot
	var material := _material()
	var built := _group_meshes()
	for group in built:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_" + String(group)
		mi.mesh = built[group]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = material
		mi.set_instance_shader_parameter("group_offset", Vector3.ZERO if group == "body" else _v(passport["pivots"][group]))
		(groups[group] as Node3D).add_child(mi)
		meshes[group] = mi
	for spec in passport["parts"]:
		parts[spec["name"]] = meshes[_group_of(spec)]
	add_child(_shadow())
	var box := _extent()
	standing_height = box.end.y
	lie_half = box.size.z * 0.5

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var forward := -global_basis.z
	forward.y = 0.0
	var to_camera := camera.global_position - global_position
	to_camera.y = 0.0
	if forward.length_squared() < 0.0001 or to_camera.length_squared() < 0.0001:
		return
	var facing := forward.normalized().dot(to_camera.normalized())
	view = &"front" if facing > 0.55 else (&"back" if facing < -0.55 else &"side")

## Путь копится на шаге физики, как у CharacterSprite (ревью ART-01, P1): на 120+ к/с ходьба не сбрасывается.
func _physics_process(delta: float) -> void:
	if passport.is_empty() or delta <= 0.0:
		return
	_clock += delta
	var at := global_position
	var moved := 0.0
	if _last != Vector3.INF:
		moved = Vector2(at.x - _last.x, at.z - _last.z).length()
	_last = at
	if moved > 1.0:  # телепорт — не шаг
		moved = 0.0
	var speed := moved / delta
	if walk_override >= 0.0:
		speed = walk_override
		moved = speed * delta
	walk_speed = speed
	var walking := speed >= WALK_SPEED_MIN
	var walk: Dictionary = passport.get("walk", {})
	var stride := float(walk.get("stride_m", 0.5)) * model.scale.y
	if walking:
		_phase = fmod(_phase + moved / stride * PI, TAU * 64.0)
	_blend = move_toward(_blend, 1.0 if walking else 0.0, delta * 6.0)
	if not walking and _blend <= 0.0:
		_phase = 0.0
	frame = int(_phase / (PI * 0.5)) % 4 if walking else -1
	_apply_pose(walk)

## Скорость ходьбы снаружи, м/с (полёт, кувырок, кадры); отрицательная — снова по пройденному пути.
func set_walk_speed(speed: float) -> void:
	walk_override = speed

## Руки и ноги врозь: 0 — обычная поза, 1 — полёт (KNOCK-01); руки ещё машут.
func set_flail(amount: float) -> void:
	flail = clampf(amount, 0.0, 1.0)
	if passport and not passport.is_empty():
		_apply_pose(passport.get("walk", {}))

## Рост фигуры, м: верх всех мешей над подошвами (для сверки с ростом спрайта).
func figure_height() -> float:
	return _extent().end.y

## Полутолщина фигуры спереди назад в стойке, м: на столько центр лежащего на спине над снегом.
func lie_center() -> float:
	return lie_half

func mesh_count() -> int:
	return parts.size()

## Отрисовок на фигуру: меши групп × 2 (материал и оболочка-контур).
func draw_calls() -> int:
	return meshes.size() * 2

## Габарит мешей в осях облика (без тени).
func _extent() -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in meshes.values():
		var aabb: AABB = mi.mesh.get_aabb()
		var xf := global_transform.affine_inverse() * mi.global_transform
		for k in 8:
			var p := xf * aabb.get_endpoint(k)
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box

func _apply_pose(walk: Dictionary) -> void:
	var s := sin(_phase) * _blend
	var leg := deg_to_rad(float(walk.get("leg_swing_deg", 25.0))) * s
	var arm := deg_to_rad(float(walk.get("arm_swing_deg", 20.0))) * s
	var flap := sin(_clock * 14.0) * 0.35 * flail
	if groups.has("leg_r"):
		groups["leg_r"].rotation = Vector3(leg, 0.0, FLAIL_LEG * flail)
	if groups.has("leg_l"):
		groups["leg_l"].rotation = Vector3(-leg, 0.0, -FLAIL_LEG * flail)
	if groups.has("arm_r"):
		groups["arm_r"].rotation = Vector3(-arm, 0.0, (FLAIL_ARM + flap) * flail)
	if groups.has("arm_l"):
		groups["arm_l"].rotation = Vector3(arm, 0.0, -(FLAIL_ARM + flap) * flail)
	body.position.y = float(walk.get("bob_m", 0.02)) * absf(sin(_phase)) * _blend

# --- построение ---

func _group_of(spec: Dictionary) -> String:
	var group: String = spec.get("group", "body")
	return group if groups.has(group) else "body"

## Меши групп: все детали группы в одном ArrayMesh (вершины в осях шарнира группы). Кэш на персонажа.
func _group_meshes() -> Dictionary:
	if _mesh_cache.has(character):
		return _mesh_cache[character]
	var acc := {}
	for spec in passport["parts"]:
		var group := _group_of(spec)
		var pivot := Vector3.ZERO if group == "body" else _v(passport["pivots"][group])
		var built: Array = _build_arrays(spec)
		var xf: Transform3D = built[1]
		xf.origin -= pivot
		if not acc.has(group):
			acc[group] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedInt32Array()]
		var a: Array = acc[group]
		var start: int = (a[0] as PackedVector3Array).size()
		var src: Array = built[0]
		var color := Color(String(spec["color"])).srgb_to_linear()
		var decal = spec.get("decal", false)
		var flags := Vector2(0.5 if decal is String and decal == "front_back" else (1.0 if decal else 0.0),
			1.0 if spec.get("top", false) else 0.0)
		var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			a[0].append(xf * verts[i])
			a[1].append((xf.basis * normals[i]).normalized())
			a[2].append(color)
			a[3].append(flags)
		for i: int in src[Mesh.ARRAY_INDEX]:
			a[4].append(start + i)
	var out := {}
	for group in acc:
		var a: Array = acc[group]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = a[0]
		arrays[Mesh.ARRAY_NORMAL] = a[1]
		arrays[Mesh.ARRAY_COLOR] = a[2]
		arrays[Mesh.ARRAY_TEX_UV] = a[3]
		arrays[Mesh.ARRAY_INDEX] = a[4]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out[group] = mesh
	_mesh_cache[character] = out
	return out

## Массивы детали в её собственных осях и преобразование в оси облика: [arrays, Transform3D].
func _build_arrays(spec: Dictionary) -> Array:
	match String(spec["kind"]):
		"loft":
			var rings: Array = []
			for r in spec["rings"]:
				rings.append(PackedFloat32Array(r))
			return [_loft(rings, float(spec.get("power", 2.0))), Transform3D.IDENTITY]
		"ellipsoid":
			var radii := _v(spec["radii"])
			return [_loft(_ellipsoid_rings(radii, 2.0), 2.0), _placed(_v(spec["center"]), spec.get("rot", []))]
		"box":
			var size := _v(spec["size"]) * 0.5
			return [_loft(_ellipsoid_rings(size, 5.0), 5.0), _placed(_v(spec["center"]), spec.get("rot", []))]
		"capsule":
			var a := _v(spec["a"])
			var b := _v(spec["b"])
			var r := float(spec["r"])
			var capsule := CapsuleMesh.new()
			capsule.radius = r
			capsule.height = maxf(a.distance_to(b) + 2.0 * r, 2.0 * r + 0.001)
			capsule.radial_segments = 14
			capsule.rings = 4
			var dir := (b - a).normalized() if a.distance_to(b) > 0.0001 else Vector3.UP
			var basis := Basis(Quaternion(Vector3.UP, dir)) if dir.dot(Vector3.UP) > -0.999 else Basis(Vector3.RIGHT, PI)
			return [capsule.get_mesh_arrays(), Transform3D(basis, (a + b) * 0.5)]
		"scallops":
			return [_scallops(_v(spec["center"]), float(spec["rx"]), float(spec["rz"]), float(spec["r"]), int(spec["n"])),
				Transform3D.IDENTITY]
	push_warning("CharacterBody3DLook: неизвестная деталь %s" % spec["kind"])
	return [BoxMesh.new().get_mesh_arrays(), Transform3D.IDENTITY]

func _placed(center: Vector3, rot: Array) -> Transform3D:
	var basis := Basis.IDENTITY
	if rot.size() == 3:
		basis = Basis.from_euler(Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]), deg_to_rad(rot[2])))
	return Transform3D(basis, center)

## Срезы эллипсоида (или скруглённой коробки при vertical_power > 2) с центром в нуле: [y, xc, rx, zc, rz].
func _ellipsoid_rings(radii: Vector3, vertical_power: float) -> Array:
	var rings: Array = []
	for i in range(1, ELLIPSOID_RINGS):
		var t := PI * float(i) / ELLIPSOID_RINGS
		var c := cos(t)
		var s := sin(t)
		var y := radii.y * signf(c) * pow(absf(c), 2.0 / vertical_power)
		var k := pow(absf(s), 2.0 / vertical_power)
		rings.append(PackedFloat32Array([y, 0.0, radii.x * k, 0.0, radii.z * k]))
	rings.push_front(PackedFloat32Array([radii.y, 0.0, 0.0, 0.0, 0.0]))
	rings.push_back(PackedFloat32Array([-radii.y, 0.0, 0.0, 0.0, 0.0]))
	return rings

## Массивы по срезам сверху вниз [y, xc, rx, zc, rz]; сечение — суперэллипс степени power (2 — эллипс).
## Вершины общие по кругу (без шва), нормали — сумма нормалей граней, грани — по часовой снаружи (Godot).
func _loft(rings: Array, power: float) -> Array:
	var verts := PackedVector3Array()
	var centers: Array[Vector3] = []
	var top: PackedFloat32Array = rings[0]
	var bottom: PackedFloat32Array = rings[rings.size() - 1]
	# Срез нулевой ширины на краю — это сам полюс (эллипсоид), вершиной кольца он не становится.
	var first := 0 if top[2] > 0.0001 or top[4] > 0.0001 else 1
	var last := rings.size() - (0 if bottom[2] > 0.0001 or bottom[4] > 0.0001 else 1)
	var e := 2.0 / power
	for i in range(first, last):
		var r: PackedFloat32Array = rings[i]
		centers.append(Vector3(r[1], r[0], r[3]))
		for j in SEGMENTS:
			var a := TAU * float(j) / SEGMENTS
			var c := cos(a)
			var s := sin(a)
			verts.append(Vector3(r[1] + r[2] * signf(c) * pow(absf(c), e), r[0], r[3] + r[4] * signf(s) * pow(absf(s), e)))
	var n_rings := last - first
	# Полюса: крайний срез с нулевой шириной или на 0,3 % высоты за крайним срезом.
	var height := absf(float(rings[first][0]) - float(rings[last - 1][0]))
	var top_pole := Vector3(top[1], top[0] + (0.0 if first == 1 else height * 0.004), top[3])
	var bottom_pole := Vector3(bottom[1], bottom[0] - (0.0 if last < rings.size() else height * 0.004), bottom[3])
	var top_index := verts.size()
	verts.append(top_pole)
	var bottom_index := verts.size()
	verts.append(bottom_pole)
	var tris := PackedInt32Array()
	var hints: Array[Vector3] = []
	for i in n_rings - 1:
		for j in SEGMENTS:
			var a0 := i * SEGMENTS + j
			var a1 := i * SEGMENTS + (j + 1) % SEGMENTS
			var b0 := a0 + SEGMENTS
			var b1 := a1 + SEGMENTS
			var mid := (centers[i] + centers[i + 1]) * 0.5
			tris.append_array([a0, a1, b0, a1, b1, b0])
			hints.append(mid)
			hints.append(mid)
	for j in SEGMENTS:
		tris.append_array([top_index, j, (j + 1) % SEGMENTS])
		hints.append(centers[0] - Vector3.UP * 1000.0)
		var base := (n_rings - 1) * SEGMENTS
		tris.append_array([bottom_index, base + j, base + (j + 1) % SEGMENTS])
		hints.append(centers[n_rings - 1] + Vector3.UP * 1000.0)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for t in hints.size():
		var ia := tris[t * 3]
		var ib := tris[t * 3 + 1]
		var ic := tris[t * 3 + 2]
		var face := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		var centroid := (verts[ia] + verts[ib] + verts[ic]) / 3.0
		var outward := centroid - hints[t]
		if face.dot(outward) > 0.0:
			# По часовой снаружи: геометрическая нормаль (b−a)×(c−a) должна смотреть внутрь.
			tris[t * 3 + 1] = ic
			tris[t * 3 + 2] = ib
		else:
			face = -face
		normals[ia] += face
		normals[ib] += face
		normals[ic] += face
	for k in normals.size():
		normals[k] = normals[k].normalized() if normals[k].length_squared() > 0.0 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = tris
	return arrays

## Кольцо «фестонов» — меховой воротник или жабо: n шариков по эллипсу (как scallops генератора).
func _scallops(center: Vector3, rx: float, rz: float, r: float, n: int) -> Array:
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	var src := sphere.get_mesh_arrays()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var index := PackedInt32Array()
	for k in n:
		var a := TAU * float(k) / n
		var offset := center + Vector3(rx * cos(a), 0.0, rz * sin(a))
		var start := verts.size()
		for v: Vector3 in src[Mesh.ARRAY_VERTEX]:
			verts.append(v + offset)
		normals.append_array(src[Mesh.ARRAY_NORMAL])
		for i: int in src[Mesh.ARRAY_INDEX]:
			index.append(start + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays

## Один материал на облик (деколь трёх рисунков, макушка, стёртые области) + оболочка-контур следующим проходом.
func _material() -> Material:
	var key := "%s/%s/%s/%s/%s" % [character, tone, tint, outline_m, height_m]
	if _material_cache.has(key):
		return _material_cache[key]
	var m := ShaderMaterial.new()
	m.shader = LookShader
	m.set_shader_parameter("tone_color", Color(tone * tint.r, tone * tint.g, tone * tint.b))
	m.set_shader_parameter("m_per_unit", float(passport["m_per_unit"]))
	var canvas: Dictionary = _passports.get("canvas", {})
	m.set_shader_parameter("axis", float(canvas.get("axis", 200.0)))
	m.set_shader_parameter("side_axis", float(canvas.get("side_axis", 200.0)))
	m.set_shader_parameter("feet_y", float(canvas.get("feet_y", 590.0)))
	var decal: Dictionary = passport.get("decal", {})
	if not decal.is_empty():
		for v in ["front", "back", "side"]:
			m.set_shader_parameter("tex_" + v, load(decal["textures"][v]))
		var vb: Array = decal.get("view", [0.0, 400.0])
		m.set_shader_parameter("canvas_view", Vector2(float(vb[0]), float(vb[1])))
		m.set_shader_parameter("top_color", Color(String(decal.get("top", "#FFFFFF"))))
		m.set_shader_parameter("top_y", float(decal.get("top_y", 0.0)))
		var erase: Dictionary = decal.get("erase", {})
		for slot in [["front", 0, "erase_front_a"], ["front", 1, "erase_front_b"], ["back", 0, "erase_back_a"],
				["back", 1, "erase_back_b"], ["side", 0, "erase_side_a"], ["side", 1, "erase_side_b"]]:
			var rects: Array = erase.get(slot[0], [])
			if rects.size() > slot[1]:
				var r: Array = rects[slot[1]]
				m.set_shader_parameter(slot[2], Vector4(r[0], r[1], r[2], r[3]))
		var caps: Array = decal.get("caps", {}).get("front", [])
		var segs := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
		var radii := Vector4.ZERO
		for i in mini(caps.size(), 4):
			var c: Array = caps[i]
			segs[i] = Vector4(c[0], c[1], c[2], c[3])
			radii[i] = float(c[4])
		m.set_shader_parameter("caps_front", segs)
		m.set_shader_parameter("caps_r", radii)
	var hull := StandardMaterial3D.new()
	hull.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hull.cull_mode = BaseMaterial3D.CULL_FRONT
	hull.grow = true
	hull.grow_amount = outline_m / maxf(0.01, height_m / float(passport["height_m"]))
	hull.albedo_color = Color(INK.r * tone, INK.g * tone, INK.b * tone)
	hull.disable_fog = true
	m.next_pass = hull
	_material_cache[key] = m
	return m

func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.45))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	var mesh := PlaneMesh.new()
	mesh.size = shadow_size
	mesh.material = material
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = mesh
	shadow.position.y = 0.03
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shadow
