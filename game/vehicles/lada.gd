class_name Lada
extends CharacterBody3D
## Белая «Лада» (DRIVE-01): аркадная езда на CharacterBody3D, вход и выход по E (C4).
## Модель: продольная скорость от газа/тормоза, поворот зависит от скорости,
## боковая скорость гасится сцеплением — на мокрой дороге остаётся лёгкий занос, ручник его усиливает.

signal driver_entered(driver: Node3D)
signal driver_exited(driver: Node3D)

const Greybox = preload("res://game/world/greybox.gd")
const InteractableScript = preload("res://game/interaction/interactable.gd")

const SIZE := Vector3(1.7, 1.4, 4.1)
const MAX_SPEED := 22.0         # м/с ≈ 80 км/ч
const MAX_REVERSE := 6.0
const ACCELERATION := 8.0
const BRAKE := 16.0
const ROLL_DRAG := 2.0
const HANDBRAKE := 9.0
const GRIP := 7.0               # мокрая дорога: боковая скорость гасится не мгновенно
const HANDBRAKE_GRIP := 1.2
const TURN_RATE_LOW := 1.9      # рад/с на малой скорости
const TURN_RATE_HIGH := 0.75    # рад/с на максимальной
const TURN_FULL_AT := 5.0       # ниже этой скорости поворот слабеет до нуля

var driver: Node3D
var enter_zone: Interactable
var lateral_speed := 0.0        # для тестов и звука заноса

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
	add_child(_build_placeholder_visual())
	enter_zone = InteractableScript.new()
	enter_zone.name = "EnterZone"
	enter_zone.interaction_id = &"car"
	enter_zone.radius = 2.8
	add_child(enter_zone)

func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	var handbrake := false
	if driver:
		throttle = Input.get_axis(&"move_back", &"move_forward")
		steer = Input.get_axis(&"move_right", &"move_left")
		handbrake = Input.is_action_pressed(&"handbrake")
	var old_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var forward := -global_basis.z
	var forward_speed := old_velocity.dot(forward)

	var speed_factor := clampf(absf(forward_speed) / TURN_FULL_AT, 0.0, 1.0)
	var turn_rate := lerpf(TURN_RATE_LOW, TURN_RATE_HIGH, clampf(absf(forward_speed) / MAX_SPEED, 0.0, 1.0))
	rotate_y(steer * turn_rate * speed_factor * signf(forward_speed) * delta)

	forward = -global_basis.z
	forward_speed = old_velocity.dot(forward)
	var lateral := old_velocity - forward * forward_speed
	if handbrake:
		forward_speed = move_toward(forward_speed, 0.0, HANDBRAKE * delta)
	elif throttle > 0.0:
		if forward_speed < -0.5:
			forward_speed = move_toward(forward_speed, 0.0, BRAKE * delta)
		else:
			forward_speed = minf(forward_speed + ACCELERATION * throttle * delta, MAX_SPEED)
	elif throttle < 0.0:
		if forward_speed > 0.5:
			forward_speed = move_toward(forward_speed, 0.0, BRAKE * delta)
		else:
			forward_speed = maxf(forward_speed + ACCELERATION * 0.6 * throttle * delta, -MAX_REVERSE)
	else:
		forward_speed = move_toward(forward_speed, 0.0, ROLL_DRAG * delta)
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

func _unhandled_input(event: InputEvent) -> void:
	if driver and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		var world := get_parent()
		if world and world.has_method("exit_car"):
			world.exit_car()

func enter(new_driver: Node3D) -> void:
	driver = new_driver
	driver_entered.emit(driver)

func exit() -> Node3D:
	var former := driver
	driver = null
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
	reset_physics_interpolation()

func _build_placeholder_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var body := Greybox.mesh_box(Vector3(SIZE.x, 0.75, SIZE.z), Color(0.93, 0.93, 0.89))
	body.position.y = 0.65
	root.add_child(body)
	var cabin := Greybox.mesh_box(Vector3(SIZE.x * 0.92, 0.55, SIZE.z * 0.48), Color(0.70, 0.75, 0.80))
	cabin.position = Vector3(0.0, 1.3, 0.25)
	root.add_child(cabin)
	for x in [-0.8, 0.8]:
		for z in [-1.3, 1.3]:
			var wheel := Greybox.mesh_cylinder(0.32, 0.32, 0.22, Color(0.08, 0.08, 0.08))
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(x, 0.32, z)
			root.add_child(wheel)
		var headlight := Greybox.mesh_box(Vector3(0.35, 0.18, 0.05), Color(1.0, 0.92, 0.6))
		headlight.position = Vector3(x * 0.8, 0.75, -SIZE.z * 0.5 - 0.02)
		root.add_child(headlight)
	return root
