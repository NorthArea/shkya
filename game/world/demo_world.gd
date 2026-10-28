class_name DemoWorld
extends Node3D
## DemoWorld: собирает квартал, ставит участников по Layout (C1), переключает «пешком / в машине» (C4)
## и отдаёт снимок HUD (C6). Состояние миссии хранит только MissionDirector; диалоги и маркеры — QuestFlow.

const Layout = preload("res://game/world/layout.gd")
const SnowTracks = preload("res://game/world/snow_tracks.gd")

const EXIT_OFFSETS: Array[Vector3] = [   # куда встаёт Илюша при выходе, в осях машины (−x — сторона водителя)
	Vector3(-1.7, 0, 0), Vector3(1.7, 0, 0), Vector3(0, 0, 3.4), Vector3(0, 0, -3.4),
	Vector3(-2.8, 0, 1.5), Vector3(2.8, 0, 1.5), Vector3(-2.8, 0, -1.5), Vector3(2.8, 0, -1.5),
	Vector3(-1.7, 0, 3.0), Vector3(1.7, 0, 3.0), Vector3(-1.7, 0, -3.0), Vector3(1.7, 0, -3.0),
	Vector3(0, 0, 4.8), Vector3(0, 0, -4.8), Vector3(-3.8, 0, 0), Vector3(3.8, 0, 0),
]
const RESET_CLEARANCE := 3.0
const RESET_SHIFTS: Array[float] = [0.0, 4.5, -4.5, 9.0, -9.0, 13.5, -13.5]
const HINT_NO_EXIT := "НЕТ МЕСТА, ЧТОБЫ ВЫЙТИ"
const HINT_SECONDS := 2.0

var control_mode: StringName = &"on_foot"
## true, пока открыт диалог или панель: мышь видна и не захватывается по клику (выставляет QuestFlow).
var ui_blocking := false
var _hint := ""
var _hint_left := 0.0

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
	var tracks := SnowTracks.new()   # следы колёс и шагов на снегу — PLAY-03
	tracks.name = "SnowTracks"
	add_child(tracks)
	_sync_prompts()

func _physics_process(delta: float) -> void:
	_sync_prompts()
	_hint_left = maxf(_hint_left - delta, 0.0)

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
	camera_rig.follow(car, &"in_car", false)
	mission.notify_entered_car()

## Выйти рядом с машиной на свободное место. Если места нет — остаться в машине и сказать об этом.
func exit_car() -> bool:
	if control_mode != &"in_car":
		return false
	var spot := _free_exit_spot()
	if spot == Vector3.INF:
		_hint = HINT_NO_EXIT
		_hint_left = HINT_SECONDS
		return false
	control_mode = &"on_foot"
	car.exit()
	player.place(spot, car.global_rotation.y)
	_set_player_active(true)
	camera_rig.yaw = car.global_rotation.y
	camera_rig.follow(player, &"on_foot", false)
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
	var origin := car.global_position + Vector3.UP * 0.8
	for offset in EXIT_OFFSETS:
		var spot := car.global_transform * offset
		spot.y = 0.0
		if not Layout.BOUNDS.has_point(Vector2(spot.x, spot.z)):
			continue
		query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.8)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		# Не выходить сквозь стену: от машины до точки должно быть видно.
		var ray := PhysicsRayQueryParameters3D.create(origin, spot + Vector3.UP * 0.8, 1, [car.get_rid()])
		if space.intersect_ray(ray).is_empty():
			return spot
	return Vector3.INF

## «Сбросить автомобиль»: ближайшая к машине свободная точка маршрута, носом по ходу маршрута,
## без скорости и не ближе RESET_CLEARANCE к Илюше (приёмка 5).
func reset_car() -> void:
	var position_now := Vector3(car.global_position.x, 0.0, car.global_position.z)
	var candidates := []
	for i in range(1, Layout.ROUTE_DRIVE.size()):
		var a := Layout.ROUTE_DRIVE[i - 1]
		var b := Layout.ROUTE_DRIVE[i]
		var direction := (b - a).normalized()
		var closest := Geometry3D.get_closest_point_to_segment(position_now, a, b)
		for shift in RESET_SHIFTS:
			var point := closest + direction * shift
			if (point - a).dot(direction) < 0.0 or (point - a).length() > a.distance_to(b):
				continue
			candidates.append([point.distance_to(position_now), point, atan2(-direction.x, -direction.z)])
	candidates.sort_custom(func(x, y): return x[0] < y[0])
	var placed := false
	for candidate in candidates:
		if _car_spot_free(candidate[1], candidate[2]):
			car.reset_to(candidate[1], candidate[2])
			placed = true
			break
	if not placed:
		car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)  # маршрут занят целиком — на стоянку во дворе
	if control_mode == &"in_car":
		camera_rig.yaw = car.global_rotation.y
		camera_rig.snap()

func _car_spot_free(point: Vector3, yaw: float) -> bool:
	if control_mode == &"on_foot" and point.distance_to(player.global_position) < RESET_CLEARANCE:
		return false
	var box := BoxShape3D.new()
	box.size = Lada.SIZE + Vector3(0.4, -0.2, 0.4)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 1 | 2
	query.exclude = [car.get_rid()]
	query.transform = Transform3D(Basis(Vector3.UP, yaw), point + Vector3.UP * (Lada.SIZE.y * 0.5 + 0.1))
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

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
	elif _hint_left > 0.0:
		prompt = _hint
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
