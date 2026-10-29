class_name DetectionSensor
extends Node3D
## Наблюдатель (C7, EXT-01 S): видит ли он Илюшу — расстояние, угол от −Z узла в плоскости XZ и луч
## от «глаз» (y + 1,5) до центра Илюши (y + 0,9) по слою World (C2): стены, гаражи, павильоны укрывают,
## снег-декор без коллизий — нет. В машине Илюшу не видят (C4), кроме car_area (ниже). Опрос раз в POLL_SECONDS, результат кэшируется;
## дальше ACTIVE_DISTANCE от Илюши сенсор не считает. Все сенсоры — в группе `detection_sensors`,
## их опрашивает StealthDirector. Сектор видимости на земле — по show_cone (полицейский, автобус ГСУМ), виден, пока
## StealthDirector держит cone_wanted (Илюша пешком ближе CONE_DISTANCE). suspicion_cap — потолок шкалы от этого
## сенсора: «учебный» наблюдатель (автобус на улице A, этап 3) зажигает индикатор, но не доводит до провала.
## EXT-02: visibility() = геометрия (0|1) × Ilyusha.exposure_factor(глаза) — 0…1 непрерывно (коробка, сугроб, бочка);
## in_view — геометрия без множителя (для гэгов «в конусе»).
## EXT-01 fix2: car_area (P1) — наблюдатель, «предназначенный для обнаружения машин» (STEALTH_DESIGN): пока Илюша в
## машине и машина в этой области (плоскость XZ), цель — центр машины, угол и дальность не важны (мотор слышно), луч
## нужен; в машине вне области и у сенсоров без car_area Илюшу не видят. Сектор на земле (P3) строится лучами: каждый
## из CONE_RAYS лучей — до первой преграды слоя World, укрытия «вырезают» тень; цвет — cone_color.
## EXT-01 fix3 (третья приёмка, P1): машину в car_area замечают, только когда она почти стоит (скорость < CAR_STILL_SPEED) —
## «остановился у киоска»; проезд мимо не наказывается. Брошенную там машину (Илюша вышел) замечают так же, пока Илюша
## ближе ACTIVE_DISTANCE к сенсору: выйти у окна и дойти пешком — не обход. visibility() — максимум из «видят Илюшу»
## (геометрия × заметность) и «видят машину»; in_view — только Илюша (в машине — машина).
## EXT-01 fix4 (четвёртая приёмка): лучи к машине — к центру кузова и к четырём его углам (CAR_CORNER_INSET внутрь),
## видна, если свободен хотя бы один (в коридоре между гаражами и киоском один луч к центру упирался в киоск). На проезжей
## части B (x ≥ Layout.KIOSK_ROAD_X) машину замечают только после CAR_ROAD_STILL_SECONDS почти полной остановки
## (скорость < CAR_ROAD_STILL_SPEED подряд, car_road_still) — «Лада» за троллейбусом на остановке не «у киоска»; на площадке
## (x < KIOSK_ROAD_X) — сразу. sees_car_now() (вышел из машины на глазах) — без скорости и выдержки, везде в области.
## EXT-01 fix5 (пятая приёмка P1-2, по крышам): on_roof — Илюша пешком в Layout.ROOF_AREA (площадка и гаражи) выше
## Layout.ROOF_HEIGHT над землёй, стоя на чём-то (или в прыжке выше ROOF_JUMP_HEIGHT): включённый сенсор ближе
## ROOF_SEE_DISTANCE видит его с видимостью 1 — без угла, дальности range_m, луча и множителя укрытия.

const POLL_SECONDS := 0.15
const ACTIVE_DISTANCE := 40.0
const EYE_HEIGHT := 1.5
const TARGET_HEIGHT := 0.9
const WORLD_MASK := 1
const CONE_COLOR := Color(1.0, 0.85, 0.12, 0.11)
const CONE_RAYS := 32              # лучей на сектор до 180°
const CONE_RAYS_FULL := 48         # на круг (учебный автобус)
const CAR_TARGET_HEIGHT := 0.7     # центр кузова «Лады» над её началом
const CAR_STILL_SPEED := 2.0       # м/с: медленнее — машина «стоит у киоска» (fix3)
const CAR_ROAD_STILL_SECONDS := 8.0   # fix4: на проезжей части B — столько подряд медленнее CAR_ROAD_STILL_SPEED
const CAR_ROAD_STILL_SPEED := 0.5  # м/с: «почти полная остановка» для выдержки на дороге (торможение и разгон не в счёт)
const CAR_CORNER_INSET := 0.1      # м: углы кузова для лучей — внутрь от габарита Lada.SIZE
const Layout = preload("res://game/world/layout.gd")

@export var range_m := 9.0
@export var fov_deg := 75.0
@export var enabled := true
## Сектор видимости на земле. Показывается только при приближении (STEALTH_DESIGN: не постоянно) — см. cone_wanted.
@export var show_cone := false
## Потолок suspicion, до которого дорастает шкала, пока Илюшу видит только этот сенсор (1 — до провала).
@export var suspicion_cap := 1.0
## Цвет сектора на земле (учебный круг автобуса — бледнее).
@export var cone_color := CONE_COLOR
## Область (x, z), где машина с Илюшей для этого сенсора — как Илюша (P1). Пустая — машин не замечает.
@export var car_area := Rect2()

## Выставляет StealthDirector: сектор рисуется, пока Илюша пешком ближе CONE_DISTANCE.
var cone_wanted := false

var _visible := 0.0
var _poll_left := 0.0
## Последний опрос: Илюша на крыше у киоска и этот сенсор его так видит (fix5).
var on_roof := false
## Что перекрыло луч в последнем опросе (имя тела) — для тестов и настройки укрытий; "" — ничего.
var last_blocker := ""
## Геометрия последнего опроса без множителя заметности: дистанция, угол и луч пропускают (в машине — false).
var in_view := false
var _cone: MeshInstance3D
var _cone_mesh: ImmediateMesh
var _cone_material: StandardMaterial3D
var _exclude: Array[RID] = []
## Сколько секунд подряд машина почти стоит на проезжей части B в car_area (fix4); 0 — едет, не на дороге или вне области.
var car_road_still := 0.0

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
	_update_road_still(delta)
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

## Машина в car_area этого сенсора и почти стоит (P1, fix3): с Илюшей внутри или брошенная (Илюша пешком не дальше
## ACTIVE_DISTANCE от сенсора).
func watches_car(any_speed := false) -> bool:
	if not car_area.has_area():
		return false
	var world := _world()
	if world == null:
		return false
	var car: Node3D = world.get("car")
	if car == null or not car_area.has_point(Vector2(car.global_position.x, car.global_position.z)):
		return false
	if world.get("control_mode") != &"in_car" and distance_to_player() > ACTIVE_DISTANCE:
		return false
	if any_speed:
		return true
	if car.global_position.x >= Layout.KIOSK_ROAD_X and car_road_still < CAR_ROAD_STILL_SECONDS:
		return false   # fix4: на проезжей части B — только после выдержки
	return _car_speed(car) < CAR_STILL_SPEED

func _car_speed(car: Node3D) -> float:
	var v = car.get("velocity")
	return Vector2(v.x, v.z).length() if v is Vector3 else 0.0

## Выдержка «почти стоит на проезжей части B» (fix4): растёт, пока машина в car_area, x ≥ KIOSK_ROAD_X и медленнее
## CAR_ROAD_STILL_SPEED; иначе 0.
func _update_road_still(delta: float) -> void:
	if not car_area.has_area():
		return
	var world := _world()
	var car: Node3D = world.get("car") if world else null
	if car == null or car.global_position.x < Layout.KIOSK_ROAD_X \
			or not car_area.has_point(Vector2(car.global_position.x, car.global_position.z)) or _car_speed(car) >= CAR_ROAD_STILL_SPEED:
		car_road_still = 0.0
	else:
		car_road_still += delta

func _compute() -> float:
	var world := _world()
	var car_seen := _car_in_sight()
	if world != null and world.get("control_mode") == &"in_car":
		in_view = car_seen > 0.0
		on_roof = false
		return car_seen   # машина не прячется: заметность 1
	on_roof = _sees_on_roof()
	if on_roof:
		in_view = true
		return 1.0   # fix5: на крыше заметен всем ближе ROOF_SEE_DISTANCE
	var seen := _line_of_sight()
	in_view = seen > 0.0
	var player_seen := 0.0
	if in_view:
		# EXT-02: множитель заметности (раздел 5.3); в сугробе 0 независимо от луча.
		var player: Node3D = world.player
		player_seen = clampf(player.exposure_factor(global_position + Vector3.UP * EYE_HEIGHT), 0.0, 1.0) if player.has_method("exposure_factor") else seen
	return maxf(player_seen, car_seen)

## Илюша пешком на крыше у киоска (fix5): в Layout.ROOF_AREA выше ROOF_HEIGHT, стоит на чём-то или в прыжке выше
## ROOF_JUMP_HEIGHT (прыжок с земли ≈1,8 м — не крыша).
static func player_on_roof(player: Node3D) -> bool:
	if player == null:
		return false
	var p := player.global_position
	if not Layout.ROOF_AREA.has_point(Vector2(p.x, p.z)) or p.y <= Layout.ROOF_HEIGHT:
		return false
	var on_floor: bool = (player as CharacterBody3D).is_on_floor() if player is CharacterBody3D else true
	return on_floor or p.y > Layout.ROOF_JUMP_HEIGHT

## Этот сенсор видит Илюшу на крыше: включён, Илюша пешком на крыше и ближе ROOF_SEE_DISTANCE (в плоскости XZ).
func _sees_on_roof() -> bool:
	if not enabled or not is_inside_tree():
		return false
	var world := _world()
	if world == null or world.get("control_mode") == &"in_car":
		return false
	var player: Node3D = world.player
	return player_on_roof(player) and distance_to_player() <= Layout.ROOF_SEE_DISTANCE

## Машина в car_area видна этому сенсору при любой скорости (fix3: Илюша выходит из неё на площадке — DemoWorld).
func sees_car_now() -> bool:
	return _car_in_sight(true) > 0.0

## Машина видна (fix3, fix4): watches_car() и свободен хотя бы один луч от глаз — к центру кузова или к одному из четырёх
## углов (car_targets); угол и дальность не важны (мотор и «чья машина у киоска» — с любого угла). 1 или 0.
func _car_in_sight(any_speed := false) -> float:
	if not enabled or not is_inside_tree() or not watches_car(any_speed):
		return 0.0
	var car: CollisionObject3D = _world().get("car")
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var center := car.global_position + Vector3.UP * CAR_TARGET_HEIGHT
	if Vector2(center.x - eye.x, center.z - eye.z).length() > ACTIVE_DISTANCE:
		return 0.0
	var exclude := _exclude.duplicate()
	exclude.append(car.get_rid())
	var space := get_world_3d().direct_space_state
	var blocker := ""
	for target in car_targets(car):
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target, WORLD_MASK, exclude))
		if hit.is_empty():
			return 1.0
		if blocker == "":
			var collider: Object = hit.get("collider")
			blocker = String(collider.name) if collider is Node else "?"
	last_blocker = blocker
	return 0.0

## Точки кузова для лучей (fix4): центр и четыре угла габарита Lada.SIZE (внутрь на CAR_CORNER_INSET) на высоте
## CAR_TARGET_HEIGHT.
static func car_targets(car: Node3D) -> Array[Vector3]:
	var half := Vector2(Lada.SIZE.x * 0.5 - CAR_CORNER_INSET, Lada.SIZE.z * 0.5 - CAR_CORNER_INSET)
	var base := car.global_position + Vector3.UP * CAR_TARGET_HEIGHT
	var right := car.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var back := car.global_basis.z
	back.y = 0.0
	back = back.normalized()
	var out: Array[Vector3] = [base]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append(base + right * half.x * sx + back * half.y * sz)
	return out

## Геометрия зрения на Илюшу пешком: 1 — дистанция, угол и луч пропускают, иначе 0 (в машине — 0); last_blocker —
## что перекрыло луч.
func _line_of_sight() -> float:
	if not enabled or not is_inside_tree():
		return 0.0
	var world := _world()
	if world == null or world.get("control_mode") == &"in_car":
		return 0.0
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var player: Node3D = world.player
	var target := player.global_position + Vector3.UP * TARGET_HEIGHT
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
	var hit := _sight_ray(eye, target)   # EXT-02 P3-1: World и «Лада» (Car) укрывают, жители и собака — нет
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

# --- сектор видимости на земле (P3: лучами до первой преграды) ---

func _update_cone() -> void:
	var wanted := show_cone and cone_wanted and enabled
	if wanted and _cone == null:
		_cone = _build_cone()
		add_child(_cone)
	if _cone:
		_cone.visible = wanted
		if wanted:
			_cone_material.albedo_color = cone_color
			_rebuild_cone()

## Веер треугольников от сенсора: луч i — от глаз (y + EYE_HEIGHT) к точке на дальности range_m на высоте цели
## (TARGET_HEIGHT), как луч зрения в _line_of_sight; длина — до первой преграды слоя World. Перестраивается каждый
## физический кадр, пока виден: корпус поворачивается, автобус и транспорт кольца двигаются.
func _rebuild_cone() -> void:
	var full := fov_deg >= 359.0
	var half := deg_to_rad(minf(fov_deg, 360.0) * 0.5)
	var rays := CONE_RAYS_FULL if full else CONE_RAYS
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var lengths := PackedFloat32Array()
	lengths.resize(rays + 1)
	for i in rays + 1:
		var a := -half + 2.0 * half * i / rays
		var local_dir := Vector3(0, 0, -1).rotated(Vector3.UP, a)
		var world_dir := (global_basis * local_dir)
		world_dir.y = 0.0
		world_dir = world_dir.normalized()
		var end := global_position + world_dir * range_m + Vector3.UP * TARGET_HEIGHT
		var query := PhysicsRayQueryParameters3D.create(eye, end, WORLD_MASK, _exclude)
		var hit := space.intersect_ray(query)
		var length := range_m
		if not hit.is_empty():
			var p: Vector3 = hit["position"]
			length = Vector2(p.x - global_position.x, p.z - global_position.z).length()
		lengths[i] = length
	_cone_mesh.clear_surfaces()
	_cone_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rays:
		var a0 := -half + 2.0 * half * i / rays
		var a1 := -half + 2.0 * half * (i + 1) / rays
		_cone_mesh.surface_add_vertex(Vector3.ZERO)
		_cone_mesh.surface_add_vertex(Vector3(0, 0, -lengths[i]).rotated(Vector3.UP, a0))
		_cone_mesh.surface_add_vertex(Vector3(0, 0, -lengths[i + 1]).rotated(Vector3.UP, a1))
	_cone_mesh.surface_end()

func _build_cone() -> MeshInstance3D:
	_cone_mesh = ImmediateMesh.new()
	_cone_material = StandardMaterial3D.new()
	_cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone_material.albedo_color = cone_color
	var instance := MeshInstance3D.new()
	instance.name = "VisionCone"
	instance.mesh = _cone_mesh
	instance.material_override = _cone_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position.y = 0.06
	return instance

## Длины лучей сектора по последней перестройке не хранятся; для тестов — длина луча под углом a (рад от −Z узла).
func cone_ray_length(a: float) -> float:
	var world_dir := global_basis * Vector3(0, 0, -1).rotated(Vector3.UP, a)
	world_dir.y = 0.0
	world_dir = world_dir.normalized()
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var end := global_position + world_dir * range_m + Vector3.UP * TARGET_HEIGHT
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, end, WORLD_MASK, _exclude))
	if hit.is_empty():
		return range_m
	var p: Vector3 = hit["position"]
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

## EXT-02 P3-1 (приёмка, HIDE_SPOTS.md 14 B «Лада» перекрывает луч): луч к Илюше пешком — по World и Car (1|4).
## На слое Car, кроме «Лады», — тела жителей (Resident.BODY_LAYER) и собаки (Ambient.dog_body): они не укрывают —
## такое попадание исключается и луч повторяется. Укрывает всё, что на слое World, и сама машина мира (world.car).
const SIGHT_CAR_MASK := 4
func _sight_ray(eye: Vector3, target: Vector3) -> Dictionary:
	var world := _world()
	var car: Object = world.get("car") if world else null
	var exclude := _exclude.duplicate()
	var space := get_world_3d().direct_space_state
	for i in 6:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target, WORLD_MASK | SIGHT_CAR_MASK, exclude))
		if hit.is_empty():
			return hit
		var collider: Object = hit.get("collider")
		if collider == car or not (collider is CollisionObject3D) or (collider as CollisionObject3D).collision_layer & WORLD_MASK:
			return hit
		exclude.append(hit.get("rid"))
	return {}
