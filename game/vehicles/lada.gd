class_name Lada
extends CharacterBody3D
## Белая «Лада» (DRIVE-01): аркадная езда на CharacterBody3D, вход и выход по E (C4).
## Модель: продольная скорость от газа/тормоза, поворот зависит от скорости,
## боковая скорость гасится сцеплением — на мокрой дороге остаётся лёгкий занос, ручник его усиливает.

signal driver_entered(driver: Node3D)
signal driver_exited(driver: Node3D)

const Greybox = preload("res://game/world/greybox.gd")
const InteractableScript = preload("res://game/interaction/interactable.gd")
const LadaVisual = preload("res://game/vehicles/lada_visual.gd")

const SIZE := Vector3(1.7, 1.4, 4.1)
## Темп по замеру эталона PLAY-01 (G02, G03): потолок 28 м/с ≈ 100 км/ч, разгон спадает к максимуму
## (0→20 м/с ≈ 2,8 с, как у G02), радиусы поворота в метрах — как у G02 (PLAY-02).
const MAX_SPEED := 28.0         # м/с ≈ 100 км/ч
const MAX_REVERSE := 10.0
const ACCELERATION := 9.0       # м/с² с места; к максимуму спадает как 1 − (v/MAX_SPEED)²
const REVERSE_ACCEL := 0.9      # доля ACCELERATION на заднем ходу
const BRAKE := 24.0             # 18→0 м/с за ~0,75 с, как у эталона (повторная сверка PLAY-02)
const ROLL_DRAG := 2.0          # накат PLAY-01 P3 (1,2) не взят: машина катилась бы 145 м
const AIR_DRAG := 0.004         # ·v²: на скорости накат короче (повторная сверка PLAY-02, P3)
const HANDBRAKE := 8.0
const HANDBRAKE_TURN := 1.4     # ручник докручивает машину
const GRIP := 7.0               # мокрая дорога: боковая скорость гасится не мгновенно
const HANDBRAKE_GRIP := 1.2
const TURN_RATE_LOW := 1.3      # рад/с на малой скорости: радиус ниже TURN_FULL_AT = 5/1,3 ≈ 3,9 м
const TURN_RATE_HIGH := 0.85    # рад/с на максимальной
const TURN_FULL_AT := 5.0       # ниже этой скорости поворот слабеет до нуля; 7 (PLAY-01) не взято: в щели тротуар–вал «Лада» не выкручивалась (тест застреваний)
const STEER_SHARPNESS := 10.0   # руль доходит до упора за ~0,2 с, а не мгновенно
const EXIT_SPEED_KMH := 3.0     # быстрее этого водитель не выходит, машина сначала тормозит

var driver: Node3D
var exit_requested := false
var enter_zone: Interactable
var lateral_speed := 0.0        # для тестов и звука заноса
var _steer_now := 0.0

func _ready() -> void:
	collision_layer = 4  # Car
	collision_mask = 1   # World
	floor_snap_length = 0.5
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	collider.position.y = SIZE.y * 0.5
	add_child(collider)
	add_child(LadaVisual.build())  # облик белой «Лады» — ART-03
	enter_zone = InteractableScript.new()
	enter_zone.name = "EnterZone"
	enter_zone.interaction_id = &"car"
	enter_zone.radius = 3.5   # ≈ длина машины, как у эталона (PLAY-01)
	add_child(enter_zone)

func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	var handbrake := false
	var stopping := not driver or exit_requested  # пустая машина и машина перед выходом тормозят до остановки
	if driver and not exit_requested:
		throttle = Input.get_axis(&"move_back", &"move_forward")
		steer = Input.get_axis(&"move_right", &"move_left")
		handbrake = Input.is_action_pressed(&"handbrake")
	var old_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var forward := -global_basis.z
	var forward_speed := old_velocity.dot(forward)

	_steer_now = lerpf(_steer_now, steer, 1.0 - exp(-STEER_SHARPNESS * delta))
	var speed_factor := clampf(absf(forward_speed) / TURN_FULL_AT, 0.0, 1.0)
	var turn_rate := lerpf(TURN_RATE_LOW, TURN_RATE_HIGH, clampf(absf(forward_speed) / MAX_SPEED, 0.0, 1.0))
	if handbrake:
		turn_rate *= HANDBRAKE_TURN
	rotate_y(_steer_now * turn_rate * speed_factor * signf(forward_speed) * delta)

	forward = -global_basis.z
	forward_speed = old_velocity.dot(forward)
	var lateral := old_velocity - forward * forward_speed
	if stopping:
		forward_speed = move_toward(forward_speed, 0.0, BRAKE * delta)
	elif handbrake:
		forward_speed = move_toward(forward_speed, 0.0, HANDBRAKE * delta)
	elif throttle > 0.0:
		if forward_speed < -0.5:
			forward_speed = move_toward(forward_speed, 0.0, BRAKE * delta)
		else:
			var ratio := clampf(forward_speed / MAX_SPEED, 0.0, 1.0)
			forward_speed = minf(forward_speed + ACCELERATION * throttle * (1.0 - ratio * ratio) * delta, MAX_SPEED)
	elif throttle < 0.0:
		if forward_speed > 0.5:
			forward_speed = move_toward(forward_speed, 0.0, BRAKE * delta)
		else:
			forward_speed = maxf(forward_speed + ACCELERATION * REVERSE_ACCEL * throttle * delta, -MAX_REVERSE)
	else:
		forward_speed = move_toward(forward_speed, 0.0, (ROLL_DRAG + AIR_DRAG * forward_speed * forward_speed) * delta)
	lateral *= exp(-(HANDBRAKE_GRIP if handbrake else GRIP) * delta)
	lateral_speed = lateral.length()

	var horizontal := forward * forward_speed + lateral
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= get_gravity().length() * delta
	move_and_slide()
	if exit_requested and speed_kmh() < EXIT_SPEED_KMH:
		exit_requested = false
		var world := get_parent()
		if world and world.has_method("exit_car"):
			world.exit_car()

## E в машине: на месте — выход сразу, на ходу — машина тормозит и водитель выходит после остановки.
func _unhandled_input(event: InputEvent) -> void:
	if driver and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		exit_requested = true

func enter(new_driver: Node3D) -> void:
	driver = new_driver
	driver_entered.emit(driver)

func exit() -> Node3D:
	var former := driver
	driver = null
	exit_requested = false
	if former:
		driver_exited.emit(former)
	return former

func speed_kmh() -> float:
	return Vector2(velocity.x, velocity.z).length() * 3.6

## Поставить машину ровно на точку, без скорости (сброс, появление).
func reset_to(point: Vector3, facing_yaw: float) -> void:
	global_position = point
	rotation = Vector3(0.0, facing_yaw, 0.0)
	velocity = Vector3.ZERO
	lateral_speed = 0.0
	_steer_now = 0.0
	exit_requested = false
	reset_physics_interpolation()
