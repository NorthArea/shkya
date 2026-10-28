class_name Ilyusha
extends CharacterBody3D
## Илюша пешком: ходьба относительно камеры, взаимодействие по E (C3).
## Visual — облик ШКЯ в зимнем костюме (ART-01, CharacterSprite); поворот Visual = взгляд Илюши.

const CharacterSpriteScript = preload("res://game/characters/character_sprite.gd")

const WALK_SPEED := 4.0         # 2,2 роста/с при фигуре 1,8 м, как у эталона (PLAY-02)
const ACCELERATION := 30.0
const DECELERATION := 11.0      # остановка за ~0,4 с, как у эталона (PLAY-01)
const TURN_RATE := 12.0
const PROBE_RADIUS := 0.5

var input_enabled := true
var camera_rig: CameraRig
var visual: Node3D
var probe: Area3D
var _last_input := Vector2.ZERO

func _ready() -> void:
	collision_layer = 2       # Player
	collision_mask = 1 | 4    # World, Car
	# Без привязки к полу: квартал плоский, ступеней и спусков нет. Привязка 0,3 м при упоре в вертикальное ребро
	# коробки (угол дома, торец вала снега) проваливала Илюшу в землю на 0,15–0,30 м (POLISH-01, tests/polish01_stuck.gd).
	floor_snap_length = 0.0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.5
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = capsule
	collider.position.y = 0.75
	add_child(collider)
	visual = _build_visual()
	add_child(visual)
	probe = Area3D.new()
	probe.name = "InteractProbe"
	probe.collision_layer = 0
	probe.collision_mask = 8  # Interact
	probe.monitorable = false
	var sphere := SphereShape3D.new()
	sphere.radius = PROBE_RADIUS
	var probe_shape := CollisionShape3D.new()
	probe_shape.shape = sphere
	probe_shape.position.y = 0.9
	probe.add_child(probe_shape)
	add_child(probe)

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	# Курс ходьбы — от камеры на момент смены клавиш (CameraRig.input_yaw): автодоводка камеры
	# не закручивает Илюшу, пока держишь те же клавиши (PLAY-02).
	if camera_rig and not input.is_equal_approx(_last_input):
		camera_rig.sync_input_yaw()
	_last_input = input
	var yaw := camera_rig.input_yaw if camera_rig else 0.0
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	var rate := ACCELERATION if direction.length_squared() > 0.01 else DECELERATION
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * WALK_SPEED, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= get_gravity().length() * delta
	move_and_slide()
	if direction.length_squared() > 0.01:
		var facing := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, facing, clampf(TURN_RATE * delta, 0.0, 1.0))
	if camera_rig and camera_rig.target == self:
		# Курс доводки — направление ввода, а не плавно поворачивающийся облик: иначе при ходьбе
		# на камеру она рывком облетала героя (повторная сверка PLAY-02, P2).
		if direction.length_squared() > 0.01:
			camera_rig.follow_heading = atan2(-direction.x, -direction.z)
		camera_rig.follow_speed = Vector2(velocity.x, velocity.z).length() if input_enabled else 0.0

func _unhandled_input(event: InputEvent) -> void:
	if input_enabled and event.is_action_pressed(&"interact"):
		var target := current_interactable()
		if target:
			get_viewport().set_input_as_handled()
			target.interact(self)

## Ближайшая доступная зона взаимодействия, в которой стоит Илюша.
func current_interactable() -> Interactable:
	if not input_enabled:
		return null
	var best: Interactable = null
	var best_distance := INF
	for area in probe.get_overlapping_areas():
		if area is Interactable and area.enabled and area.prompt != "":
			var distance := global_position.distance_squared_to(area.global_position)
			if distance < best_distance:
				best = area
				best_distance = distance
	return best

## Поставить на точку и остановить (появление, перезапуск, выход из машины).
func place(point: Vector3, facing_yaw: float) -> void:
	global_position = point
	velocity = Vector3.ZERO
	visual.rotation.y = facing_yaw
	reset_physics_interpolation()

func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var look: CharacterSprite = CharacterSpriteScript.new()
	look.name = "Look"
	look.character = "ilyusha"
	look.height_m = 2.0   # фигура ≈1,8 м — чуть выше крыши «Лады», как в концепте 04 и у эталона (PLAY-01)
	root.add_child(look)
	return root
