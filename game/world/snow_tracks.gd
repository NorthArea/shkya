extends Node3D
## Следы на снегу (PLAY-03): колея задних колёс «Лады» и шаги Илюши на снегу, тротуарах и во дворе.
## На проезжей части следов нет: там свои колеи (road.gdshader). Только облик, на игру не влияет.
## Один MultiMesh — кольцевой буфер: новые отпечатки замещают самые старые.

const Layout = preload("res://game/world/layout.gd")

const CAPACITY := 800
const TYRE_STEP := 0.45       # м между отпечатками колеса
const FOOT_STEP := 0.75       # м между шагами, как у звука шагов (SoundDirector)
const TYRE_SIZE := Vector2(0.22, 0.55)
const FOOT_SIZE := Vector2(0.13, 0.26)
const REAR_WHEELS := [Vector3(-0.78, 0, 1.25), Vector3(0.78, 0, 1.25)]   # в осях машины, перед — −Z
const LIFT := 0.025           # над тропинками (0,018) и тротуарами (0,015)

var world: DemoWorld
var _mm: MultiMesh
var _next := 0
var _count := 0     # сколько отпечатков поставлено (для проверок)
var _car_last := Vector3.INF
var _foot_last := Vector3.INF
var _foot_side := 1.0

func _ready() -> void:
	world = get_parent() as DemoWorld
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var look := StandardMaterial3D.new()
	look.albedo_color = Color(0.30, 0.31, 0.34, 0.5)   # притоптанный серый снег
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.roughness = 0.9
	plane.material = look
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = plane
	_mm.instance_count = CAPACITY
	# Все экземпляры видимы; ещё не поставленные — нулевого размера под землёй.
	for i in CAPACITY:
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -10, 0)))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Prints"
	instance.multimesh = _mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-150, -1, -150), Vector3(300, 3, 300))
	# Отпечатки неподвижны: интерполяция физики (включена в проекте) им не нужна.
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(instance)

func _physics_process(_delta: float) -> void:
	if not world:
		return
	var car := world.car
	var at := car.global_position
	if world.control_mode == &"in_car" and car.is_on_floor():
		if _car_last == Vector3.INF or _flat(at - _car_last) > 2.0:
			_car_last = at   # первый кадр или телепорт (сброс машины)
		elif _flat(at - _car_last) >= TYRE_STEP:
			for wheel in REAR_WHEELS:
				_stamp(car.global_transform * wheel, car.global_rotation.y, TYRE_SIZE)
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
			_stamp(feet + side, heading, FOOT_SIZE)
			_foot_side = -_foot_side
			_foot_last = feet
	else:
		_foot_last = Vector3.INF

func _stamp(point: Vector3, yaw: float, size: Vector2) -> void:
	if _on_road(point):
		return
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(size.x, 1.0, size.y))
	_mm.set_instance_transform(_next, Transform3D(basis, Vector3(point.x, LIFT, point.z)))
	_next = (_next + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)

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
