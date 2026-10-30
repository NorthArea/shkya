extends Node3D
## Следы на снегу: колея задних колёс «Лады», шаги Илюши и близких жителей на снегу, тротуарах и во дворе.
## На проезжей части следов нет: там свои колеи (road.gdshader). Только облик, на игру не влияет.
## Буферы Илюши и колеи кольцевые; общий буфер жителей замещает только дальние или невидимые старые следы.
## Колея — лента из отрезков от прошлого положения колеса до нового: без стыков и разрывов на любой скорости.

const Layout = preload("res://game/world/layout.gd")
const SnowField = preload("res://game/world/snow_field.gd")

const TYRE_CAPACITY := 600   # отрезков колеи: 300 пар ≈ 135 м
const FOOT_CAPACITY := 200
const RESIDENT_CAPACITY := 320
const RESIDENT_RANGE := 32.0
const RESIDENT_KEEP_RANGE := 12.0
const RESIDENT_SLOT_SEARCH := 32
const RESIDENT_STAMPS_PER_FRAME := 3
const TYRE_STEP := 0.45       # м между отрезками колеи
const FOOT_STEP := 0.75       # м между шагами, как у звука шагов (SoundDirector)
const TYRE_WIDTH := 0.30
const FOOT_SIZE := Vector2(0.13, 0.26)
const TINT := Color(0.30, 0.31, 0.34, 0.5)   # притоптанный серый снег
const REAR_WHEELS := [Vector3(-0.78, 0, 1.25), Vector3(0.78, 0, 1.25)]   # в осях машины, перед — −Z
const LIFT := 0.025           # над тропинками (0,018) и тротуарами (0,015)

var world: DemoWorld
var _tyres: MultiMesh
var _feet: MultiMesh
var _resident_feet: MultiMesh
var _resident_marks: Array[Vector3] = []
var _resident_next := 0
var _residents: Array = []
var _resident_last := {}
var _resident_side := {}
var _nonsnow_patches: Array[Transform3D] = []
var _ice_areas: Array[Rect2] = []
var _tyre_next := 0
var _foot_next := 0
var _count := 0     # сколько отпечатков поставлено (для проверок)
var _car_last := Vector3.INF
var _wheels_last: Array[Vector3] = []
var _foot_last := Vector3.INF
var _foot_side := 1.0

func _ready() -> void:
	world = get_parent() as DemoWorld
	# Колея: мягкие края поперёк, вдоль — ровно, чтобы отрезки ленты сходились без шва.
	var across := Gradient.new()
	across.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	across.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var tyre_tex := GradientTexture2D.new()
	tyre_tex.gradient = across
	tyre_tex.width = 32
	tyre_tex.height = 4
	_tyres = _multimesh("Tyres", TYRE_CAPACITY, tyre_tex)
	# Шаг: мягкий овал — круглое пятно, растянутое размером отпечатка.
	var blob := Gradient.new()
	blob.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	blob.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var foot_tex := GradientTexture2D.new()
	foot_tex.gradient = blob
	foot_tex.fill = GradientTexture2D.FILL_RADIAL
	foot_tex.fill_from = Vector2(0.5, 0.5)
	foot_tex.fill_to = Vector2(1.0, 0.5)
	foot_tex.width = 32
	foot_tex.height = 32
	_feet = _multimesh("Feet", FOOT_CAPACITY, foot_tex)
	_resident_feet = _multimesh("ResidentFeet", RESIDENT_CAPACITY, foot_tex)
	_resident_feet.mesh.material = _feet.mesh.material
	_resident_marks.resize(RESIDENT_CAPACITY)
	_resident_marks.fill(Vector3.INF)
	_collect_resident_ground()
	var residents := world.get_node_or_null("LevelGeometry/Residents")
	if residents:
		_residents = residents.residents.duplicate()

func _collect_resident_ground() -> void:
	var rink: Vector2 = Layout.RINK[0]
	var size: Vector3 = Layout.RINK[1]
	_ice_areas.append(Rect2(rink - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)))
	var slide_width := 0.0
	for spec in Layout.PROPS_SOLIDS:
		if spec[0] in ["PropIceSlide", "PropIceSlideRamp"]:
			var center: Vector2 = spec[2]
			var footprint := Vector2(spec[3].x, spec[3].z)
			_ice_areas.append(Rect2(center - footprint * 0.5, footprint))
			slide_width = maxf(slide_width, footprint.x)
	var top: Array = Layout.LIFE_SLIDE_LOOP[2]
	var bottom: Array = Layout.LIFE_SLIDE_LOOP[4]
	_ice_areas.append(Rect2(float(top[0]) - slide_width * 0.5, float(bottom[1]), slide_width, float(top[1]) - float(bottom[1])))
	# Только готовые пакеты покрытий Environment; обхода остальной сцены и повторного поиска в кадре нет.
	var environment := world.get_node_or_null("LevelGeometry/Environment")
	if environment:
		for node in environment.get_children():
			if not node is MultiMeshInstance3D or not String(node.name).begins_with("EnvNear_patch_"):
				continue
			for i in node.multimesh.instance_count:
				var transform: Transform3D = node.global_transform * node.multimesh.get_instance_transform(i)
				_nonsnow_patches.append(transform.affine_inverse())

func _multimesh(node_name: String, capacity: int, texture: Texture2D) -> MultiMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var look := StandardMaterial3D.new()
	look.albedo_color = TINT
	look.albedo_texture = texture
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.roughness = 0.9
	plane.material = look
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = capacity
	# Все экземпляры видимы; ещё не поставленные — нулевого размера под землёй.
	for i in capacity:
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -10, 0)))
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-150, -1, -150), Vector3(300, 3, 300))
	# Отпечатки неподвижны: интерполяция физики (включена в проекте) им не нужна.
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(instance)
	return mm

func _physics_process(_delta: float) -> void:
	if not world:
		return
	var car := world.car
	var at := car.global_position
	if world.control_mode == &"in_car" and car.is_on_floor():
		if _car_last == Vector3.INF or _flat(at - _car_last) > 2.0:
			_car_last = at   # первый кадр или телепорт (сброс машины)
			_wheels_last = _rear_wheels(car)
		elif _flat(at - _car_last) >= TYRE_STEP:
			var wheels := _rear_wheels(car)
			for i in wheels.size():
				_stamp_tyre(_wheels_last[i], wheels[i])
			_wheels_last = wheels
			_car_last = at
	else:
		_car_last = Vector3.INF
	var player := world.player
	var feet := player.global_position
	if world.control_mode == &"on_foot" and player.is_on_floor():
		if _foot_last == Vector3.INF or _flat(feet - _foot_last) > 2.0:
			_foot_last = feet
		elif _flat(feet - _foot_last) >= FOOT_STEP:
			var heading := atan2(-(feet.x - _foot_last.x), -(feet.z - _foot_last.z))
			var side := Vector3(cos(heading), 0, -sin(heading)) * 0.14 * _foot_side
			_stamp_foot(feet + side, heading)
			_foot_side = -_foot_side
			_foot_last = feet
	else:
		_foot_last = Vector3.INF
	_stamp_residents()

func _stamp_residents() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var budget := RESIDENT_STAMPS_PER_FRAME
	for cached in _residents:
		if not is_instance_valid(cached):
			continue
		var resident: Resident = cached
		var at := resident.global_position
		var seated: bool = resident._acting and resident._act_sit != 0.0
		var skating: bool = resident._acting and resident._act_kind in [&"slide", &"hockey"]
		if not resident.is_visible_in_tree() or resident.hidden or resident.state == &"knocked" or seated or skating or absf(at.y) > 0.12 or absf(resident.visual.position.y) > 0.25 or at.distance_squared_to(camera.global_position) > RESIDENT_RANGE * RESIDENT_RANGE:
			_resident_last.erase(resident)
			continue
		var last: Vector3 = _resident_last.get(resident, Vector3.INF)
		if last == Vector3.INF or _flat(at - last) > 2.0:
			_resident_last[resident] = at
			continue
		if _flat(at - last) < FOOT_STEP or budget <= 0:
			continue
		var heading := atan2(-(at.x - last.x), -(at.z - last.z))
		var side: float = _resident_side.get(resident, 1.0)
		var point := at + Vector3(cos(heading), 0, -sin(heading)) * 0.14 * side
		if _resident_snow(point):
			_stamp_foot(point, heading, true)
			budget -= 1
		_resident_last[resident] = at
		_resident_side[resident] = -side

func _resident_snow(point: Vector3) -> bool:
	if _on_road(point) or SnowField.height_at(point.x, point.z) > 0.06:
		return false
	var flat := Vector2(point.x, point.z)
	for area in _ice_areas:
		if area.has_point(flat):
			return false
	for inverse in _nonsnow_patches:
		var local := inverse * point
		if absf(local.x) <= 0.6 and absf(local.z) <= 0.6:
			return false
	return true

func _resident_slot() -> int:
	var camera := get_viewport().get_camera_3d()
	for offset in RESIDENT_SLOT_SEARCH:
		var slot := (_resident_next + offset) % RESIDENT_CAPACITY
		var point := _resident_marks[slot]
		var reusable := point == Vector3.INF
		if not reusable and camera:
			var distance := point.distance_squared_to(camera.global_position)
			reusable = distance > RESIDENT_RANGE * RESIDENT_RANGE or (distance > RESIDENT_KEEP_RANGE * RESIDENT_KEEP_RANGE and not camera.is_position_in_frustum(point))
		if reusable:
			_resident_next = (slot + 1) % RESIDENT_CAPACITY
			return slot
	_resident_next = (_resident_next + RESIDENT_SLOT_SEARCH) % RESIDENT_CAPACITY
	return -1

func _rear_wheels(car: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for wheel in REAR_WHEELS:
		out.append(car.global_transform * wheel)
	return out

## Отрезок колеи от прошлого положения колеса до нового.
func _stamp_tyre(from: Vector3, to: Vector3) -> void:
	# Оба конца, а не середина: иначе отрезок у края заходит на проезжую часть.
	if _on_road(from) or _on_road(to):
		return
	var mid := (from + to) * 0.5
	var d := to - from
	var basis := Basis(Vector3.UP, atan2(d.x, d.z)) * Basis.from_scale(Vector3(TYRE_WIDTH, 1.0, _flat(d)))
	_tyres.set_instance_transform(_tyre_next, Transform3D(basis, Vector3(mid.x, LIFT, mid.z)))
	_tyre_next = (_tyre_next + 1) % TYRE_CAPACITY
	_count += 1

func _stamp_foot(point: Vector3, yaw: float, resident := false) -> void:
	if _on_road(point):
		return
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(FOOT_SIZE.x, 1.0, FOOT_SIZE.y))
	var stamp := Transform3D(basis, Vector3(point.x, LIFT, point.z))
	if resident:
		var slot := _resident_slot()
		if slot < 0:
			return
		_resident_feet.set_instance_transform(slot, stamp)
		_resident_marks[slot] = stamp.origin
	else:
		_feet.set_instance_transform(_foot_next, stamp)
		_foot_next = (_foot_next + 1) % FOOT_CAPACITY
	_count += 1

## Проезжая часть: Layout.SURFACES вида road (C1).
static func _on_road(point: Vector3) -> bool:
	for spec in Layout.SURFACES:
		if spec[1] != "road":
			continue
		var c: Vector2 = spec[2]
		var s: Vector2 = spec[3]
		if absf(point.x - c.x) < s.x * 0.5 and absf(point.z - c.y) < s.y * 0.5:
			return true
	return false

static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
