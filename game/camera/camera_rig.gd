class_name CameraRig
extends Node3D
## C4 — камера от третьего лица на SpringArm3D. Мышь крутит yaw/pitch, когда курсор захвачен.
## Профиль in_car использует DRIVE-01.

const PROFILES := {
	&"on_foot": {"distance": 4.5, "height": 1.7, "pitch": -0.30},
	&"in_car": {"distance": 7.5, "height": 2.2, "pitch": -0.22},
}
const PITCH_MIN := -1.1
const PITCH_MAX := 0.35
const FOLLOW_SHARPNESS := 14.0
const CHASE_SHARPNESS := 3.0

@export var mouse_sensitivity := 0.0025

var target: Node3D
var profile: StringName = &"on_foot"
var yaw := 0.0
var pitch := -0.30
var arm: SpringArm3D
var camera: Camera3D
var permanent_exclusions: Array[RID] = []
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
	camera.fov = 65.0
	camera.current = true
	arm.add_child(camera)

func follow(new_target: Node3D, new_profile: StringName = &"on_foot") -> void:
	target = new_target
	profile = new_profile
	pitch = PROFILES[profile]["pitch"]
	arm.clear_excluded_objects()
	for rid in permanent_exclusions:
		arm.add_excluded_object(rid)
	if target is CollisionObject3D:
		arm.add_excluded_object(target.get_rid())
	snap()

## Тела, которые не должны притягивать камеру (NPC рядом с героем).
func exclude_permanently(rid: RID) -> void:
	permanent_exclusions.append(rid)
	arm.add_excluded_object(rid)

## Мгновенно поставить камеру за целью, без сглаживания.
func snap() -> void:
	if target:
		global_position = _goal()
		arm.spring_length = PROFILES[profile]["distance"]
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
	arm.spring_length = lerpf(arm.spring_length, PROFILES[profile]["distance"], 1.0 - exp(-4.0 * delta))
	rotation = Vector3(pitch, yaw, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse(event.relative)

## Мышь вправо — камера вправо, мышь вверх — взгляд вверх.
func apply_mouse(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * mouse_sensitivity, PITCH_MIN, PITCH_MAX)

func _goal() -> Vector3:
	return target.global_position + Vector3.UP * PROFILES[profile]["height"]
