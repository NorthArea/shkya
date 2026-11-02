class_name CityVan
extends AnimatableBody3D
## Общая пассажирская ГАЗель-32213 в роли микроавтобуса ГСУМ «БЕСПЛАТНЫЙ ПРОЕЗД» (EXT-01 N, концепт e02): белый с ржавчиной, снег на крыше,
## остекление, тёплый свет в салоне, открытая правая боковая дверь, надписи «БЕСПЛАТНЫЙ ПРОЕЗД» на боках и
## «МАРШРУТ УТОЧНЯЕТСЯ» сзади, номер региона 154 без реальных эмблем. Перед — −Z, правая сторона (дверь) — +X,
## начало — на земле. Тело — AnimatableBody3D на слое World (C2): укрытие для луча DetectionSensor, коллизия едет
## вместе с кузовом. Дочерний DetectionSensor у двери (C7) в двух режимах: на стоянке (park) — «учебный»
## (этап 3: PARK_SENSOR_RANGE м во все стороны, потолок шкалы TUTORIAL_CAP — индикатор без провала); в пути выключен;
## в конце пути — дверной (STEALTH_DESIGN: 14 м, 80°) из двери наружу. Сектор на земле — при приближении Илюши.
## Interactable «ГОРОДСКОЙ ТРАНСПОРТ (?)» — только подпись при приближении, без действия (MISSION_EXTENSION).
## drive(path, stop_yaw) — постановочный проезд по точкам (сглаженные повороты, SPEED м/с) и остановка в конце
## носом по stop_yaw; без физики трафика (README расширения). Впереди по пути — датчик, как у PathVehicle
## (game/vehicles/path_vehicle.gd): «Лада», Илюша, транспорт кольца в SCAN_AHEAD м — торможение и ожидание, объезда нет;
## перед шагом кузов на новом месте проверяется на касание — сквозь машины автобус не едет (приёмка 28.10, P2).
## EXT-01 fix2 (P2-4): на полосе кольца (троллейбус — RING, машины — CAR_RING, Layout.ring_lane) автобус стоит не
## дольше STALL_SECONDS: дальше поездка завершается постановочно на ближайшей по пути точке вне полос, где кузов
## никого не касается (может оказаться и концом пути на площадке) — без толчков; вне полос ждёт, пока освободят.
## EXT-01 fix3 (третья приёмка, P3): без телепорта. Простоял на полосе STALL_SECONDS — едет по своему пути дальше до
## ближайшей точки вне полос и завершает поездку там, если кузов проходит туда, никого не касаясь (stall_drives); иначе
## ждёт ещё. Телепорт на точку вне полос — только крайний случай после STALL_TELEPORT_SECONDS, с push_warning
## (stall_ends). Вне полос за «Ладой» (обочина улицы A) ждёт не дольше DETOUR_AFTER и объезжает её по полосе машин
## кольца (Layout.ring_lane(…, true)), если полоса свободна DETOUR_CLEAR м вперёд (detours); иначе стоит.
## Учебный круг на стоянке улицы A — PARK_SENSOR_RANGE 6 м и бледнее (TUTORIAL_CONE_COLOR, P3).
## EXT-01 fix4 (четвёртая приёмка P3: при брошенной на полосе «Ладе» автобус переносился назад, на улицу A): крайний
## случай — после STALL_TELEPORT_SECONDS 60 с ожидания и только ВПЕРЁД по пути, на ближайшую точку вне полос, где кузов
## никого не касается; до того ждёт, пока путь освободят.

const Gazelle = preload("res://game/vehicles/gazelle_visual.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const DetectionSensorScript = preload("res://game/stealth/detection_sensor.gd")
const Layout = preload("res://game/world/layout.gd")
const InteractableScript = preload("res://game/interaction/interactable.gd")

const SIZE := Gazelle.PASSENGER_SIZE
const PLATE := "о282оо 154"
const PROMPT := "ГОРОДСКОЙ ТРАНСПОРТ (?)"
const BODY_PAINT := Color(0.93, 0.92, 0.88)
const SPEED := 6.0
const ACCEL := 2.5            # м/с²: разгон и торможение у конца пути
const TURN_SMOOTH := 5.0      # радиус скругления углов пути, м
const WHEEL_RADIUS := Gazelle.WHEEL_RADIUS
const DOOR_AT := Vector3(Gazelle.HALF_WIDTH + 0.015, 0.0, 0.3)   # низ открытого дверного проёма, правый борт
const SENSOR_RANGE := 14.0
const SENSOR_FOV := 80.0
const PARK_SENSOR_RANGE := 6.0    # этап 3: пешком у двери и у «военкома» — индикатор (8 → 6 м, EXT-01 fix2, P3)
const TUTORIAL_CONE_COLOR := Color(1.0, 0.85, 0.12, 0.06)   # учебный круг бледнее обычного сектора
const PARK_SENSOR_FOV := 360.0
const TUTORIAL_CAP := 0.6         # на стоянке улицы A шкала дорастает до 0,6 и стоит — провала нет
const SCAN_AHEAD := 7.0           # м от переднего бампера
const SCAN_STEP := 1.0
const STOP_MARGIN := 2.5          # м: встаёт, когда препятствие в 2,5–3,5 м от бампера
const EMERGENCY_DECEL := 9.0
const OBSTACLE_MASK := 1 | 2 | 4  # World (транспорт кольца), Player, Car
const STALL_SECONDS := 12.0       # P2-4: дольше на полосе кольца не стоит — съезжает по пути с полосы (fix3)
const STALL_TELEPORT_SECONDS := 60.0   # fix4: крайний случай — постановочно на точку вне полос впереди, с предупреждением
const STALL_RETRY := 0.5          # с между попытками съехать с полосы или объехать
const DETOUR_AFTER := 20.0        # fix3: вне полос за «Ладой» — столько ждёт, потом объезд по полосе машин
const DETOUR_CLEAR := 15.0        # м свободной полосы машин впереди для объезда
const DETOUR_MAX_SHIFT := 4.5     # м: полоса машин дальше в сторону — объезда нет
const LANE_CLEARANCE := 1.95      # консервативный прежний зазор: новая половина кузова 1,0375 меньше прежних 1,05
const STALL_SEARCH_STEP := 0.5    # м: шаг поиска точки пути вне полос

var sensor: Node3D
var interactable: Interactable
var visual: Node3D
var _curve: Curve3D
var _offset := 0.0
var _speed := 0.0
var _stop_yaw := 0.0
var _driving := false
var _wheels: Array[MeshInstance3D] = []
var _scan_query := PhysicsShapeQueryParameters3D.new()
var _body_query := PhysicsShapeQueryParameters3D.new()
## Что держит автобус в последнем кадре (null — ничего) — для тестов.
var blocked_by: Object = null
## Сколько секунд подряд стоит перед телом (P2-4); сколько поездок завершено досрочно вне полос.
var stall_seconds := 0.0
var stall_ends := 0
## Кто держал автобус перед последним досрочным завершением (имя тела) — для тестов и журнала.
var last_stall_blocker := ""
## fix3: сколько раз съехал с полосы своим ходом (досрочный конец поездки) и сколько раз объехал «Ладу».
var stall_drives := 0
var detours := 0
var _end_at := -1.0      # досрочный конец поездки (смещение по пути), −1 — конец пути
var _retry_left := 0.0
var _path: Array = []
var _detour_query := PhysicsShapeQueryParameters3D.new()
var _lanes: Array = []   # оси полос кольца (Layout.ring_lane): троллейбус и машины

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = false
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	collider.position.y = SIZE.y * 0.5
	add_child(collider)
	visual = _build_visual()
	add_child(visual)
	sensor = DetectionSensorScript.new()
	sensor.name = "DetectionSensor"
	sensor.range_m = SENSOR_RANGE
	sensor.fov_deg = SENSOR_FOV
	sensor.position = DOOR_AT
	sensor.rotation.y = -PI * 0.5   # −Z сенсора → +X: из двери наружу
	sensor.show_cone = true
	add_child(sensor)
	var scan_box := BoxShape3D.new()
	scan_box.size = Vector3(SIZE.x + 0.3, 1.8, SCAN_STEP)
	_scan_query.shape = scan_box
	_scan_query.collision_mask = OBSTACLE_MASK
	_scan_query.exclude = [get_rid()]
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(SIZE.x + 0.1, 1.8, SIZE.z + 0.1)
	_body_query.shape = body_box
	_body_query.collision_mask = OBSTACLE_MASK
	_body_query.exclude = [get_rid()]
	interactable = InteractableScript.new()
	interactable.name = "Interactable"
	interactable.interaction_id = &"city_van"
	interactable.prompt = PROMPT
	interactable.radius = 4.2
	interactable.position = Vector3(0, 0, 0)
	add_child(interactable)

## Поставить на точку носом по yaw (yaw 0 — на север, как в Layout).
func park(point: Vector3, yaw: float) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x, 0.0, point.z))
	_driving = false
	_curve = null
	_end_at = -1.0
	_sensor_mode(PARK_SENSOR_RANGE, PARK_SENSOR_FOV, TUTORIAL_CAP)
	sensor.cone_color = TUTORIAL_CONE_COLOR

## Проехать по точкам (первая — где стоит сейчас) и встать в конце носом по stop_yaw.
func drive(path: Array, stop_yaw: float) -> void:
	if path.size() < 2:
		return
	stall_seconds = 0.0
	_route(path, stop_yaw)
	sensor.enabled = false   # в пути не смотрит; дверной режим — на месте

## Построить кривую по точкам и ехать с её начала (drive и объезд).
func _route(path: Array, stop_yaw: float) -> void:
	_path = path.duplicate()
	_end_at = -1.0
	_retry_left = 0.0
	_curve = Curve3D.new()
	_curve.bake_interval = 0.25
	for i in path.size():
		var p: Vector3 = path[i]
		p.y = 0.0
		var tangent_in := Vector3.ZERO
		var tangent_out := Vector3.ZERO
		if i > 0 and i < path.size() - 1:
			var prev: Vector3 = path[i - 1]
			var next: Vector3 = path[i + 1]
			var d0 := (p - prev)
			var d1 := (next - p)
			d0.y = 0.0
			d1.y = 0.0
			var reach := minf(TURN_SMOOTH, minf(d0.length(), d1.length()) * 0.4)
			var dir := (d0.normalized() + d1.normalized()).normalized()
			tangent_in = -dir * reach
			tangent_out = dir * reach
		_curve.add_point(p, tangent_in, tangent_out)
	_offset = 0.0
	_speed = 0.0
	_stop_yaw = stop_yaw
	_driving = true

## Режим сенсора двери: дальность, угол, потолок шкалы; включает сенсор.
func _sensor_mode(range_m: float, fov: float, cap: float) -> void:
	sensor.range_m = range_m
	sensor.fov_deg = fov
	sensor.suspicion_cap = cap
	sensor.cone_color = DetectionSensor.CONE_COLOR
	sensor.enabled = true

func is_driving() -> bool:
	return _driving

func _physics_process(delta: float) -> void:
	if not _driving or _curve == null:
		return
	var length := _curve.get_baked_length()
	var end := _end_at if _end_at >= 0.0 else length
	var left := end - _offset
	# Тормозной путь v²/2a: перед концом сбрасываем, иначе набираем до SPEED.
	var allowed := sqrt(maxf(2.0 * ACCEL * left, 0.0))
	var target := minf(SPEED, allowed)
	var obstacle := _obstacle_limit(length, end)
	if obstacle < target:
		_speed = maxf(_speed - EMERGENCY_DECEL * delta, obstacle)
	elif _speed < target:
		_speed = minf(_speed + ACCEL * delta, target)
	else:
		_speed = maxf(_speed - ACCEL * 1.5 * delta, target)
	var next := minf(_offset + _speed * delta, end)
	if next > _offset and not _free_at(next, length):
		_speed = 0.0   # кузов на новом месте задел бы машину или Илюшу — стоим
	if _speed < 0.05 and blocked_by != null:
		stall_seconds += delta
		_retry_left -= delta
		_on_stall(length)
		return
	stall_seconds = 0.0
	_offset = next
	var at := _curve.sample_baked(_offset, true)
	var ahead := _curve.sample_baked(minf(_offset + 0.6, length), true)
	var behind := _curve.sample_baked(maxf(_offset - 0.6, 0.0), true)
	var dir := ahead - behind
	dir.y = 0.0
	var yaw := global_rotation.y
	if dir.length() > 0.01:
		yaw = atan2(-dir.x, -dir.z)
	if left < 1.5 and _end_at < 0.0:
		# Последние полтора метра — довернуть к stop_yaw.
		yaw = lerp_angle(global_rotation.y, _stop_yaw, 1.0 - exp(-4.0 * delta))
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.z))
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.UP, -_speed * delta / WHEEL_RADIUS)   # ось цилиндра повёрнута на ±90° по Z
	if _offset >= end - 0.01:
		if _end_at < 0.0:
			global_transform = Transform3D(Basis(Vector3.UP, _stop_yaw), Vector3(at.x, 0.0, at.z))
		_driving = false
		_speed = 0.0
		_end_at = -1.0
		_sensor_mode(SENSOR_RANGE, SENSOR_FOV, 1.0)

## Стоит перед телом (fix3): на полосе — после STALL_SECONDS съехать по пути, после STALL_TELEPORT_SECONDS — телепорт;
## вне полос за «Ладой» — после DETOUR_AFTER объезд по полосе машин. Попытки — раз в STALL_RETRY с.
func _on_stall(length: float) -> void:
	if _retry_left > 0.0:
		return
	if on_lane():
		if stall_seconds >= STALL_TELEPORT_SECONDS:
			push_warning("CityVan: %.0f s on a ring lane behind %s at %s — moved off the lane (last resort)" % [stall_seconds, blocked_by.name if blocked_by is Node else "?", global_position])
			_end_trip_off_lane(length)
		elif stall_seconds >= STALL_SECONDS and _end_at < 0.0:
			var blocker: Object = blocked_by
			var off := _off_lane_ahead(length)
			blocked_by = blocker
			if off >= 0.0:
				last_stall_blocker = String(blocker.name) if blocker is Node else ""
				_end_at = off if off < length - STALL_SEARCH_STEP else -1.0
				stall_drives += 1
				stall_seconds = 0.0
	elif stall_seconds >= DETOUR_AFTER and blocked_by is Lada:
		_try_detour(length)
	_retry_left = STALL_RETRY

## Ближайшее смещение по пути впереди, где кузов вне полос, и весь путь до него кузов никого не касается; −1 — нет.
func _off_lane_ahead(length: float) -> float:
	var o := _offset + STALL_SEARCH_STEP
	while o <= length + 0.001:
		if not _free_at(minf(o, length), length):
			return -1.0
		if not _xform_on_lane(_transform_at(minf(o, length), length, 0.0)):
			return minf(o, length)
		o += STALL_SEARCH_STEP
	return -1.0

## Объезд «Лады» (fix3): сдвиг на ось полосы машин кольца сбоку, мимо «Лады» с запасом и обратно на путь. Только если
## полоса рядом (≤ DETOUR_MAX_SHIFT) и свободна DETOUR_CLEAR м вперёд. true — поехал в объезд.
func _try_detour(length: float) -> bool:
	var blocker := blocked_by as Node3D
	var pos := global_position
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var lane: Array[Vector3] = Layout.ring_lane(6.0, 6, true)
	var best := Vector2.INF
	var q := Vector2(pos.x, pos.z)
	for i in lane.size():
		var a: Vector3 = lane[i]
		var b: Vector3 = lane[(i + 1) % lane.size()]
		var c := Geometry2D.get_closest_point_to_segment(q, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if c.distance_to(q) < best.distance_to(q):
			best = c
	var shift := (Vector3(best.x, 0.0, best.y) - pos).dot(right)
	if absf(shift) > DETOUR_MAX_SHIFT or absf(shift) < 1.0:
		return false
	var side := right * shift
	var along := (blocker.global_position - pos).dot(fwd)
	var pass_at := along + Lada.SIZE.z * 0.5 + SIZE.z * 0.5 + 2.0
	# Полоса свободна: коробка шириной кузова + 0,6 м по оси полосы от бампера на DETOUR_CLEAR (не короче объезда).
	var reach := maxf(DETOUR_CLEAR, pass_at + SIZE.z * 0.5)
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x + 0.6, 1.6, reach)
	_detour_query.shape = box
	_detour_query.collision_mask = OBSTACLE_MASK
	_detour_query.exclude = [get_rid()]
	var center := pos + side + fwd * (SIZE.z * 0.5 + reach * 0.5) + Vector3.UP * 1.1
	_detour_query.transform = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), center)
	for result in get_world_3d().direct_space_state.intersect_shape(_detour_query, 8):
		if _is_obstacle(result["collider"]):
			return false
	# Возврат на путь — первая точка кривой впереди дальше pass_at + 6 м по ходу; дальше — исходные точки после неё.
	var rejoin := -1.0
	var o := _offset
	while o <= length:
		if (_curve.sample_baked(o, true) - pos).dot(fwd) >= pass_at + 6.0:
			rejoin = o
			break
		o += STALL_SEARCH_STEP
	var points: Array = [pos, pos + fwd * 3.0 + side, pos + fwd * pass_at + side]
	if rejoin >= 0.0:
		points.append(_curve.sample_baked(rejoin, true))
		for p in _path:
			if _curve.get_closest_offset(p) > rejoin + 1.0:
				points.append(p)
	else:
		points.append(_path[-1])
	detours += 1
	last_stall_blocker = String(blocker.name)
	stall_seconds = 0.0
	_route(points, _stop_yaw)
	return true

## Кузов на полосе кольца: ось автобуса (центр и ±2,2 м вдоль) ближе LANE_CLEARANCE к оси любой полосы (C8).
func on_lane() -> bool:
	return _xform_on_lane(global_transform)

func _xform_on_lane(xform: Transform3D) -> bool:
	if _lanes.is_empty():
		_lanes = [Layout.ring_lane(6.0, 6), Layout.ring_lane(6.0, 6, true)]
	var forward := -xform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for k: float in [-2.2, 0.0, 2.2]:
		var p := xform.origin + forward * k
		var q := Vector2(p.x, p.z)
		for lane in _lanes:
			var n: int = lane.size()
			for i in n:
				var a: Vector3 = lane[i]
				var b: Vector3 = lane[(i + 1) % n]
				var c := Geometry2D.get_closest_point_to_segment(q, Vector2(a.x, a.z), Vector2(b.x, b.z))
				if c.distance_to(q) < LANE_CLEARANCE:
					return true
	return false

## P2-4 (fix3, fix4 — только крайний случай после STALL_TELEPORT_SECONDS): встать на ближайшей точке пути ВПЕРЕДИ вне
## полос, где кузов никого не касается (конец пути — обычная остановка носом по stop_yaw), и завершить поездку; дверной
## сенсор включается. Назад (на улицу A) не переносится. Такой точки нет — ждать ещё STALL_TELEPORT_SECONDS.
func _end_trip_off_lane(length: float) -> void:
	stall_seconds = 0.0
	_end_at = -1.0
	var blocker: Object = blocked_by   # _free_at ниже перезаписывает blocked_by
	var best := -1.0
	var o := _offset + STALL_SEARCH_STEP
	while o <= length + 0.001:
		var xform := _transform_at(o, length, 0.0)
		if not _xform_on_lane(xform) and _free_at(o, length):
			best = o
			break
		o += STALL_SEARCH_STEP
	if best < 0.0 and not _xform_on_lane(_transform_at(length, length, 0.0)) and _free_at(length, length):
		best = length
	if best < 0.0:
		blocked_by = blocker
		return
	last_stall_blocker = String(blocker.name) if blocker is Node else ""
	_offset = best
	_speed = 0.0
	_driving = false
	stall_ends += 1
	var at := _curve.sample_baked(best, true)
	var yaw := _stop_yaw if best >= length - STALL_SEARCH_STEP else _transform_at(best, length, 0.0).basis.get_euler().y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.z))
	_sensor_mode(SENSOR_RANGE, SENSOR_FOV, 1.0)

## Предел скорости по датчику впереди: коробки шириной кузова + 0,3 м вдоль пути от бампера на SCAN_AHEAD (не дальше
## бампера в конце поездки end — досрочный конец, fix3).
func _obstacle_limit(length: float, end := INF) -> float:
	var space := get_world_3d().direct_space_state
	blocked_by = null
	for k in int(round(SCAN_AHEAD / SCAN_STEP)):
		var at := _offset + SIZE.z * 0.5 + SCAN_STEP * (k + 0.5)
		if at > minf(length, end) + SIZE.z * 0.5:
			break
		_scan_query.transform = _transform_at(at, length, 1.1)
		for result in space.intersect_shape(_scan_query, 8):
			if _is_obstacle(result["collider"]):
				blocked_by = result["collider"]
				return sqrt(2.0 * EMERGENCY_DECEL * maxf(SCAN_STEP * k - STOP_MARGIN, 0.0))
	return INF

## Кузов на смещении at никого подвижного не задевает.
func _free_at(at: float, length: float) -> bool:
	_body_query.transform = _transform_at(at, length, 0.95)
	for result in get_world_3d().direct_space_state.intersect_shape(_body_query, 8):
		if _is_obstacle(result["collider"]):
			blocked_by = result["collider"]
			return false
	return true

## Положение на кривой со смещением at (за концом — продолжение по последнему направлению), на высоте y.
func _transform_at(at: float, length: float, y: float) -> Transform3D:
	var clamped := clampf(at, 0.0, length)
	var p := _curve.sample_baked(clamped, true)
	var ahead := _curve.sample_baked(minf(clamped + 0.6, length), true)
	var behind := _curve.sample_baked(maxf(clamped - 0.6, 0.0), true)
	var dir := ahead - behind
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = -global_basis.z
	dir = dir.normalized()
	p += dir * (at - clamped)
	return Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), Vector3(p.x, y, p.z))

## Препятствие — любой корпус, кроме неподвижной застройки и NPC (StaticBody3D, не AnimatableBody3D).
static func _is_obstacle(body: Object) -> bool:
	if body == null:
		return false
	if body is StaticBody3D and not (body is AnimatableBody3D):
		return false
	return true

# --- служебная окраска общей пассажирской ГАЗели с открытой сдвижной дверью ---

func _build_visual() -> Node3D:
	var root := Gazelle.build(BODY_PAINT, PLATE, 0.12, Gazelle.PASSENGER, true)
	var body := root.get_node("Body/BodyMesh") as MeshInstance3D
	var slots: Array = body.mesh.get_meta("slots", [])
	body.set_surface_override_material(slots.find("head"),
		VehicleMesh.lamp(Color(1.0, 0.95, 0.80), Color(1.0, 0.90, 0.66), 1.4))
	body.set_surface_override_material(slots.find("tail"),
		VehicleMesh.lamp(Color(0.5, 0.05, 0.03), Color(0.9, 0.08, 0.04), 0.6))
	var paint := body.get_surface_override_material(slots.find("paint")) as ShaderMaterial
	paint.set_shader_parameter("rust_amount", 0.75)
	paint.set_shader_parameter("dirt_amount", 0.7)
	for child in root.get_children():
		if str(child.name).begins_with("WheelPivot"):
			_wheels.append(child.get_node("Wheel"))
	VehicleMesh.exhaust(root, Vector3(-0.95, 0.255, 0.72))
	for x in [-1.0, 1.0]:
		var side := _label("БЕСПЛАТНЫЙ\nПРОЕЗД", 50, Color(0.62, 0.06, 0.05))
		side.position = Gazelle.OPEN_DOOR_SIGN if x > 0.0 else Vector3(-Gazelle.HALF_WIDTH - 0.012, 1.02, 0.45)
		side.position.y = 1.02
		side.rotation.y = PI * 0.5 if x > 0.0 else -PI * 0.5
		root.add_child(side)
	var rear := _label("МАРШРУТ\nУТОЧНЯЕТСЯ", 48, Color(0.62, 0.06, 0.05))
	rear.position = Vector3(0.0, 1.17, 2.68)
	root.add_child(rear)
	var lamp := OmniLight3D.new()
	lamp.name = "CabinLight"
	lamp.position = Vector3(0.2, 1.9, 0.4)
	lamp.light_color = Color(1.0, 0.78, 0.46)
	lamp.light_energy = 1.1
	lamp.omni_range = 4.5
	lamp.omni_attenuation = 1.4
	preload("res://game/world/lighting.gd").configure_local_shadow(lamp)
	lamp.light_specular = 0.2
	root.add_child(lamp)
	return root

func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.0046
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
