class_name Resident
extends "res://game/npc/npc.gd"
## Житель города Н. (PEOPLE-01, часть B): ходит по замкнутому маршруту из точек (Layout.RESIDENT_*, C1)
## со скоростью SPEEDS[index], на отмеченных точках стоит PAUSES[index] с. Илюша ближе NOTICE_DISTANCE — житель
## останавливается на STARE_SECONDS и смотрит на него (look_at_target из npc.gd), потом идёт дальше; пока Илюша
## не отошёл дальше RELEASE_DISTANCE, второй раз не останавливается. Илюша прямо по ходу ближе BLOCK_DISTANCE — ждёт.
## Тело — AnimatableBody3D на слое Car (3-й, значение 4), маска 0: Илюша (маска World|Car) упирается в него и
## обходит, не толкает; транспорт кольца (датчик World|Player|Car) тормозит; луч наблюдателей (DetectionSensor,
## WORLD_MASK = 1) и пружина камеры (маска 1) его не видят — житель не укрытие (C7). «Лада» (маска World) сквозь
## тело проходит: при касании житель встаёт на ближайшую свободную точку маршрута (place), без рэгдолла; «Лада»
## стоит поперёк пути — житель разворачивается. Без случайностей: всё задаётся индексом и маршрутом.

const SPEEDS: Array[float] = [1.2, 1.45, 1.35, 1.6, 1.3, 1.25, 1.5, 1.4]    # м/с, 1,2–1,6
const PAUSES: Array[float] = [4.0, 2.5, 3.5, 2.0, 3.0, 4.5, 2.5, 5.0]        # с, 2–5
const NOTICE_DISTANCE := 3.0
const RELEASE_DISTANCE := 4.0
const STARE_SECONDS := 2.0
const BLOCK_DISTANCE := 1.5
const BODY_LAYER := 4          # Car
const BODY_RADIUS := 0.35
const BODY_HEIGHT := 1.7
const LADA_MARGIN := 0.1       # м сверх габарита «Лады» и радиуса тела — касание
const LADA_CLEAR := 1.0        # м от габарита «Лады» до точки, куда встаёт житель
const LADA_LOOKAHEAD := 0.9    # м впереди по ходу: «Лада» там — разворот
const REVERSE_COOLDOWN := 2.0

@export var index := 0
var route: Array = []          # Vector3, замкнутая ломаная
var pause_points: Array = []   # индексы точек с паузой
var start_point := 0
var speed := 1.3
var pause_seconds := 3.0
## Илюша и «Лада» — задаёт Residents (в отдельном тесте могут быть null).
var player: Node3D
var lada: Node3D

var body: AnimatableBody3D
var state: StringName = &"walk"    # walk, pause, stare
var target_point := 0
var direction := 1
var distance_walked := 0.0
var stare_count := 0
var lada_bumps := 0
var turnarounds := 0
var _wait := 0.0
var _resume_state: StringName = &"walk"
var _resume_wait := 0.0
var _met := false
var _reverse_cooldown := 0.0

func setup(resident_index: int, points: Array, pauses: Array, start: int) -> void:
	index = resident_index
	route = points
	pause_points = pauses
	start_point = start
	speed = SPEEDS[index % SPEEDS.size()]
	pause_seconds = PAUSES[index % PAUSES.size()]
	interaction_id = StringName("resident_%d" % index)   # только для фазы дыхания npc.gd; зона E выключена

func _ready() -> void:
	solid = false   # своё тело ниже: не StaticBody на слое World, как у npc.gd
	body_radius = BODY_RADIUS
	if not route.is_empty():
		position = _flat(route[start_point])
		target_point = _wrap(start_point + 1)
		facing_yaw = _yaw_to(route[target_point])
	super()
	interactable.enabled = false
	interactable.prompt = ""
	interactable.monitorable = false
	body = AnimatableBody3D.new()
	body.name = "Body"
	body.collision_layer = BODY_LAYER
	body.collision_mask = 0
	body.sync_to_physics = false
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = BODY_HEIGHT * 0.5
	body.add_child(collider)
	add_child(body)

func _physics_process(delta: float) -> void:
	if route.size() < 2 or delta <= 0.0:
		return
	_reverse_cooldown = maxf(_reverse_cooldown - delta, 0.0)
	if _lada_touches(global_position, LADA_MARGIN):
		_dodge_lada()
		return
	var to_player := _player_distance()
	if to_player > RELEASE_DISTANCE:
		_met = false
	if state == &"stare":
		_wait -= delta
		if _wait <= 0.0:
			_met = true
			stop_looking()
			state = _resume_state
			_wait = _resume_wait
		return
	if to_player < NOTICE_DISTANCE and not _met:
		_resume_state = state
		_resume_wait = _wait
		state = &"stare"
		_wait = STARE_SECONDS
		stare_count += 1
		look_at_target(player)
		return
	if state == &"pause":
		_wait -= delta
		if _wait <= 0.0:
			state = &"walk"
			target_point = _wrap(target_point + direction)
		return
	_walk(delta, to_player)

func _walk(delta: float, to_player: float) -> void:
	var here := _flat(global_position)
	var goal := _flat(route[target_point])
	var to := goal - here
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else Vector3.ZERO
	if dir != Vector3.ZERO:
		facing_yaw = atan2(-dir.x, -dir.z)
	# Илюша прямо по ходу: стоим и смотрим, пока не отойдёт (он обходит, житель в него не входит).
	if to_player < BLOCK_DISTANCE and dir != Vector3.ZERO:
		var to_him := _flat(player.global_position) - here
		if to_him.length() < 0.01 or dir.dot(to_him.normalized()) > 0.3:
			look_at_target(player)
			return
	if _look_target == player and to_player >= BLOCK_DISTANCE:
		stop_looking()
	# «Лада» стоит поперёк пути: разворот к предыдущей точке.
	if dir != Vector3.ZERO and _lada_touches(here + dir * LADA_LOOKAHEAD, LADA_MARGIN):
		if _reverse_cooldown <= 0.0:
			direction = -direction
			target_point = _wrap(target_point + direction)
			_reverse_cooldown = REVERSE_COOLDOWN
			turnarounds += 1
		return
	var step := speed * delta
	if dist <= step:
		global_position = goal
		distance_walked += dist
		if pause_points.has(target_point):
			state = &"pause"
			_wait = pause_seconds
		else:
			target_point = _wrap(target_point + direction)
		return
	global_position = here + dir * step
	distance_walked += step

## Поставить на точку маршрута (касание «Лады», перезапуск): без скорости и без интерполяции рывка.
func place(point: Vector3) -> void:
	global_position = _flat(point)
	reset_physics_interpolation()

## Перезапуск: на старт, к следующей точке, счётчики — с нуля.
func reset_to_start() -> void:
	state = &"walk"
	direction = 1
	_met = false
	_wait = 0.0
	_reverse_cooldown = 0.0
	stop_looking()
	target_point = _wrap(start_point + 1)
	place(route[start_point])
	facing_yaw = _yaw_to(route[target_point])
	distance_walked = 0.0

## Длина замкнутого маршрута, м.
func loop_length() -> float:
	var total := 0.0
	for i in route.size():
		total += _flat(route[i]).distance_to(_flat(route[_wrap(i + 1)]))
	return total

## «Лада» задела: на ближайшую точку маршрута (шаг 0,5 м), свободную от её габарита на LADA_CLEAR, и дальше — от неё.
func _dodge_lada() -> void:
	var here := _flat(global_position)
	var best := Vector3.INF
	var best_d := INF
	var best_seg := -1
	for k in route.size():
		var a := _flat(route[k])
		var b := _flat(route[_wrap(k + 1)])
		var n := maxi(1, ceili(a.distance_to(b) / 0.5))
		for j in n + 1:
			var p := a.lerp(b, float(j) / n)
			if _lada_touches(p, LADA_CLEAR):
				continue
			var d := p.distance_to(here)
			if d < best_d:
				best_d = d
				best = p
				best_seg = k
	lada_bumps += 1
	stop_looking()
	state = &"walk"
	if best_seg < 0:
		direction = 1
		target_point = _wrap(start_point + 1)
		place(route[start_point])
		return
	place(best)
	var away := best - _flat(lada.global_position)
	if (_flat(route[_wrap(best_seg + 1)]) - best).dot(away) >= 0.0:
		direction = 1
		target_point = _wrap(best_seg + 1)
	else:
		direction = -1
		target_point = best_seg

## Точка p (XZ) ближе margin + BODY_RADIUS к габариту «Лады».
func _lada_touches(p: Vector3, margin: float) -> bool:
	if not is_instance_valid(lada):
		return false
	var local := lada.global_transform.affine_inverse() * Vector3(p.x, lada.global_position.y, p.z)
	var half := Lada.SIZE * 0.5
	return absf(local.x) < half.x + BODY_RADIUS + margin and absf(local.z) < half.z + BODY_RADIUS + margin

func _player_distance() -> float:
	if not is_instance_valid(player) or not player.is_visible_in_tree():
		return INF
	var p := player.global_position
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

func _wrap(i: int) -> int:
	return posmod(i, route.size())

func _yaw_to(point: Vector3) -> float:
	var to := _flat(point) - _flat(position)
	return atan2(-to.x, -to.z) if to.length() > 0.001 else facing_yaw

static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)
