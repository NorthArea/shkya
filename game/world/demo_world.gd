class_name DemoWorld
extends Node3D
## DemoWorld: собирает квартал, ставит участников по Layout (C1), переключает «пешком / в машине» (C4)
## и отдаёт снимок HUD (C6). Состояние миссии хранит только MissionDirector; диалоги и маркеры — QuestFlow.

const Layout = preload("res://game/world/layout.gd")

const EXIT_OFFSETS: Array[Vector3] = [   # куда встаёт Илюша при выходе, в осях машины (−x — сторона водителя)
	Vector3(-1.7, 0, 0), Vector3(1.7, 0, 0), Vector3(0, 0, 3.4), Vector3(0, 0, -3.4),
	Vector3(-2.8, 0, 1.5), Vector3(2.8, 0, 1.5), Vector3(-2.8, 0, -1.5), Vector3(2.8, 0, -1.5),
]
const RESET_CLEARANCE := 3.0

var control_mode: StringName = &"on_foot"
## true, пока открыт диалог или панель: мышь видна и не захватывается по клику (выставляет QuestFlow).
var ui_blocking := false

@onready var player: Ilyusha = $Ilyusha
@onready var camera_rig: CameraRig = $CameraRig
@onready var mission: MissionDirector = $MissionDirector
@onready var babka: Node3D = $Babka
@onready var vendor: Node3D = $Vendor
@onready var car: Lada = $Car
@onready var kiosk_zone: Area3D = $KioskZone

func _ready() -> void:
	babka.position = Layout.BABKA
	babka.rotation.y = 0.0  # лицом на север, к двору
	vendor.position = Layout.VENDOR
	vendor.interactable.position = Layout.VENDOR_WINDOW - Layout.VENDOR
	car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	car.enter_zone.interacted.connect(func(_actor): enter_car())
	player.camera_rig = camera_rig
	player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	camera_rig.yaw = Layout.SPAWN_YAW
	camera_rig.follow(player, &"on_foot")
	camera_rig.exclude_permanently(babka.get_node("Body").get_rid())
	_sync_prompts()

func _physics_process(_delta: float) -> void:
	_sync_prompts()

## Тексты и доступность зон E — только из MissionDirector (C3).
func _sync_prompts() -> void:
	for zone: Interactable in [babka.interactable, vendor.interactable, car.enter_zone]:
		zone.prompt = mission.prompt_for(zone.interaction_id)
		zone.enabled = zone.prompt != ""

# --- C4: пешком / в машине ---

func enter_car() -> void:
	if control_mode == &"in_car":
		return
	control_mode = &"in_car"
	_set_player_active(false)
	car.enter(player)
	camera_rig.yaw = car.global_rotation.y
	camera_rig.follow(car, &"in_car")
	mission.notify_entered_car()

## Выйти рядом с машиной на свободное место. Если места нет — остаться в машине.
func exit_car() -> bool:
	if control_mode != &"in_car":
		return false
	var spot := _free_exit_spot()
	if spot == Vector3.INF:
		return false
	control_mode = &"on_foot"
	car.exit()
	player.place(spot, car.global_rotation.y)
	_set_player_active(true)
	camera_rig.yaw = car.global_rotation.y
	camera_rig.follow(player, &"on_foot")
	return true

func _set_player_active(active: bool) -> void:
	player.visible = active
	player.input_enabled = active
	player.velocity = Vector3.ZERO
	player.set_physics_process(active)
	player.get_node("CollisionShape3D").set_deferred("disabled", not active)
	player.probe.monitoring = active

func _free_exit_spot() -> Vector3:
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1 | 4
	for offset in EXIT_OFFSETS:
		var spot := car.global_transform * offset
		spot.y = 0.0
		if not Layout.BOUNDS.has_point(Vector2(spot.x, spot.z)):
			continue
		query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.8)
		if space.intersect_shape(query, 1).is_empty():
			return spot
	return Vector3.INF

## «Сбросить автомобиль»: ближайшая точка маршрута машины, по ходу маршрута, без скорости (приёмка 5).
func reset_car() -> void:
	var best_point := Layout.ROUTE_DRIVE[0]
	var best_yaw := Layout.CAR_SPAWN_YAW
	var best_distance := INF
	var position_now := Vector3(car.global_position.x, 0.0, car.global_position.z)
	for i in range(1, Layout.ROUTE_DRIVE.size()):
		var a := Layout.ROUTE_DRIVE[i - 1]
		var b := Layout.ROUTE_DRIVE[i]
		var point := Geometry3D.get_closest_point_to_segment(position_now, a, b)
		var segment := b - a
		# Не ставить машину на Илюшу: сдвинуть вдоль участка.
		if control_mode == &"on_foot" and point.distance_to(player.global_position) < RESET_CLEARANCE:
			var shifted := point + segment.normalized() * RESET_CLEARANCE * 1.5
			point = shifted if (shifted - a).length() <= segment.length() else point - segment.normalized() * RESET_CLEARANCE * 1.5
		var distance := point.distance_to(position_now)
		if distance < best_distance:
			best_distance = distance
			best_point = point
			best_yaw = atan2(-segment.x, -segment.z)
	car.reset_to(best_point, best_yaw)
	if control_mode == &"in_car":
		camera_rig.yaw = best_yaw
		camera_rig.snap()

func anchor_position(id: StringName) -> Vector3:
	match id:
		&"babka": return babka.global_position
		&"vendor": return Layout.VENDOR_WINDOW
		&"kiosk": return Layout.KIOSK
		&"car": return car.global_position
	return Vector3.INF

## C6 — снимок для HUD. HUD только читает его каждый кадр.
func get_hud_state() -> Dictionary:
	var objective := mission.objective()
	var prompt := ""
	if control_mode == &"on_foot":
		var zone := player.current_interactable()
		if zone:
			prompt = zone.prompt
	var target_id: StringName = objective.get("target_id", &"")
	return {
		"title": objective.get("title", ""),
		"task": objective.get("task", ""),
		"prompt": prompt,
		"target_position": null if target_id == &"" else anchor_position(target_id),
		"babka_marker": mission.babka_marker(),
		"speed_kmh": car.speed_kmh() if control_mode == &"in_car" else -1.0,
		"toast": $QuestFlow.toast_text(),
		"complete": mission.state == MissionDirector.COMPLETE,
	}
