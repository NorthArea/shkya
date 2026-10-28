extends "res://game/npc/npc.gd"
## Патрульный полицейский (EXT-01 N, STEALTH_DESIGN «Наблюдатели»): стоит на посту и каждые TURN_EVERY с
## плавно (TURN_SECONDS) разворачивает корпус на следующий угол из facings; дочерний DetectionSensor (C7)
## смотрит туда же, куда корпус. move_post(point) — переход на новый пост шагом MOVE_SPEED (этап 7: после
## покупки хлеба). Облик, тело, дыхание и зона E — npc.gd; на время диалога смотрит на Илюшу (look_at_target).

const DetectionSensorScript = preload("res://game/stealth/detection_sensor.gd")

## Углы корпуса в осях узла (yaw: 0 — на север), по кругу.
@export var facings: Array = [0.0]
@export var turn_every := Vector2(3.0, 4.0)   # с между разворотами, случайно в этих границах
@export var sensor_range := 9.0
@export var sensor_fov := 75.0

const TURN_SECONDS := 0.6
const MOVE_SPEED := 1.5
const LOOK_SPEED := 6.0   # доворот к собеседнику, 1/с (как у npc.gd)

var sensor: Node3D
var _facing_index := 0
var _turn_from := 0.0
var _turn_to := 0.0
var _turn_t := 1.0        # 0…1 — идёт разворот
var _wait_left := 0.0
var _move_target := Vector3.INF
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	super()
	_rng.seed = String(interaction_id).hash()
	if facings.is_empty():
		facings = [facing_yaw]
	_turn_from = float(facings[0])
	_turn_to = _turn_from
	facing_yaw = _turn_from
	visual.rotation.y = _turn_from
	_wait_left = _rng.randf_range(turn_every.x, turn_every.y)
	sensor = DetectionSensorScript.new()
	sensor.name = "DetectionSensor"
	sensor.range_m = sensor_range
	sensor.fov_deg = sensor_fov
	sensor.rotation.y = _turn_from
	add_child(sensor)

func _process(delta: float) -> void:
	_breath_time += delta
	var s := sin(_breath_time * TAU / BREATH_PERIOD)
	visual.scale = Vector3(1.0 - s * BREATH * 0.5, 1.0 + s * BREATH, 1.0)
	if is_instance_valid(_look_target):
		# Диалог: корпус к Илюше, таймер разворотов стоит.
		var to := _look_target.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.3:
			var wanted := atan2(-to.x, -to.z) - global_rotation.y
			visual.rotation.y = lerp_angle(visual.rotation.y, wanted, 1.0 - exp(-LOOK_SPEED * delta))
	elif _move_target != Vector3.INF:
		var to := _move_target - global_position
		to.y = 0.0
		if to.length() > 0.001:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-to.x, -to.z) - global_rotation.y, 1.0 - exp(-LOOK_SPEED * delta))
	else:
		if _turn_t < 1.0:
			_turn_t = minf(_turn_t + delta / TURN_SECONDS, 1.0)
			var k := smoothstep(0.0, 1.0, _turn_t)
			visual.rotation.y = lerp_angle(_turn_from, _turn_to, k)
		else:
			_wait_left -= delta
			if _wait_left <= 0.0:
				_next_facing()
	facing_yaw = visual.rotation.y
	sensor.rotation.y = visual.rotation.y

func _physics_process(delta: float) -> void:
	if _move_target == Vector3.INF:
		return
	var to := _move_target - global_position
	to.y = 0.0
	var step := MOVE_SPEED * delta
	if to.length() <= step:
		global_position = Vector3(_move_target.x, global_position.y, _move_target.z)
		_move_target = Vector3.INF
		_turn_from = visual.rotation.y
		_turn_t = 1.0
		_wait_left = _rng.randf_range(turn_every.x, turn_every.y) * 0.5
		return
	global_position += to.normalized() * step

func _next_facing() -> void:
	_facing_index = (_facing_index + 1) % facings.size()
	_turn_from = visual.rotation.y
	_turn_to = float(facings[_facing_index])
	_turn_t = 0.0
	_wait_left = _rng.randf_range(turn_every.x, turn_every.y)

## Перейти на новый пост (этап 7): шагом MOVE_SPEED, лицом по ходу; на месте — снова разворачивается по facings.
func move_post(point: Vector3) -> void:
	_move_target = Vector3(point.x, 0.0, point.z)

func is_moving() -> bool:
	return _move_target != Vector3.INF

## Текущий угол корпуса в осях узла (для тестов).
func body_yaw() -> float:
	return visual.rotation.y
