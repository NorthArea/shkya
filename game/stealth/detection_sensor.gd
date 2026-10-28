class_name DetectionSensor
extends Node3D
## Наблюдатель (C7, EXT-01 S): видит ли он Илюшу — расстояние, угол от −Z узла в плоскости XZ и луч
## от «глаз» (y + 1,5) до центра Илюши (y + 0,9) по слою World (C2): стены, гаражи, павильоны укрывают,
## снег-декор без коллизий — нет. В машине Илюшу не видят (C4). Опрос раз в POLL_SECONDS, результат кэшируется;
## дальше ACTIVE_DISTANCE от Илюши сенсор не считает. Все сенсоры — в группе `detection_sensors`,
## их опрашивает StealthDirector. Сектор видимости на земле — по show_cone (полицейский, автобус ГСУМ), виден, пока
## StealthDirector держит cone_wanted (Илюша пешком ближе CONE_DISTANCE). suspicion_cap — потолок шкалы от этого
## сенсора: «учебный» наблюдатель (автобус на улице A, этап 3) зажигает индикатор, но не доводит до провала.
## EXT-02: visibility() = геометрия (0|1) × Ilyusha.exposure_factor(глаза) — 0…1 непрерывно (коробка, сугроб, бочка);
## in_view — геометрия без множителя (для гэгов «в конусе»).

const POLL_SECONDS := 0.15
const ACTIVE_DISTANCE := 40.0
const EYE_HEIGHT := 1.5
const TARGET_HEIGHT := 0.9
const WORLD_MASK := 1
const CONE_COLOR := Color(1.0, 0.85, 0.12, 0.16)

@export var range_m := 9.0
@export var fov_deg := 75.0
@export var enabled := true
## Сектор видимости на земле. Показывается только при приближении (STEALTH_DESIGN: не постоянно) — см. cone_wanted.
@export var show_cone := false
## Потолок suspicion, до которого дорастает шкала, пока Илюшу видит только этот сенсор (1 — до провала).
@export var suspicion_cap := 1.0

## Выставляет StealthDirector: сектор рисуется, пока Илюша пешком ближе CONE_DISTANCE.
var cone_wanted := false

var _visible := 0.0
var _poll_left := 0.0
## Что перекрыло луч в последнем опросе (имя тела) — для тестов и настройки укрытий; "" — ничего.
var last_blocker := ""
## Геометрия последнего опроса без множителя заметности: дистанция, угол и луч пропускают (в машине — false).
var in_view := false
var _cone: MeshInstance3D
var _cone_shape := Vector2.ZERO   # (range_m, fov_deg), под которые построен сектор
var _exclude: Array[RID] = []

func _ready() -> void:
	add_to_group(&"detection_sensors")
	# Собственное тело наблюдателя (StaticBody родителя или соседа) луч не задевает.
	var owner_node := get_parent()
	while owner_node:
		if owner_node is CollisionObject3D:
			_exclude.append((owner_node as CollisionObject3D).get_rid())
		owner_node = owner_node.get_parent()
	if get_parent():
		for sibling in get_parent().get_children():
			if sibling is CollisionObject3D:
				_exclude.append((sibling as CollisionObject3D).get_rid())

func _physics_process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left += POLL_SECONDS
		_visible = _compute()
	if _cone or (show_cone and cone_wanted):
		_update_cone()

## Кэшированная видимость 0…1: геометрия (0 или 1) × заметность Илюши (EXT-02).
func visibility() -> float:
	return _visible

## Пересчитать немедленно (для тестов и постановочных моментов).
func poll() -> float:
	_visible = _compute()
	_poll_left = POLL_SECONDS
	return _visible

## Расстояние до Илюши в плоскости XZ, INF без мира.
func distance_to_player() -> float:
	var world := _world()
	if world == null:
		return INF
	var p: Vector3 = world.player.global_position
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

func _compute() -> float:
	var seen := _line_of_sight()
	in_view = seen > 0.0
	if not in_view:
		return 0.0
	# EXT-02: множитель заметности (раздел 5.3); в сугробе 0 независимо от луча.
	var player: Node3D = _world().player
	if player.has_method("exposure_factor"):
		return clampf(player.exposure_factor(global_position + Vector3.UP * EYE_HEIGHT), 0.0, 1.0)
	return seen

## Геометрия зрения: 1 — дистанция, угол и луч пропускают, иначе 0; last_blocker — что перекрыло луч.
func _line_of_sight() -> float:
	if not enabled or not is_inside_tree():
		return 0.0
	var world := _world()
	if world == null or world.get("control_mode") == &"in_car":
		return 0.0
	var player: Node3D = world.player
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var target: Vector3 = player.global_position + Vector3.UP * TARGET_HEIGHT
	var flat := Vector2(target.x - eye.x, target.z - eye.z)
	var distance := flat.length()
	if distance > ACTIVE_DISTANCE or distance > range_m:
		return 0.0
	var forward := -global_basis.z
	var heading := Vector2(forward.x, forward.z)
	if distance > 0.01 and heading.length() > 0.001:
		var angle := rad_to_deg(absf(heading.angle_to(flat)))
		if angle > fov_deg * 0.5:
			return 0.0
	var query := PhysicsRayQueryParameters3D.create(eye, target, WORLD_MASK, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		last_blocker = String(collider.name) if collider is Node else "?"
		return 0.0
	last_blocker = ""
	return 1.0

func _world() -> Node:
	var node := get_parent()
	while node:
		if node.get("control_mode") != null and node.get("player") != null:
			return node
		node = node.get_parent()
	return null

# --- отладочный сектор ---

func _update_cone() -> void:
	var wanted := show_cone and cone_wanted and enabled
	if wanted and _cone and _cone_shape != Vector2(range_m, fov_deg):
		_cone.queue_free()   # дальность или угол сменились (автобус ГСУМ на стоянке и у киоска)
		_cone = null
	if wanted and _cone == null:
		_cone = _build_cone()
		_cone_shape = Vector2(range_m, fov_deg)
		add_child(_cone)
	if _cone:
		_cone.visible = wanted

func _build_cone() -> MeshInstance3D:
	var half := deg_to_rad(minf(fov_deg, 360.0) * 0.5)
	var steps := 48 if fov_deg > 180.0 else 24
	var vertices := PackedVector3Array()
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		vertices.append(Vector3.ZERO)
		vertices.append(Vector3(0, 0, -range_m).rotated(Vector3.UP, a0))
		vertices.append(Vector3(0, 0, -range_m).rotated(Vector3.UP, a1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = CONE_COLOR
	var instance := MeshInstance3D.new()
	instance.name = "VisionCone"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position.y = 0.06
	return instance
