extends Node3D
## Следы на снегу (PLAY-03): колея задних колёс «Лады» и шаги Илюши на снегу, тротуарах и во дворе.
## На проезжей части следов нет: там свои колеи (road.gdshader). Только облик, на игру не влияет.
## Два MultiMesh — колея и шаги, каждый кольцевой буфер: новые отпечатки замещают самые старые.
## Колея — лента из отрезков от прошлого положения колеса до нового: без стыков и разрывов на любой скорости.

const Layout = preload("res://game/world/layout.gd")

const TYRE_CAPACITY := 600   # отрезков колеи: 300 пар ≈ 135 м
const FOOT_CAPACITY := 200
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

func _rear_wheels(car: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for wheel in REAR_WHEELS:
		out.append(car.global_transform * wheel)
	return out

## Отрезок колеи от прошлого положения колеса до нового.
func _stamp_tyre(from: Vector3, to: Vector3) -> void:
	var mid := (from + to) * 0.5
	if _on_road(mid):
		return
	var d := to - from
	var basis := Basis(Vector3.UP, atan2(d.x, d.z)) * Basis.from_scale(Vector3(TYRE_WIDTH, 1.0, _flat(d)))
	_tyres.set_instance_transform(_tyre_next, Transform3D(basis, Vector3(mid.x, LIFT, mid.z)))
	_tyre_next = (_tyre_next + 1) % TYRE_CAPACITY
	_count += 1

func _stamp_foot(point: Vector3, yaw: float) -> void:
	if _on_road(point):
		return
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(FOOT_SIZE.x, 1.0, FOOT_SIZE.y))
	_feet.set_instance_transform(_foot_next, Transform3D(basis, Vector3(point.x, LIFT, point.z)))
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
