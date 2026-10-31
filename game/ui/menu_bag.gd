extends Node3D
## MENU-02: постановочный пакет справа от карточек меню; материал и печать держит двор.

const WindBags = preload("res://game/world/wind_bags.gd")

const PERIOD := 16.0
const FLIGHT_SECONDS := 12.0
const START_OFFSET := 3.0
const DEPTH := 8.0
const BAG_SCALE := 2.0
const SCREEN_EDGE := 1.14
const SCREEN_SWEEP := 0.45

var material: ShaderMaterial
var _look: MeshInstance3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_look = MeshInstance3D.new()
	_look.name = "Look"
	_look.mesh = WindBags.bag_mesh()
	_look.material_override = material
	_look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_look.scale = Vector3.ONE * BAG_SCALE
	add_child(_look)
	_look.set_instance_shader_parameter("puff", 0.08)
	_look.set_instance_shader_parameter("flutter", 0.05)
	_look.set_instance_shader_parameter("flap_speed", 12.0)
	_look.set_instance_shader_parameter("phase", 1.9)


## Вызывать после перемещения камеры. Абсолютное время исключает зависимость от FPS.
func update_pose(camera: Camera3D, seconds: float) -> void:
	var clock := fposmod(maxf(seconds, 0.0) + START_OFFSET, PERIOD)
	visible = clock < FLIGHT_SECONDS and is_instance_valid(camera)
	if not visible:
		return
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		visible = false
		return
	var flight := clock / FLIGHT_SECONDS
	# Оба конца за правым краем: пауза и возврат не дают видимого скачка.
	var screen := Vector2(SCREEN_EDGE - SCREEN_SWEEP * sin(PI * flight), 0.48 + 0.07 * sin(TAU * flight))
	global_position = camera.project_position(screen * viewport_size, DEPTH)
	var tumble := Vector3(0.3 * sin(TAU * flight), 0.55 * sin(TAU * flight * 1.5), 0.6 * sin(TAU * flight * 2.0))
	global_basis = camera.global_basis.orthonormalized() * Basis.from_euler(tumble)
