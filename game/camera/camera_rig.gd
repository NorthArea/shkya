class_name CameraRig
extends Node3D
## C4 — камера от третьего лица на SpringArm3D. Мышь крутит yaw/pitch, когда курсор захвачен.
## Профиль in_car использует DRIVE-01.

## Кадр по замеру эталона PLAY-01 (G02) и концептам 01, 04, 05: камера ближе и ниже, FOV 55°,
## в машине FOV растёт со скоростью (до +6°), пешком камера сама доворачивает за Илюшей (PLAY-02).
const PROFILES := {
	&"on_foot": {"distance": 4.3, "height": 1.9, "pitch": -0.17, "fov": 55.0},
	&"in_car": {"distance": 6.7, "height": 2.2, "pitch": -0.22, "fov": 55.0},
}
const FOV_PER_SPEED := 0.16     # градусов на м/с в машине
const FOV_SPEED_MAX := 6.0
const FOV_SHARPNESS := 4.0
const AUTO_FOLLOW_IDLE := 1.0   # с без мыши — камера начинает доворачивать за Илюшей
const AUTO_FOLLOW_RATE := 2.2   # 1/с
const AUTO_FOLLOW_MAX := 2.2    # рад: при ходьбе на камеру (разворот больше) не доворачивать
const PITCH_MIN := -1.1
const PITCH_MAX := 0.35
const FOLLOW_SHARPNESS := 14.0
const CHASE_SHARPNESS := 3.0

@export var mouse_sensitivity := 0.0025

var target: Node3D
var profile: StringName = &"on_foot"
## Любое присваивание yaw снаружи (мышь, сцена, тесты) переносит и input_yaw — опору ходьбы.
## Автодоводка меняет только yaw: пока нажаты те же клавиши, Илюша идёт прежним курсом и не закручивается
## по спирали; при смене клавиш он берёт новый yaw (sync_input_yaw).
var yaw := 0.0:
	set(value):
		yaw = value
		input_yaw = value
var input_yaw := 0.0
## Курс, за которым доворачивает камера пешком (Ilyusha задаёт его по взгляду), и скорость цели.
var follow_heading := 0.0
var follow_speed := 0.0
var _mouse_idle := 0.0
var pitch := -0.30
var arm: SpringArm3D
var camera: Camera3D
var permanent_exclusions: Array[RID] = []
## Плечевое смещение вправо, м: на время диалога камера уходит вбок, чтобы собеседник
## за спиной Илюши был виден (кадр 07). Меняется плавно.
var shoulder := 0.0
var _shoulder_now := 0.0
const SHOULDER_SHARPNESS := 5.0
func _ready() -> void:
	arm = SpringArm3D.new()
	arm.name = "Arm"
	arm.collision_mask = 1  # только World
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	arm.shape = sphere
	add_child(arm)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = PROFILES[&"on_foot"]["fov"]
	camera.current = true
	arm.add_child(camera)

## instant = false: камера встаёт за новой целью сразу, а дистанция плавно меняется до профиля.
func follow(new_target: Node3D, new_profile: StringName = &"on_foot", instant := true) -> void:
	target = new_target
	profile = new_profile
	pitch = PROFILES[profile]["pitch"]
	arm.clear_excluded_objects()
	for rid in permanent_exclusions:
		arm.add_excluded_object(rid)
	if target is CollisionObject3D:
		arm.add_excluded_object(target.get_rid())
	snap(instant)

## Тела, которые не должны притягивать камеру (NPC рядом с героем).
func exclude_permanently(rid: RID) -> void:
	permanent_exclusions.append(rid)
	arm.add_excluded_object(rid)

## Мгновенно поставить камеру за целью, без сглаживания.
func snap(with_distance := true) -> void:
	if target:
		global_position = _goal()
		if with_distance:
			arm.spring_length = PROFILES[profile]["distance"]
			camera.fov = PROFILES[profile]["fov"]
		rotation = Vector3(pitch, yaw, 0.0)
		reset_physics_interpolation()

## Камера движется в физическом кадре вместе с целью; плавность между кадрами даёт интерполяция физики.
func _physics_process(delta: float) -> void:
	if not target:
		return
	global_position = global_position.lerp(_goal(), 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	if profile == &"in_car":
		# Камера преследования: плавно встаёт за машиной по её курсу.
		yaw = lerp_angle(yaw, target.global_rotation.y, 1.0 - exp(-CHASE_SHARPNESS * delta))
	elif follow_speed > 0.2:
		_mouse_idle += delta
		var diff := wrapf(follow_heading - yaw, -PI, PI)
		if _mouse_idle >= AUTO_FOLLOW_IDLE and absf(diff) < AUTO_FOLLOW_MAX:
			var keep := input_yaw
			yaw = yaw + diff * (1.0 - exp(-AUTO_FOLLOW_RATE * delta))
			input_yaw = keep
	else:
		_mouse_idle += delta
	var fov: float = PROFILES[profile]["fov"]
	if profile == &"in_car" and target is Lada:
		fov += minf(FOV_PER_SPEED * (target as Lada).speed_kmh() / 3.6, FOV_SPEED_MAX)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-FOV_SHARPNESS * delta))
	arm.spring_length = lerpf(arm.spring_length, PROFILES[profile]["distance"], 1.0 - exp(-4.0 * delta))
	_shoulder_now = lerpf(_shoulder_now, shoulder, 1.0 - exp(-SHOULDER_SHARPNESS * delta))
	rotation = Vector3(pitch, yaw, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse(event.relative)

## Мышь вправо — камера вправо, мышь вверх — взгляд вверх.
func apply_mouse(relative: Vector2) -> void:
	_mouse_idle = 0.0
	yaw = wrapf(yaw - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * mouse_sensitivity, PITCH_MIN, PITCH_MAX)

## Опора ходьбы догоняет камеру: вызывается при смене нажатых клавиш.
func sync_input_yaw() -> void:
	input_yaw = yaw

func _goal() -> Vector3:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return target.global_position + Vector3.UP * PROFILES[profile]["height"] + right * _shoulder_now
