class_name PathVehicle
extends AnimatableBody3D
## Транспорт на кольце арены (ARENA-01, часть T, контракт C8). Общее для TrafficCar и Trolleybus.
## Тело — AnimatableBody3D на слое World (1), маска 0, как CityVan: двигается установкой transform, физикой
## никого не толкает. Путь — LanePath: замкнутый цикл через Layout.RING, смещённый на RING_LANE вправо по ходу
## (правостороннее движение), углы скруглены дугами радиуса TURN_RADIUS. Корпус ставится по двум осям на пути
## (передняя и задняя — на полколёсной базы вперёд и назад), поэтому в повороте задние колёса идут внутри дуги.
## Скорость — минимум из ограничений: крейсерская, поворот, свои впереди (дистанция ≥ FOLLOW_GAP по бамперам),
## датчик впереди SENSOR_RANGE м (Lada, Илюша, любой не статичный корпус: торможение до остановки, объезда нет —
## ждёт), и ограничение потомка (остановки троллейбуса). Препятствие ближе тормозного пути при 9 м/с² —
## аварийное торможение до HARD_DECEL (12 м/с²) с остановкой за CONTACT_MARGIN до него (ARENA-01 fix P3). Перед шагом —
## последняя страховка: корпус на новом месте никого не задевает, иначе стоит (никого не толкает).
## Без случайностей: всё задаётся смещением старта.

const Materials = preload("res://game/world/materials.gd")
const Layout = preload("res://game/world/layout.gd")

const TURN_RADIUS := 6.0
## Машины (ARENA-01 fix P2-2) идут против троллейбуса, по внешней полосе, повороты левые. Радиус 4 м, а не 6: на
## углу A∩B дуга 6 м подводила борт «Газели» к оси ROUTE_DRIVE (70, 32) на 0,56 м, 4 м — на 1,30 м (C8: ≥ 0,9).
const CAR_TURN_RADIUS := 4.0
const ACCEL := 2.5              # м/с² разгон
const SOFT_DECEL := 2.5         # м/с² плановое торможение (поворот, остановка)
const EMERGENCY_DECEL := 9.0    # м/с² до упора — препятствие из датчика (9 → 0 м/с за 1 с, 4,5 м)
const HARD_DECEL := 12.0        # м/с² аварийное: препятствие возникло ближе тормозного пути при 9 м/с² (6 м/с → 1,5 м)
const CONTACT_MARGIN := 0.3     # м: аварийная остановка — за столько до начала коробки датчика с препятствием
const SENSOR_RANGE := 8.0       # м от переднего бампера
const SENSOR_STEP := 1.0        # длина одной коробки датчика вдоль пути
const STOP_MARGIN := 3.5        # м: стоп, когда препятствие в 3–4 м от бампера (шаг коробок 1 м): разворачивающейся
                                # «Ладе» хватает места, чтобы не задеть стоящего
const FOLLOW_GAP := 10.0        # м между бамперами своих (C8)
const FOLLOW_DECEL := 3.0
const SENSOR_MASK := 1 | 2 | 4 # World (транспорт, автобус ГСУМ), Player, Car
const GROUP := &"traffic_vehicles"

## Габарит корпуса (ширина, высота, длина), перед — −Z. Задаётся до добавления в дерево.
var size := Vector3(1.7, 1.45, 4.1)
var wheelbase := 2.4
var wheel_radius := 0.32
var cruise_speed := 9.0
var corner_speed := 5.0
## Свои на кольце (включая себя) — для дистанции; задаёт Traffic.
var peers: Array = []
var path: LanePath
## Смещение центра корпуса вдоль пути, м (растёт по ходу; по модулю длины пути).
var s := 0.0
var speed := 0.0
var distance_travelled := 0.0
## Что остановило по датчику в последнем кадре (null — ничего) и сколько секунд стоим из-за этого.
var blocked_by: Object = null
var blocked_time := 0.0
## Ограничение скорости и его причина в последнем кадре — для тестов и отладки.
var limit_reason: StringName = &""
## Замедление в последнем кадре, м/с² (0 — не тормозил) — для тестов: аварийное не больше HARD_DECEL.
var last_decel := 0.0
## Расстояние от бампера до препятствия датчика в последнем кадре (INF — нет).
var obstacle_gap := INF
var visual: Node3D

var _wheels: Array[Node3D] = []
var _tail: StandardMaterial3D
var _sensor_query := PhysicsShapeQueryParameters3D.new()
var _body_query := PhysicsShapeQueryParameters3D.new()

func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = false

func _ready() -> void:
	add_to_group(GROUP)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	collider.position.y = size.y * 0.5
	add_child(collider)
	var sensor_box := BoxShape3D.new()
	sensor_box.size = Vector3(size.x + 0.3, 1.8, SENSOR_STEP)
	_sensor_query.shape = sensor_box
	_sensor_query.collision_mask = SENSOR_MASK
	_sensor_query.exclude = [get_rid()]
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(size.x + 0.1, minf(size.y, 1.8), size.z + 0.1)
	_body_query.shape = body_box
	_body_query.collision_mask = SENSOR_MASK
	_body_query.exclude = [get_rid()]
	_tail = StandardMaterial3D.new()
	_tail.albedo_color = Color(0.42, 0.04, 0.03)
	_tail.roughness = 0.3
	_tail.emission_enabled = true
	_tail.emission = Color(0.95, 0.06, 0.03)
	_tail.emission_energy_multiplier = 0.8
	visual = _build_visual()
	visual.name = "Visual"
	add_child(visual)
	if path:
		_apply_transform()

## Поставить на путь со смещением offset (м вдоль пути от его начала).
func setup(lane_path: LanePath, offset: float) -> void:
	path = lane_path
	s = fposmod(offset, path.length)
	speed = 0.0
	if is_inside_tree():
		_apply_transform()

## Габарит корпуса на земле: центр и направление «вперёд» (XZ).
func footprint() -> Array:
	return [Vector2(global_position.x, global_position.z), Vector2(-global_basis.z.x, -global_basis.z.z).normalized(), Vector2(size.x, size.z)]

func _physics_process(delta: float) -> void:
	if path == null or delta <= 0.0:
		return
	_tick(delta)
	var target := _target_speed()
	var braking := target < speed - 0.01
	var before := speed
	if speed < target:
		speed = minf(speed + ACCEL * delta, target)
	else:
		speed = maxf(speed - _brake_decel() * delta, target)
	var step := _limit_step(speed * delta)
	if step > 0.0 and not _free_at(s + step):
		# Страховка: аварийное торможение не успело (кто-то шагнул под самый бампер или в борт) — стоим, не толкаем.
		step = 0.0
		speed = 0.0
		limit_reason = &"body"
	last_decel = maxf((before - speed) / delta, 0.0)
	s = fposmod(s + step, path.length)
	distance_travelled += step
	if step > 0.0:
		_apply_transform()
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.UP, -step / wheel_radius)   # ось цилиндра повёрнута на 90° по Z
	_tail.emission_energy_multiplier = 3.5 if braking or speed < 0.05 else 0.8
	if blocked_by != null and speed < 0.05:
		blocked_time += delta
	elif blocked_by == null:
		blocked_time = 0.0

## Ограничения скорости: минимум из всех; limit_reason — какое сработало.
func _target_speed() -> float:
	var v := cruise_speed
	limit_reason = &"cruise"
	var corner := _corner_limit()
	if corner < v:
		v = corner
		limit_reason = &"corner"
	var follow := _follow_limit()
	if follow < v:
		v = follow
		limit_reason = &"follow"
	var own := _extra_limit()
	if own < v:
		v = own
		limit_reason = &"own"
	var obstacle := _obstacle_limit()
	if obstacle < v:
		v = obstacle
		limit_reason = &"sensor"
	return maxf(v, 0.0)

func _corner_limit() -> float:
	var v := INF
	for arc in path.arcs:
		var into := fposmod(s + size.z * 0.5 - arc.x, path.length)   # перед уже в дуге
		if into < arc.y - arc.x + size.z:
			return corner_speed
		var ahead := fposmod(arc.x - s - size.z * 0.5, path.length)
		if ahead < 40.0:
			v = minf(v, sqrt(corner_speed * corner_speed + 2.0 * SOFT_DECEL * ahead))
	return v

## Ближайший свой впереди по пути: зазор между бамперами не меньше FOLLOW_GAP.
func _follow_limit() -> float:
	var best := INF
	var ahead: PathVehicle = null
	for other in peers:
		if other == self or not is_instance_valid(other):
			continue
		var d := fposmod(other.s - s, path.length)
		if d < best:
			best = d
			ahead = other
	if ahead == null:
		return INF
	var gap := best - size.z * 0.5 - ahead.size.z * 0.5
	return sqrt(2.0 * FOLLOW_DECEL * maxf(gap - FOLLOW_GAP, 0.0))

## Датчик: коробки шириной корпуса + 0,3 м вдоль пути от переднего бампера на SENSOR_RANGE.
## Препятствие — любой корпус, кроме неподвижной застройки (StaticBody3D, не AnimatableBody3D).
func _obstacle_limit() -> float:
	var hit: Variant = scan_ahead()
	if hit == null:
		blocked_by = null
		obstacle_gap = INF
		return INF
	blocked_by = hit[1]
	var d: float = hit[0]
	obstacle_gap = d
	return sqrt(2.0 * EMERGENCY_DECEL * maxf(d - STOP_MARGIN, 0.0))

## Замедление: плановое — EMERGENCY_DECEL; если препятствие датчика ближе тормозного пути при нём — сколько нужно,
## чтобы встать за CONTACT_MARGIN до него, но не больше HARD_DECEL (ARENA-01 fix P3: было — мгновенный стоп).
func _brake_decel() -> float:
	if obstacle_gap == INF or speed <= 0.0:
		return EMERGENCY_DECEL
	var room := obstacle_gap - CONTACT_MARGIN
	if room <= 0.0:
		return HARD_DECEL
	return clampf(speed * speed / (2.0 * room), EMERGENCY_DECEL, HARD_DECEL)

## [расстояние от бампера до начала коробки, корпус] или null.
func scan_ahead() -> Variant:
	var space := get_world_3d().direct_space_state
	var steps := int(round(SENSOR_RANGE / SENSOR_STEP))
	for k in steps:
		var at := s + size.z * 0.5 + SENSOR_STEP * (k + 0.5)
		var p := path.position_at(at)
		var dir := path.direction_at(at)
		_sensor_query.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), p + Vector3.UP * 1.1)
		for result in space.intersect_shape(_sensor_query, 8):
			var body: Object = result["collider"]
			if _is_obstacle(body):
				return [SENSOR_STEP * k, body]
	return null

static func _is_obstacle(body: Object) -> bool:
	if body == null:
		return false
	if body is StaticBody3D and not (body is AnimatableBody3D):
		return false
	return true

## Корпус на смещении at не задевает никого подвижного (Lada, Илюша, транспорт).
func _free_at(at: float) -> bool:
	var xf := _transform_at(at)
	xf.origin.y = minf(size.y, 1.8) * 0.5 + 0.05
	_body_query.transform = xf
	for result in get_world_3d().direct_space_state.intersect_shape(_body_query, 8):
		if _is_obstacle(result["collider"]):
			return false
	return true

func _apply_transform() -> void:
	global_transform = _transform_at(s)

func _transform_at(at: float) -> Transform3D:
	var front := path.position_at(at + wheelbase * 0.5)
	var rear := path.position_at(at - wheelbase * 0.5)
	var dir := front - rear
	var center := (front + rear) * 0.5
	return Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), Vector3(center.x, 0.0, center.z))

# --- для потомков ---

## Каждый кадр до расчёта скорости.
func _tick(_delta: float) -> void:
	pass

## Своё ограничение скорости (остановки троллейбуса).
func _extra_limit() -> float:
	return INF

## Укоротить шаг (не проскочить точку остановки).
func _limit_step(step: float) -> float:
	return step

func _build_visual() -> Node3D:
	return Node3D.new()

# --- облик: общие детали ---

func _box(parent: Node3D, name: String, box_size: Vector3, at: Vector3, material: Material, shadow := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	if not shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _cylinder(parent: Node3D, name: String, radius: float, width: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 14
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance

## Колесо: шина, колпак и спица — чтобы вращение было видно.
func _wheel(parent: Node3D, at: Vector3, radius: float, width: float) -> void:
	var tyre := Materials.plain(Color(0.05, 0.05, 0.05), 0.9)
	var hub := Materials.plain(Color(0.45, 0.44, 0.42), 0.5)
	var wheel := _cylinder(parent, "Wheel", radius, width, at, tyre)
	wheel.rotation.z = PI * 0.5
	var cap := _cylinder(wheel, "Hubcap", radius * 0.5, width + 0.02, Vector3.ZERO, hub)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(wheel, "Spoke", Vector3(radius * 1.5, width + 0.04, radius * 0.18), Vector3.ZERO, hub, false)
	_wheels.append(wheel)

func _lamp(color: Color, glow: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = energy
	return material

## Фары спереди (z = front) и габариты/стоп-сигналы сзади (z = rear).
func _lights(parent: Node3D, half_x: float, y: float, front: float, rear: float, head_size := Vector2(0.28, 0.16)) -> void:
	var head := _lamp(Color(1.0, 0.95, 0.80), Color(1.0, 0.90, 0.66), 2.2)
	for x in [-half_x, half_x]:
		_box(parent, "Headlight", Vector3(head_size.x, head_size.y, 0.04), Vector3(x, y, front), head, false)
		_box(parent, "Taillight", Vector3(0.3, 0.14, 0.04), Vector3(x, y + 0.02, rear), _tail, false)

func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _plate(parent: Node3D, y: float, z: float, yaw: float, text: String) -> void:
	var holder := Node3D.new()
	holder.name = "Plate"
	holder.position = Vector3(0, y, z)
	holder.rotation.y = yaw
	parent.add_child(holder)
	_box(holder, "PlateBase", Vector3(0.52, 0.12, 0.02), Vector3.ZERO, Materials.plain(Color(0.92, 0.92, 0.90), 0.5), false)
	var label := _label(text, 48, Color(0.05, 0.05, 0.05))
	label.pixel_size = 0.0016
	label.position = Vector3(0, 0, 0.012)
	holder.add_child(label)

func _paint(color: Color, roughness := 0.45) -> StandardMaterial3D:
	return Materials.plain(color, roughness)

# =====================================================================================

## Замкнутый путь по правой полосе: прямые и дуги скругления. s — метры вдоль пути от его начала.
## Начало (s = 0) — конец дуги в первой вершине RING, дальше — по порядку вершин.
class LanePath:
	var points := PackedVector3Array()
	var cumulative := PackedFloat32Array()
	var length := 0.0
	## Дуги поворотов: Vector2(начало, конец) по s.
	var arcs: Array[Vector2] = []
	## Оси улиц (вершины RING) — для проверки отклонения.
	var axis: Array[Vector3] = []
	var lane := 0.0
	var radius := 0.0

	## ring — вершины осей по ходу движения; lane — смещение вправо; radius — скругление.
	static func build(ring: Array, lane_offset: float, turn_radius: float, arc_steps := 24) -> LanePath:
		var path := LanePath.new()
		path.lane = lane_offset
		path.radius = turn_radius
		var n := ring.size()
		var corners: Array[Vector3] = []
		for i in n:
			var p: Vector3 = ring[i]
			path.axis.append(Vector3(p.x, 0.0, p.z))
		for i in n:
			var p := path.axis[i]
			var d_in := (p - path.axis[(i - 1 + n) % n]).normalized()
			var d_out := (path.axis[(i + 1) % n] - p).normalized()
			var n_in := right_of(d_in)
			var n_out := right_of(d_out)
			corners.append(p + (n_in + n_out) * lane_offset / (1.0 + n_in.dot(n_out)))
		# Начало — конец дуги первой вершины; дальше: прямая до начала следующей дуги, дуга.
		var pts := PackedVector3Array()
		for k in n:
			var i := (k + 1) % n
			var c := corners[i]
			var d_in := (c - corners[(i - 1 + n) % n]).normalized()
			var d_out := (corners[(i + 1) % n] - c).normalized()
			var half := d_in.angle_to(d_out) * 0.5
			var t := turn_radius * tan(half)
			var start := c - d_in * t
			var finish := c + d_out * t
			var turn_right := d_in.cross(d_out).y < 0.0
			var normal := right_of(d_in) if turn_right else -right_of(d_in)
			var center := start + normal * turn_radius
			if k == 0:
				var first := corners[0]
				var f_out := (corners[1] - first).normalized()
				var f_in := (first - corners[n - 1]).normalized()
				pts.append(first + f_out * turn_radius * tan(f_in.angle_to(f_out) * 0.5))
			pts.append(start)
			var arc_start_index := pts.size() - 1
			var v0 := start - center
			var sweep := v0.signed_angle_to(finish - center, Vector3.UP)
			for j in range(1, arc_steps + 1):
				pts.append(center + v0.rotated(Vector3.UP, sweep * j / arc_steps))
			path.arcs.append(Vector2(arc_start_index, pts.size() - 1))   # индексы; ниже — в метры
		# Последняя точка совпадает с первой — цикл.
		pts[pts.size() - 1] = pts[0]
		path.points = pts
		path.cumulative.resize(pts.size())
		var total := 0.0
		path.cumulative[0] = 0.0
		for i in range(1, pts.size()):
			total += pts[i].distance_to(pts[i - 1])
			path.cumulative[i] = total
		path.length = total
		for a in path.arcs.size():
			var arc := path.arcs[a]
			path.arcs[a] = Vector2(path.cumulative[int(arc.x)], path.cumulative[int(arc.y)])
		return path

	## Вправо по ходу для направления d (x — восток, z — юг): на запад → север, на юг → запад.
	static func right_of(d: Vector3) -> Vector3:
		return Vector3(-d.z, 0.0, d.x)

	func _segment(at: float) -> int:
		var lo := 0
		var hi := cumulative.size() - 1
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if cumulative[mid] <= at:
				lo = mid
			else:
				hi = mid
		return lo

	func position_at(at: float) -> Vector3:
		var u := fposmod(at, length)
		var i := _segment(u)
		var span := cumulative[i + 1] - cumulative[i]
		var k := 0.0 if span <= 0.0 else (u - cumulative[i]) / span
		return points[i].lerp(points[i + 1], k)

	func direction_at(at: float) -> Vector3:
		var u := fposmod(at, length)
		var i := _segment(u)
		return (points[i + 1] - points[i]).normalized()

	## Смещение s ближайшей к точке позиции на пути.
	func offset_of(p: Vector3) -> float:
		var best := INF
		var best_s := 0.0
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			var ab := b - a
			var len2 := ab.length_squared()
			var k := 0.0 if len2 <= 0.0 else clampf((Vector3(p.x, 0, p.z) - a).dot(ab) / len2, 0.0, 1.0)
			var q := a + ab * k
			var d := q.distance_squared_to(Vector3(p.x, 0, p.z))
			if d < best:
				best = d
				best_s = cumulative[i] + sqrt(len2) * k
		return best_s

	## Внутри дуги поворота (по s).
	func in_arc(at: float) -> bool:
		var u := fposmod(at, length)
		for arc in arcs:
			if u >= arc.x and u <= arc.y:
				return true
		return false

	## Расстояние от точки до ближайшей оси улицы (отрезки RING по кругу).
	func axis_distance(p: Vector3) -> float:
		var best := INF
		var q := Vector3(p.x, 0, p.z)
		for i in axis.size():
			var a := axis[i]
			var b := axis[(i + 1) % axis.size()]
			var ab := b - a
			var k := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, q.distance_to(a + ab * k))
		return best
