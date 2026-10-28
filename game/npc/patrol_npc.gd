extends "res://game/npc/npc.gd"
## Патрульный полицейский (EXT-01 N, STEALTH_DESIGN «Наблюдатели»): стоит на посту и каждые TURN_EVERY с
## плавно (TURN_SECONDS) разворачивает корпус на следующий угол из facings; дочерний DetectionSensor (C7)
## смотрит туда же, куда корпус. move_post(point) — переход на новый пост шагом MOVE_SPEED (этап 7: после
## покупки хлеба): на переходе сенсор выключен и конус скрыт — идущий патруль не «смотрит» (приёмка 28.10, P1),
## на новом посту доворачивается на текущий угол из facings и включает сенсор. Облик, тело, дыхание и зона E —
## npc.gd; на время диалога смотрит на Илюшу (look_at_target).
## EXT-01 fix2 (P2-3, этап 5 «может спокойно уйти, если быстро завершит диалог»): после диалога QuestFlow зовёт
## turn_away_from(Илюша, grace) — сразу разворот на угол из facings, в котором Илюши нет, таймер разворотов заново.
## Если по истечении grace Илюша всё ещё стоит рядом (LINGER_RADIUS), полицейский поворачивается к нему и смотрит,
## пока тот не отойдёт: дальше видит сенсор — провал через 2 с. can_talk_to(target) — Илюша не за спиной (P3).
## EXT-01 fix4 (четвёртая приёмка P3: после диалога разворачивался на юг, куда Илюша уходит к парковке): из углов, в
## конусе которых Илюши нет, — тот, что дальше от направления на away_point (парковка); если Илюша во всех — дальше всего
## от Илюши.
## fix4: avoid_yaw — угол корпуса, через который разворот не проходит (второй пост: окно киоска на юге; кратчайший путь
## между западом и востоком-юго-востоком шёл через юг и на 0,3 с открывал окно): разворот идёт длинной дугой, время —
## TURN_SECONDS на каждые 90° (не меньше TURN_SECONDS).

const DetectionSensorScript = preload("res://game/stealth/detection_sensor.gd")

## Углы корпуса в осях узла (yaw: 0 — на север), по кругу.
@export var facings: Array = [0.0]
@export var turn_every := Vector2(3.0, 4.0)   # с между разворотами, случайно в этих границах
@export var sensor_range := 9.0
@export var sensor_fov := 75.0
## Куда уходит Илюша после диалога (парковка): turn_away_from не выбирает угол, смотрящий туда. INF — не учитывать.
@export var away_point := Vector3.INF
## Угол корпуса (в осях узла), через который не разворачиваться; NAN — кратчайшим путём (fix4).
@export var avoid_yaw := NAN

const TURN_SECONDS := 0.6
const MOVE_SPEED := 1.5
const LOOK_SPEED := 6.0   # доворот к собеседнику, 1/с (как у npc.gd)
const TALK_ANGLE := 100.0      # град от направления корпуса: дальше — «за спиной», подсказки E нет
const LINGER_RADIUS := 3.5     # м: после диалога ближе этого — «не ушёл» (зона E 2,5 м + зонд Илюши 0,5 м + запас)

var sensor: Node3D
var _facing_index := 0
var _turn_from := 0.0
var _turn_to := 0.0
var _turn_t := 1.0        # 0…1 — идёт разворот
var _turn_delta := 0.0    # дуга разворота, рад (со знаком; fix4 — может быть длинной)
var _turn_time := TURN_SECONDS
var _wait_left := 0.0
var _move_target := Vector3.INF
var _linger_target: Node3D
var _linger_left := 0.0
var _watching := false     # после диалога Илюша не ушёл — смотрим на него
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
	_update_linger(delta)
	if is_instance_valid(_look_target):
		# Диалог (или Илюша задержался после него): корпус к Илюше, таймер разворотов стоит.
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
			_turn_t = minf(_turn_t + delta / _turn_time, 1.0)
			var k := smoothstep(0.0, 1.0, _turn_t)
			visual.rotation.y = _turn_from + _turn_delta * k
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
		# Пришёл: доворот на текущий угол поста, затем обычный цикл разворотов; сенсор снова смотрит.
		_turn_from = visual.rotation.y
		_turn_to = float(facings[_facing_index])
		_start_turn()
		_wait_left = _rng.randf_range(turn_every.x, turn_every.y)
		sensor.enabled = true
		return
	global_position += to.normalized() * step

func _next_facing() -> void:
	_facing_index = (_facing_index + 1) % facings.size()
	_turn_from = visual.rotation.y
	_turn_to = float(facings[_facing_index])
	_start_turn()
	_wait_left = _rng.randf_range(turn_every.x, turn_every.y)

## После диалога (P2-3, fix4): сразу на угол из facings без target в конусе — из таких дальше всего от away_point;
## если target во всех — дальше всего от target. Таймер разворотов заново; grace с — время уйти. Позже — _update_linger.
func turn_away_from(target: Node3D, grace: float) -> void:
	_look_target = null
	_watching = false
	_linger_target = target
	_linger_left = grace
	if not is_instance_valid(target) or facings.is_empty():
		return
	_facing_index = away_facing(target.global_position)
	_turn_from = visual.rotation.y
	_turn_to = float(facings[_facing_index])
	_start_turn()
	_wait_left = _rng.randf_range(turn_every.x, turn_every.y)

func _update_linger(delta: float) -> void:
	if not is_instance_valid(_linger_target):
		_linger_target = null
		return
	var near := _flat_distance(_linger_target) <= LINGER_RADIUS
	if _watching:
		if not near:
			# Отошёл: перестать смотреть, снова на угол без него.
			var target := _linger_target
			turn_away_from(target, 0.0)
			_linger_target = null
		return
	_linger_left -= delta
	if _linger_left > 0.0:
		return
	if near:
		_watching = true
		_look_target = _linger_target
	else:
		_linger_target = null

## Илюша задержался после диалога, полицейский смотрит на него (для тестов).
func is_watching() -> bool:
	return _watching

## Можно ли заговорить: target не за спиной — угол от направления корпуса не больше TALK_ANGLE.
func can_talk_to(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return true
	if is_instance_valid(_look_target):
		return true
	return _angle_to(target, visual.rotation.y) <= TALK_ANGLE

## Начать разворот _turn_from → _turn_to: кратчайшей дугой, если она не проходит через avoid_yaw, иначе длинной (fix4).
func _start_turn() -> void:
	var d := wrapf(_turn_to - _turn_from, -PI, PI)
	if not is_nan(avoid_yaw) and absf(d) > 0.001:
		var a := wrapf(avoid_yaw - _turn_from, -PI, PI)
		if signf(a) == signf(d) and absf(a) < absf(d):
			d -= signf(d) * TAU
	_turn_delta = d
	_turn_time = TURN_SECONDS * maxf(1.0, absf(d) / (PI * 0.5))
	_turn_t = 0.0

## Номер угла facings для разворота от точки p (fix4): без p в конусе (угол > половины обзора) и дальше всего от
## away_point; если p во всех конусах — дальше всего от p.
func away_facing(p: Vector3) -> int:
	var best := -1
	var best_angle := -1.0
	for i in facings.size():
		var yaw := float(facings[i])
		var off := _angle_to_point(p, yaw)
		if off <= sensor_fov * 0.5:
			continue
		var angle := _angle_to_point(away_point, yaw) if away_point != Vector3.INF else off
		if angle > best_angle:
			best_angle = angle
			best = i
	if best >= 0:
		return best
	best = _facing_index
	for i in facings.size():
		var off := _angle_to_point(p, float(facings[i]))
		if off > best_angle:
			best_angle = off
			best = i
	return best

## Угол (град) между направлением корпуса при yaw (в осях узла) и направлением на target в плоскости XZ.
func _angle_to(target: Node3D, yaw: float) -> float:
	return _angle_to_point(target.global_position, yaw)

func _angle_to_point(p: Vector3, yaw: float) -> float:
	var to := p - global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() < 0.01:
		return 0.0
	var world_yaw := yaw + global_rotation.y
	return rad_to_deg(absf(Vector2(-sin(world_yaw), -cos(world_yaw)).angle_to(flat)))

func _flat_distance(target: Node3D) -> float:
	var to := target.global_position - global_position
	return Vector2(to.x, to.z).length()

## Перейти на новый пост (этап 7): шагом MOVE_SPEED, лицом по ходу, сенсор выключен до прихода; на месте — снова
## разворачивается по facings.
func move_post(point: Vector3) -> void:
	_move_target = Vector3(point.x, 0.0, point.z)
	sensor.enabled = false

func is_moving() -> bool:
	return _move_target != Vector3.INF

## Встать на пост сразу (перезапуск, тесты): без перехода, с первым углом facings, сенсор включён.
func place_at(point: Vector3) -> void:
	_move_target = Vector3.INF
	_linger_target = null
	_watching = false
	_look_target = null
	global_position = Vector3(point.x, global_position.y, point.z)
	_facing_index = 0
	_turn_from = float(facings[0])
	_turn_to = _turn_from
	_turn_t = 1.0
	visual.rotation.y = _turn_from
	_wait_left = _rng.randf_range(turn_every.x, turn_every.y)
	sensor.enabled = true

## Идёт плавный разворот корпуса (между углами facings).
func is_turning() -> bool:
	return _turn_t < 1.0

## Номер текущего (или целевого, если идёт разворот) угла в facings.
func facing_index() -> int:
	return _facing_index

## Текущий угол корпуса в осях узла (для тестов).
func body_yaw() -> float:
	return visual.rotation.y
