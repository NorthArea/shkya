extends SceneTree
## ARENA-01 T: транспорт кольца по контракту C8 на настоящей сцене main.tscn (набор TRAFFIC).
## Если интегратор ещё не подключил узел Traffic к LevelGeometry, тест добавляет его сам.
## Проверки: троллейбус — правая полоса RING (по часовой) со скруглением 6 м, машины — встречная правая полоса
## CAR_RING (ARENA-01 fix P2-2: B на север, C на запад, D на юг, A на восток; скругление CAR_TURN_RADIUS); корпуса
## машин по всему кругу ≥ 0,9 м от оси ROUTE_DRIVE на A и B и ≥ 0,8 м от припаркованных; старт — троллейбус
## START_OFFSET, машины равномерно, ≥ 20 м от CAR_SPAWN, стоянки «Лады» у киоска (конец ROUTE_DRIVE) и окна,
## VAN_PARK; слои тел; путь каждого корпуса не входит в коробки Layout.all_solids(); за прогон все три машины
## проходят полный круг, троллейбус стоит ≈6 с на обеих остановках со звуком дверей, отклонение от оси на
## прямых ≤ RING_LANE + 0,5, дистанция между своими ≥ 10 м; за 240 с ни одна машина не стоит в колонне за
## троллейбусом, встречные расходятся без касаний; машина тормозит перед стоящей на полосе «Ладой» и не сдвигает
## её, троллейбус — перед Илюшей; Илюша под бампером на 6 м/с — аварийное торможение ≤ 12 м/с² без касания
## (ARENA-01 fix P3); после ухода препятствия едут дальше; на паузе транспорт стоит, при открытом диалоге едет.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/traffic_test.gd

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const TrafficScript = preload("res://game/world/traffic.gd")

var failures: Array[String] = []
var checks := 0
var main: Node
var drv
var world: DemoWorld
var traffic: Node3D
var lane: PathVehicle.LanePath       # троллейбус
var car_lane: PathVehicle.LanePath   # машины, встречная
var _solids: Array = []
var _sim_time := 0.0
var _door_events: Array = []   # [время, "open"/"close", индекс остановки, позиция]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(1400.0, true, false, true).timeout.connect(func():
		push_error("FAIL: traffic test exceeded 1400 simulated seconds")
		_finish(2))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	await drv.frames(3)
	main.start_game()
	await drv.frames(10)
	world = main.world
	if not check(world != null, "DemoWorld exists"):
		_finish()
		return
	traffic = world.get_node_or_null("LevelGeometry/Traffic")
	if traffic == null:
		traffic = TrafficScript.new()
		world.get_node("LevelGeometry").add_child(traffic)
		print("INFO: Traffic attached by the test (LevelGeometry has no Traffic yet)")
	else:
		print("INFO: Traffic attached by LevelGeometry")
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false   # наблюдатели не мешают: Илюша стоит на дорогах
	await drv.frames(3)
	lane = traffic.path
	car_lane = traffic.car_path
	for spec in Layout.all_solids():
		_solids.append([spec[0], spec[2], spec[3]])
	traffic.trolleybus.doors_opened.connect(func(i): _door_events.append([_sim_time, "open", i, traffic.trolleybus.global_position]))
	traffic.trolleybus.doors_closed.connect(func(i): _door_events.append([_sim_time, "close", i, traffic.trolleybus.global_position]))
	physics_frame.connect(func(): _sim_time += 1.0 / Engine.physics_ticks_per_second)
	_part_path()
	_part_start()
	_part_sweep()
	_part_side_room_profiles()
	_part_people()
	await _part_laps()
	await _part_oncoming()
	await _part_lada_block()
	await _part_lada_head_on()
	await _part_lada_head_on_drive()
	await _part_player_block()
	await _part_hard_brake()
	await _part_pause_and_dialog()
	await _part_closure()
	drv.release_all()
	_finish()

# =====================================================================================
# TROLLEY-01: водитель и пассажиры в салоне
# =====================================================================================

## Водитель за рулём виден снаружи: геометрический луч от точки обзора до головы проходит через стекло (лобовое —
## между стойками, боковое — в оконном поясе и не по простенку); пассажиров 3–8, головы в оконном поясе, все внутри
## салона; ни тел, ни коллизий; дальше 60 м не рисуются.
func _part_people() -> void:
	print("--- TROLLEY-01 people ---")
	var bus: Trolleybus = traffic.trolleybus
	var people: Node3D = bus.people
	if not check(people != null and people.driver != null, "trolleybus has Passengers with a driver"):
		return
	var driver: Node3D = people.driver
	var head: Vector3 = driver.position + Vector3(0, 1.62, 0)   # центр головы мужика в ушанке (рост 1,8 м на холсте 2,0)
	var top := _sprite_top(driver)
	check(driver.visible and driver.sprite != null and driver.character.begins_with("resident_"), "driver: resident look %s, visible" % driver.character)
	check(top > Trolleybus.SILL + 0.4 and top < Trolleybus.EAVE - 0.05, "driver's head in the window band: head top %.2f m (%.2f–%.2f)" % [top, Trolleybus.SILL + 0.4, Trolleybus.EAVE - 0.05])
	check(driver.position.x < -0.3 and driver.position.z < -4.6 and driver.position.z > -Trolleybus.HALF_LEN + 0.5, "driver sits left, behind the wheel (%s)" % driver.position)
	# Лобовое: точка обзора спереди-слева на высоте глаз камеры.
	for eye in [Vector3(-1.5, 2.8, -16.0), Vector3(1.0, 3.2, -12.0)]:
		var t: float = (-Trolleybus.HALF_LEN - eye.z) / (head.z - eye.z)
		var hit: Vector3 = eye.lerp(head, t)
		check(hit.x > -1.08 and hit.x < -0.06 and hit.y > Trolleybus.SILL + 0.05 and hit.y < Trolleybus.EAVE - 0.05,
			"driver seen through the windscreen from %s (crosses at x %.2f, y %.2f)" % [eye, hit.x, hit.y])
	# Боковое слева: стёкла между простенками (как в trolleybus.gd _meshes).
	var posts: Array[float] = []
	for span in Trolleybus._free_spans(false):
		var count := maxi(1, ceili((float(span[1]) - float(span[0])) / 1.45))
		for k in count + 1:
			posts.append(float(span[0]) + (float(span[1]) - float(span[0])) / count * k)
	for eye in [Vector3(-9.0, 3.0, -5.0), Vector3(-7.0, 3.5, -2.0)]:
		var t: float = (-Trolleybus.HALF_W - eye.x) / (head.x - eye.x)
		var hit: Vector3 = eye.lerp(head, t)
		var clear := hit.y > Trolleybus.SILL + 0.05 and hit.y < Trolleybus.EAVE - 0.05 and hit.z > -Trolleybus.HALF_LEN + 0.45
		for p in posts:
			clear = clear and absf(hit.z - p) > 0.1
		check(clear, "driver seen through the left side window from %s (crosses at y %.2f, z %.2f)" % [eye, hit.y, hit.z])
	# Стенка за водителем и руль не на голове.
	check(head.z < -4.6 and head.y > Trolleybus.SILL + 0.25 + 0.3, "driver's head clear of the partition (z −4.55) and the wheel (y %.2f)" % (Trolleybus.SILL + 0.25))
	var shown: Array = people.shown()
	check(shown.size() >= 3 and shown.size() <= 8, "passengers in the cabin: %d (3–8)" % shown.size())
	var looks := {}
	var inside := true
	var heads := true
	for p in shown:
		looks[p.character] = true
		inside = inside and absf(p.position.x) < Trolleybus.HALF_W - 0.3 and absf(p.position.z) < Trolleybus.HALF_LEN - 0.6
		var y := _sprite_top(p)
		heads = heads and y > Trolleybus.SILL + 0.35 and y < Trolleybus.EAVE - 0.05
	check(looks.size() == shown.size(), "passengers all look different (%s)" % [looks.keys()])
	var allowed := {}
	for l in Layout.RESIDENT_LOOKS:
		allowed["resident_%s" % l] = true
	check(looks.keys().all(func(c): return allowed.has(c)) and allowed.has(driver.character), "driver and passengers — only RESIDENT_LOOKS")
	check(inside, "every passenger inside the cabin (|x| < %.2f, |z| < %.2f)" % [Trolleybus.HALF_W - 0.3, Trolleybus.HALF_LEN - 0.6])
	check(heads, "every passenger's head in the window band")
	var bodies := people.find_children("*", "CollisionObject3D", true, false).size() + people.find_children("*", "CollisionShape3D", true, false).size()
	check(bodies == 0, "no bodies or collision shapes among the people (C2): %d" % bodies)
	var lod := true
	for p in shown + [driver]:
		lod = lod and is_equal_approx(p.sprite.visibility_range_end, 60.0) and p.get_node_or_null("Shadow") == null
	check(lod, "people sprites hidden beyond 60 m, no ground shadow blobs")
	check(not shown.any(func(p): return p.is_in_group(&"residents") or p.is_in_group(&"detection_sensors")), "people in the cabin are not residents and not stealth sensors")

## Макушка облика в осях троллейбуса, м: самый высокий житель — 1,83 м на холсте 2,0 м (Residents.SILHOUETTES).
func _sprite_top(p: Node3D) -> float:
	return p.position.y + 1.83 * p.height_m / 2.0

# =====================================================================================
# 1. Путь: правая полоса, по часовой стрелке, скругление 6 м
# =====================================================================================

func _part_path() -> void:
	print("--- path ---")
	var straight := 0.0
	for i in 4:
		var a: Vector3 = Layout.RING[i]
		var b: Vector3 = Layout.RING[(i + 1) % 4]
		straight += a.distance_to(b) - 2.0 * Layout.RING_LANE   # полоса — прямоугольник, вписанный на RING_LANE
	var expected := straight - 4.0 * (2.0 * PathVehicle.TURN_RADIUS - PI * PathVehicle.TURN_RADIUS * 0.5)
	check(absf(lane.length - expected) < 0.05, "lane loop length %.2f m (expected %.2f)" % [lane.length, expected])
	check(lane.arcs.size() == 4, "four rounded corners (%d)" % lane.arcs.size())
	# Сторона и направление: середины улиц.
	var mids := [[Vector3(0, 0, 29), Vector3(-1, 0, 0), "A westbound z=29"], [Vector3(-57, 0, -34), Vector3(0, 0, -1), "D northbound x=-57"],
		[Vector3(5, 0, -97), Vector3(1, 0, 0), "C eastbound z=-97"], [Vector3(67, 0, -34), Vector3(0, 0, 1), "B southbound x=67"]]
	for m in mids:
		var at := lane.offset_of(m[0])
		check(lane.position_at(at).distance_to(m[0]) < 0.01 and lane.direction_at(at).dot(m[1]) > 0.999, "lane %s" % m[2])
	var worst_straight := 0.0
	var worst_arc := 0.0
	var at := 0.0
	while at < lane.length:
		var d := lane.axis_distance(lane.position_at(at))
		if lane.in_arc(at):
			worst_arc = maxf(worst_arc, d)
		else:
			worst_straight = maxf(worst_straight, absf(d - Layout.RING_LANE))
		at += 0.5
	check(worst_straight < 0.01, "straights: lane is RING_LANE from the street axis (max error %.3f m)" % worst_straight)
	var arc_bound := Layout.RING_LANE + PathVehicle.TURN_RADIUS * (1.0 - cos(PI / 4.0)) + 0.01
	check(worst_arc <= arc_bound, "corners: lane within %.2f m of the nearer axis (max %.2f m)" % [arc_bound, worst_arc])
	# Полоса машин — встречная (ARENA-01 fix P2-2).
	var r := PathVehicle.CAR_TURN_RADIUS
	var car_expected := straight + 16.0 * Layout.RING_LANE - 4.0 * (2.0 * r - PI * r * 0.5)   # внешний прямоугольник: +2·RING_LANE на сторону
	check(absf(car_lane.length - car_expected) < 0.05, "car lane loop length %.2f m (expected %.2f)" % [car_lane.length, car_expected])
	var car_mids := [[Vector3(0, 0, 35), Vector3(1, 0, 0), "A eastbound z=35"], [Vector3(73, 0, -34), Vector3(0, 0, -1), "B northbound x=73"],
		[Vector3(5, 0, -103), Vector3(-1, 0, 0), "C westbound z=-103"], [Vector3(-63, 0, -34), Vector3(0, 0, 1), "D southbound x=-63"]]
	for m in car_mids:
		var c_at := car_lane.offset_of(m[0])
		check(car_lane.position_at(c_at).distance_to(m[0]) < 0.01 and car_lane.direction_at(c_at).dot(m[1]) > 0.999, "car lane %s" % m[2])
	var car_worst := 0.0
	at = 0.0
	while at < car_lane.length:
		if not car_lane.in_arc(at):
			car_worst = maxf(car_worst, absf(car_lane.axis_distance(car_lane.position_at(at)) - Layout.RING_LANE))
		at += 0.5
	check(car_worst < 0.01, "car lane straights: RING_LANE from the street axis (max error %.3f m)" % car_worst)
	# Ось «Лады» (ROUTE_DRIVE по A на восток и по B на север) и припаркованные машины — от корпусов машин по кругу.
	var drive_axis: Array = [[Vector2(0, 32), Vector2(70, 32)], [Vector2(70, 32), Vector2(70, -46)]]
	var parked: Array = []
	for spec in Layout.all_solids():
		if spec[1] == "parked_car":
			parked.append([spec[0], spec[2], Vector2(spec[3].x, spec[3].z)])
	for kind in TrafficCar.KINDS:
		var spec: Dictionary = TrafficCar.KINDS[kind]
		var size: Vector3 = spec["size"]
		var wb: float = spec["wheelbase"]
		var min_axis := INF
		var min_parked := INF
		var min_parked_name := ""
		at = 0.0
		while at < car_lane.length:
			var front := car_lane.position_at(at + wb * 0.5)
			var rear := car_lane.position_at(at - wb * 0.5)
			var corners := _obb_corners(_flat((front + rear) * 0.5), _flat(front - rear).normalized(), Vector2(size.x, size.z))
			for seg in drive_axis:
				for c in corners:
					min_axis = minf(min_axis, c.distance_to(Geometry2D.get_closest_point_to_segment(c, seg[0], seg[1])))
				for e in seg:
					min_axis = minf(min_axis, _point_obb_distance(e, corners))
			for pc in parked:
				var d := _obb_rect_distance(corners, pc[1], pc[2])
				if d < min_parked:
					min_parked = d
					min_parked_name = "%s@(%.1f,%.1f)" % [pc[0], pc[1].x, pc[1].y]
			at += 0.25
		check(min_axis >= 0.9, "%s body on the car lane keeps ≥ 0.9 m from the ROUTE_DRIVE axis on A and B (%.2f m)" % [kind, min_axis])
		check(min_parked >= 0.8, "%s body on the car lane keeps ≥ 0.8 m from parked cars (%.2f m, %s)" % [kind, min_parked, min_parked_name])

# =====================================================================================
# 2. Состав и старт
# =====================================================================================

func _part_start() -> void:
	print("--- start ---")
	check(traffic.cars.size() == Layout.TRAFFIC_CARS, "TRAFFIC_CARS = %d cars on the ring (%d)" % [Layout.TRAFFIC_CARS, traffic.cars.size()])
	var kinds := {}
	for car in traffic.cars:
		kinds[car.kind] = true
	check(kinds.size() == 3 and kinds.has(&"zhiguli") and kinds.has(&"volga") and kinds.has(&"gazelle"), "three silhouettes: Жигули, Волга, Газель (%s)" % [kinds.keys()])
	check(traffic.trolleybus is Trolleybus, "trolleybus 13 on the ring")
	for v in traffic.vehicles:
		check(v is AnimatableBody3D and v.collision_layer == 1 and v.collision_mask == 0, "%s: AnimatableBody3D, layer 1, mask 0" % v.name)
		check(v.is_in_group(PathVehicle.GROUP), "%s in group traffic_vehicles" % v.name)
	check(traffic.cars.all(func(c): return is_equal_approx(c.cruise_speed, 9.0)) and is_equal_approx(traffic.trolleybus.cruise_speed, 7.0), "speeds: cars 9 m/s, trolleybus 7 m/s")
	var offsets: Array[float] = TrafficScript.start_offsets(lane.length, car_lane.length)
	check(offsets == TrafficScript.start_offsets(lane.length, car_lane.length), "start offsets are constants (same on a second call)")
	check(traffic.trolleybus.path == lane and traffic.cars.all(func(c): return c.path == car_lane), "trolleybus on RING, cars on the oncoming CAR_RING lane")
	check(traffic.cars.all(func(c): return c.peers == traffic.cars) and traffic.trolleybus.peers == [traffic.trolleybus], "follow distance only to own lane (cars ↔ cars)")
	var step := car_lane.length / Layout.TRAFFIC_CARS
	for i in offsets.size():
		var v: PathVehicle = traffic.vehicles[i]
		var p := v.path.position_at(offsets[i])
		var name: String = v.name
		var d_car := _flat(p).distance_to(_flat(Layout.CAR_SPAWN))
		# Киоск — стоянка «Лады» (конец ROUTE_DRIVE) и окно: KIOSK_ZONE после EXT-01 захватывает край улицы B
		# у заезда на парковку, и полоса кольца идёт вдоль неё — мерить до коробки зоны стало бессмысленно.
		var d_kiosk := minf(_flat(p).distance_to(_flat(Layout.ROUTE_DRIVE[-1])), _flat(p).distance_to(_flat(Layout.VENDOR_WINDOW)))
		var d_van := _flat(p).distance_to(_flat(Layout.VAN_PARK))
		check(d_car >= 20.0 and d_kiosk >= 20.0 and d_van >= 20.0, "%s starts at (%.1f, %.1f): CAR_SPAWN %.1f, kiosk parking/window %.1f, VAN_PARK %.1f m (≥ 20)" % [name, p.x, p.z, d_car, d_kiosk, d_van])
		if v != traffic.trolleybus:
			var next := 1 + (i % Layout.TRAFFIC_CARS)   # индекс следующей машины в vehicles (0 — троллейбус)
			var gap := fposmod(offsets[next] - offsets[i], car_lane.length)
			check(absf(gap - step) < 0.01, "%s: next car %.1f m ahead (even spacing %.1f)" % [name, gap, step])
	var stops: Array[float] = traffic.trolleybus.stop_offsets
	for i in Layout.TROLLEY_STOPS.size():
		var stop: Vector3 = Layout.TROLLEY_STOPS[i]
		check(lane.position_at(stops[i]).distance_to(stop) < 0.05, "trolley stop %d %s lies on the lane" % [i, stop])

# =====================================================================================
# 3. Путь корпуса каждого транспорта против коробок Layout.all_solids() (шаг 0,5 м, по кругу)
# =====================================================================================

func _part_sweep() -> void:
	print("--- sweep vs Layout.all_solids() ---")
	for v in traffic.vehicles:
		var hits := {}
		var at := 0.0
		while at < v.path.length:
			var xf: Transform3D = v._transform_at(at)
			for solid in _overlaps(xf, v.size):
				if not hits.has(solid[0]):
					hits[solid[0]] = "%s@(%.0f,%.0f) at (%.1f, %.1f)" % [solid[0], solid[1].x, solid[1].y, xf.origin.x, xf.origin.z]
			at += 0.5
		check(hits.is_empty(), "%s: swept body enters no solid box%s" % [v.name, "" if hits.is_empty() else " — " + ", ".join(hits.values())])

# =====================================================================================
# 4. Прогон: полный круг, остановки, полоса, дистанция, коробки, никого не толкают
# =====================================================================================

func _part_laps() -> void:
	print("--- laps ---")
	traffic.reset_positions()
	var lada_at: Vector3 = world.car.global_position
	var player_at: Vector3 = world.player.global_position
	var worst_lane := 0.0
	var worst_corner := 0.0
	var min_gap := INF
	var solid_hits := {}
	var t0 := _sim_time
	_door_events.clear()
	var max_frames := 200 * 60
	var lap_done_at := -1.0
	var turn_at_stop := 0.0      # TROLLEY-01: голова водителя к дверям на стоянке
	var turn_driving := 0.0      # и прямо в пути (через 3 с после отправления)
	var since_dwell := 0.0
	for frame in max_frames:
		await physics_frame
		var bus: Trolleybus = traffic.trolleybus
		since_dwell = 0.0 if bus.doors_open else since_dwell + 1.0 / 60.0
		if bus.doors_open:
			turn_at_stop = minf(turn_at_stop, bus.people.driver.rotation.y)
		elif since_dwell > 3.0:
			turn_driving = maxf(turn_driving, absf(bus.people.driver.rotation.y))
		for v in traffic.vehicles:
			var front: float = v.s + v.wheelbase * 0.5
			var rear: float = v.s - v.wheelbase * 0.5
			var d: float = v.path.axis_distance(v.global_position)
			if v.path.in_arc(front) or v.path.in_arc(rear) or v.path.in_arc(v.s):
				worst_corner = maxf(worst_corner, d)
			else:
				worst_lane = maxf(worst_lane, absf(d - Layout.RING_LANE))
		for i in traffic.vehicles.size():
			var a: PathVehicle = traffic.vehicles[i]
			for b in traffic.vehicles:
				if b == a or b.path != a.path:
					continue
				var ahead := fposmod(b.s - a.s, a.path.length)
				if ahead < a.path.length * 0.5:
					min_gap = minf(min_gap, ahead - a.size.z * 0.5 - b.size.z * 0.5)
		if frame % 10 == 0:
			for v in traffic.vehicles:
				for solid in _overlaps(v.global_transform, v.size):
					solid_hits[solid[0]] = "%s in %s@(%.0f,%.0f)" % [v.name, solid[0], solid[1].x, solid[1].y]
		var laps_ok := _cars_lapped()
		if laps_ok and traffic.trolleybus.stops_made >= 2 and _door_events.size() >= 4 and lap_done_at < 0.0:
			lap_done_at = _sim_time - t0
			break
	for car in traffic.cars:
		check(car.distance_travelled >= car_lane.length, "%s made a full lap (%.0f of %.0f m)" % [car.name, car.distance_travelled, car_lane.length])
	check(lap_done_at > 0.0, "all cars lapped and the trolleybus served both stops in %.0f s (limit 200 s)" % (lap_done_at if lap_done_at > 0.0 else _sim_time - t0))
	check(worst_lane <= 0.5, "straights: distance to the street axis within RING_LANE ± 0.5 (worst %.3f m)" % worst_lane)
	check(worst_corner <= 6.0, "corners: body centre stays on the carriageway, ≤ 6 m from the axis (worst %.2f m)" % worst_corner)
	check(min_gap >= _follow_gap_min(), "own vehicles keep ≥ 10 m bumper to bumper (min %.2f m)" % min_gap)
	check(solid_hits.is_empty(), "no vehicle inside a Layout solid during the run%s" % ("" if solid_hits.is_empty() else " — " + ", ".join(solid_hits.values().slice(0, 8))))
	check(_flat(world.car.global_position).distance_to(_flat(lada_at)) < 0.05, "parked Lada not moved by traffic")
	check(_flat(world.player.global_position).distance_to(_flat(player_at)) < 0.05, "Ilyusha not moved by traffic")
	# Остановки троллейбуса: открыл — 6 с — закрыл, на точке остановки, обе.
	var served := {}
	for i in _door_events.size():
		var e: Array = _door_events[i]
		if e[1] != "open" or i + 1 >= _door_events.size():
			continue
		var c: Array = _door_events[i + 1]
		var dwell: float = c[0] - e[0]
		var stop: Vector3 = Layout.TROLLEY_STOPS[e[2]]
		var off := _flat(e[3]).distance_to(_flat(stop))
		var still := _flat(e[3]).distance_to(_flat(c[3]))
		check(absf(dwell - Trolleybus.DWELL) <= 0.1 and off < 0.3 and still < 0.01 and c[1] == "close", "trolley stop %d %s: stood %.2f s (≈6), %.2f m from the stop point, moved %.3f m while doors open" % [e[2], stop, dwell, off, still])
		served[e[2]] = true
	check(served.size() == Layout.TROLLEY_STOPS.size(), "trolleybus served both TROLLEY_STOPS (%s)" % [served.keys()])
	check(turn_at_stop < -0.6 and turn_driving < 0.05, "driver turns his head to the doors at stops (%.2f rad) and looks ahead while driving (%.2f)" % [turn_at_stop, turn_driving])
	var sound: Node = world.get_node_or_null("SoundDirector")
	if sound:
		check(sound.played.get("trolley_doors", 0) >= 4, "door sound played at the stops (%d times)" % sound.played.get("trolley_doors", 0))
		var engines := 0
		for v in traffic.vehicles:
			var p: AudioStreamPlayer3D = v.get_node_or_null("TrafficEngine")
			if p and p.stream != null and p.max_distance > 0.0:
				engines += 1
		check(engines == traffic.vehicles.size(), "every vehicle has a distance-attenuated engine/hum player (%d)" % engines)

func _follow_gap_min() -> float:
	return PathVehicle.FOLLOW_GAP - 0.05

func _cars_lapped() -> bool:
	for car in traffic.cars:
		if car.distance_travelled < car_lane.length:
			return false
	return true

# =====================================================================================
# 4а. 240 с: машины не стоят в колонне за троллейбусом, встречные расходятся без касаний (ARENA-01 fix P2-2)
# =====================================================================================

func _part_oncoming() -> void:
	print("--- oncoming, 240 s ---")
	traffic.reset_positions()
	var bus: Trolleybus = traffic.trolleybus
	var column := {}           # машина → кадров «за троллейбусом в одну сторону и медленно»
	var standing := {}         # машина → самый длинный простой подряд, кадров
	var run := {}
	var min_oncoming := INF
	var min_any := INF
	var passes := 0
	var close := {}            # пара → была ли рядом в прошлом кадре (для счёта разъездов)
	var dist0: Array = traffic.cars.map(func(c): return c.distance_travelled)
	for frame in 240 * 60:
		await physics_frame
		var bus_f: Vector2 = bus.footprint()[1]
		for car in traffic.cars:
			var fp: Array = car.footprint()
			var to_bus: Vector2 = _flat(bus.global_position) - fp[0]
			var along: float = to_bus.dot(fp[1])
			var across := absf(to_bus.dot(Vector2(-fp[1].y, fp[1].x)))
			if car.blocked_by == bus or (fp[1].dot(bus_f) > 0.7 and along > 0.0 and along < 25.0 and across < 2.5 and car.speed < 7.5):
				column[car.name] = column.get(car.name, 0) + 1
			run[car.name] = run.get(car.name, 0) + 1 if car.speed < 0.05 else 0
			standing[car.name] = maxi(standing.get(car.name, 0), run[car.name])
		var vs: Array = traffic.vehicles
		for i in vs.size():
			for j in range(i + 1, vs.size()):
				var a: PathVehicle = vs[i]
				var b: PathVehicle = vs[j]
				var pair := "%s|%s" % [a.name, b.name]
				if _flat(a.global_position).distance_to(_flat(b.global_position)) > 20.0:
					close[pair] = false
					continue
				var d := _poly_distance(_footprint_corners(a), _footprint_corners(b))
				min_any = minf(min_any, d)
				if a.footprint()[1].dot(b.footprint()[1]) < -0.3 or a.path != b.path:
					min_oncoming = minf(min_oncoming, d)
					if not close.get(pair, false):
						passes += 1
					close[pair] = true
	for car in traffic.cars:
		check(column.get(car.name, 0) == 0, "%s never queues behind the trolleybus in 240 s (%d frames)" % [car.name, column.get(car.name, 0)])
	var laps := INF
	for i in traffic.cars.size():
		laps = minf(laps, (traffic.cars[i].distance_travelled - dist0[i]) / car_lane.length)
	print("INFO: longest stand per car (frames) %s, oncoming encounters %d" % [standing, passes])
	check(laps >= 3.0, "every car makes ≥ 3 laps in 240 s (min %.2f) — nobody stuck in a column" % laps)
	check(passes >= 10, "cars and the trolleybus meet head-on on the ring (%d encounters within 20 m)" % passes)
	check(min_oncoming >= 1.0, "oncoming vehicles pass without touching (min body gap %.2f m, ≥ 1)" % min_oncoming)
	check(min_any > 0.0, "no two vehicles ever overlap (min body gap %.2f m)" % min_any)

# =====================================================================================
# 5. «Лада» стоит на полосе: машина тормозит, не трогает её, ждёт; «Лада» ушла — едет
# =====================================================================================

func _part_lada_block() -> void:
	print("--- Lada blocks the lane ---")
	traffic.reset_positions()
	var lada_point := Vector3(73, 0, -40)   # улица B, полоса машин на север; «Жигули» стартуют южнее (z ≈ 1)
	var at := car_lane.offset_of(lada_point)
	var dir := car_lane.direction_at(at)
	var car: PathVehicle = _vehicle_behind(at, car_lane)
	world.car.reset_to(lada_point, atan2(-dir.x, -dir.z))
	await drv.frames(2)
	var lada_at: Vector3 = world.car.global_position
	var waited := 0
	var min_gap := INF
	while waited < 30 * 60 and car.blocked_time < 3.5:
		await physics_frame
		waited += 1
		var gap := fposmod(at - car.s, car_lane.length) - car.size.z * 0.5 - Lada.SIZE.z * 0.5
		min_gap = minf(min_gap, gap)
	check(car is TrafficCar, "a car (not the trolleybus) comes up behind the Lada (%s)" % car.name)
	check(car.blocked_by == world.car, "%s stopped for the Lada (blocked by %s)" % [car.name, car.blocked_by.name if car.blocked_by else "nothing"])
	check(car.speed == 0.0 and car.blocked_time >= 3.0, "%s waits standing ≥ 3 s (%.1f s), no overtaking" % [car.name, car.blocked_time])
	check(min_gap > 2.5 and min_gap <= PathVehicle.SENSOR_RANGE, "%s stopped %.2f m short of the Lada (2.5…8)" % [car.name, min_gap])
	check(_flat(world.car.global_position).distance_to(_flat(lada_at)) < 0.05, "Lada not pushed (moved %.3f m)" % _flat(world.car.global_position).distance_to(_flat(lada_at)))
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	var resumed := await _wait_until(func(): return car.speed > 1.0, 5 * 60)
	check(resumed >= 0, "%s drives on after the Lada leaves (%d frames)" % [car.name, resumed])

# =====================================================================================
# 5б. POLISH-03 C: «Лада» встала носом навстречу в полосе машин (критик 30.10, k_09_back_pt04: 27 с лоб в лоб у A∩B).
# Shared path queries must not inherit another car's clearance result.
# The witness is selected by real Layout geometry, without reading provider cache/state.
func _part_side_room_profiles() -> void:
	var sizes: Array = traffic.cars.map(func(car): return car.size)
	sizes.sort_custom(func(a, b): return a.x < b.x)
	if not check(sizes.size() >= 3, "side-room oracle uses all three actual traffic bodies"):
		return
	var narrow: Vector3 = sizes[0]
	var wide: Vector3 = sizes[-1]
	var clear := PathVehicle.YIELD_CLEAR
	var maximum := PathVehicle.SIDE_MAX
	var witness := -1.0
	var narrow_room := 0.0
	var wide_room := 0.0
	for metre in ceili(car_lane.length):
		var at := metre + 0.5
		var a := _side_room_geometry(at, narrow, clear, maximum)
		var b := _side_room_geometry(at, wide, clear, maximum)
		if a >= b + 0.19 and a > 0.0 and _overlaps(_side_room_pose(at, 0.0), wide + Vector3(clear * 2.0, 0.0, clear * 2.0)).is_empty():
			witness = at
			narrow_room = a
			wide_room = b
			break
	if not check(witness >= 0.0, "real static corridor permits a larger side offset for the narrow body"):
		return
	print("INFO: side-room geometric witness s=%.1f narrow=%.2f wide=%.2f" % [witness, narrow_room, wide_room])
	var narrow_padded := narrow + Vector3(clear * 2.0, 0.0, clear * 2.0)
	var wide_padded := wide + Vector3(clear * 2.0, 0.0, clear * 2.0)
	check(_overlaps(_side_room_pose(witness, narrow_room), narrow_padded).is_empty(), "narrow body's geometric witness is outside the actual static corridor walls")
	check(not _overlaps(_side_room_pose(witness, narrow_room), wide_padded).is_empty(), "the same offset is unsafe for the real wide body")
	var profiles: Array = []
	for size: Vector3 in sizes:
		profiles.append([size, clear, maximum])
	profiles.append([narrow, clear + 0.2, maximum])
	profiles.append([narrow, clear, minf(1.0, maximum)])
	var expected: Array = []
	for profile in profiles:
		var fresh := PathVehicle.LanePath.build(Layout.CAR_RING, Layout.RING_LANE, PathVehicle.CAR_TURN_RADIUS)
		expected.append(fresh.side_room(witness, profile[0], profile[1], profile[2]))
	check(absf(expected[0] - narrow_room) <= 0.01 and absf(expected[sizes.size() - 1] - wide_room) <= 0.01, "fresh provider queries agree with independently selected corridor geometry")
	for backwards in [false, true]:
		var shared := PathVehicle.LanePath.build(Layout.CAR_RING, Layout.RING_LANE, PathVehicle.CAR_TURN_RADIUS)
		var order: Array = range(profiles.size())
		if backwards:
			order.reverse()
		for i in order:
			var profile: Array = profiles[i]
			var actual := shared.side_room(witness, profile[0], profile[1], profile[2])
			check(absf(actual - expected[i]) <= 0.00001, "shared side-room query matches a fresh path for profile %d in %s order" % [i, "wide-to-narrow" if backwards else "narrow-to-wide"])
			var padded: Vector3 = profile[0] + Vector3(profile[1] * 2.0, 0.0, profile[1] * 2.0)
			check(actual <= profile[2] + 0.00001 and _overlaps(_side_room_pose(witness, actual), padded).is_empty(), "profile %d returned offset respects its own static clearance and side limit" % i)

func _side_room_geometry(at: float, size: Vector3, clear: float, maximum: float) -> float:
	var padded := size + Vector3(clear * 2.0, 0.0, clear * 2.0)
	var room := 0.0
	for step in range(1, floori(maximum * 10.0) + 1):
		var offset := step / 10.0
		if not _overlaps(_side_room_pose(at, offset), padded).is_empty():
			break
		room = offset
	return room

func _side_room_pose(at: float, offset: float) -> Transform3D:
	var p := car_lane.position_at(at)
	var d := car_lane.direction_at(at)
	var right := Vector3(-d.z, 0.0, d.x).normalized()
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), p + right * offset)

# Машина тормозит, ждёт не дольше YIELD_DELAY, прижимается вправо к обочине и медленно разъезжается, не касаясь
# «Лады» и коробок Layout; за «Ладой» возвращается в полосу.
# =====================================================================================

func _part_lada_head_on() -> void:
	print("--- Lada head-on in the car lane ---")
	traffic.reset_positions()
	var lada_point := Vector3(58.9, 0, 34.3)   # улица A, полоса машин на восток; точка застревания бота критика
	var at := car_lane.offset_of(lada_point)
	var car: PathVehicle = _vehicle_behind(at, car_lane)
	world.car.reset_to(lada_point, PI * 0.5)   # носом на запад, навстречу
	await drv.frames(2)
	var lada_at: Vector3 = world.car.global_position
	var lada_box := [_flat(lada_at), Vector2(-1, 0), Vector2(Lada.SIZE.x, Lada.SIZE.z)]
	var first_block := -1.0
	var passed_at := -1.0
	var max_blocked := 0.0
	var min_gap := INF
	var max_side := 0.0
	var yield_at := -1.0
	var solid_hits := {}
	var t0 := _sim_time
	for frame in 60 * 60:
		await physics_frame
		if car.blocked_by == world.car and car.speed < 0.05 and first_block < 0.0:
			first_block = _sim_time - t0   # встала перед «Ладой»
		if car.yielding and yield_at < 0.0:
			yield_at = _sim_time - t0
		max_blocked = maxf(max_blocked, car.blocked_time)
		max_side = maxf(max_side, absf(car.side))
		min_gap = minf(min_gap, _poly_distance(_footprint_corners(car), _obb_corners(lada_box[0], lada_box[1], lada_box[2])))
		if frame % 10 == 0:
			for solid in _overlaps(car.global_transform, car.size):
				solid_hits[solid[0]] = "%s@(%.0f,%.0f)" % [solid[0], solid[1].x, solid[1].y]
		var ahead := fposmod(at - car.s, car_lane.length)
		if passed_at < 0.0 and first_block >= 0.0 and ahead > car_lane.length * 0.5:
			passed_at = _sim_time - t0
		if passed_at >= 0.0 and _sim_time - t0 > passed_at + 6.0:
			break
	check(car is TrafficCar and first_block >= 0.0, "%s comes up and stops for the oncoming Lada (after %.1f s)" % [car.name, first_block])
	check(yield_at >= 0.0 and yield_at - first_block <= PathVehicle.YIELD_DELAY + 0.5, "%s starts pulling over %.1f s after stopping (≤ %.1f)" % [car.name, yield_at - first_block, PathVehicle.YIELD_DELAY + 0.5])
	var stand_max := PathVehicle.YIELD_DELAY + PathVehicle.SIDE_MAX / PathVehicle.SIDE_RATE + 0.5
	check(max_blocked <= stand_max, "%s stands nose to nose no longer than %.1f s (%.1f s)" % [car.name, stand_max, max_blocked])
	check(passed_at >= 0.0 and passed_at - first_block <= 10.0, "%s squeezes past the Lada %.1f s after stopping (≤ 10 s)" % [car.name, passed_at - first_block if passed_at >= 0.0 else -1.0])
	check(max_side > 0.5 and max_side <= PathVehicle.SIDE_MAX + 0.01, "%s pulls over to the kerb by %.2f m (≤ %.1f)" % [car.name, max_side, PathVehicle.SIDE_MAX])
	check(min_gap > 0.2, "%s never touches the Lada (min body gap %.2f m)" % [car.name, min_gap])
	check(solid_hits.is_empty(), "%s stays out of Layout solids while yielding%s" % [car.name, "" if solid_hits.is_empty() else " — " + ", ".join(solid_hits.values())])
	check(absf(car.side) < 0.05, "%s is back in its lane after the Lada (side %.2f m)" % [car.name, car.side])
	check(_flat(world.car.global_position).distance_to(_flat(lada_at)) < 0.05, "Lada not pushed (moved %.3f m)" % _flat(world.car.global_position).distance_to(_flat(lada_at)))
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	await drv.frames(2)

## Как бот критика: «Лада» после поворота с B на A едет на запад по полосе машин (z ≈ 34,3) к (0; 32), навстречу —
## машина кольца. Проезд не блокируется дольше нескольких секунд.
func _part_lada_head_on_drive() -> void:
	print("--- Lada drives west in the car lane ---")
	traffic.reset_positions()
	var start := Vector3(66, 0, 34.3)
	var at := car_lane.offset_of(Vector3(50, 0, 35))
	var car: PathVehicle = _vehicle_behind(at, car_lane)
	# Машину — за 30 м до встречи, чтобы встреча была сразу; Илюша за рулём.
	car.setup(car_lane, at - 30.0)
	world.car.reset_to(start, PI * 0.5)
	world.enter_car()
	await drv.frames(5)
	var t0 := _sim_time
	var ok: bool = await drv.drive_path([Vector3(30, 0, 32)], 9.0)
	var took := _sim_time - t0
	drv.release_all()
	check(ok, "Lada gets past the oncoming %s along A (%s)" % [car.name, "ok" if ok else drv.last_error])
	check(took < 12.0, "36 m along A take %.1f s (< 12, nobody stands nose to nose)" % took)
	await drv.brake()
	world.exit_car()
	await drv.frames(30)
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	await drv.frames(2)

# =====================================================================================
# 6. Илюша стоит на полосе перед троллейбусом
# =====================================================================================

func _part_player_block() -> void:
	print("--- Ilyusha on the lane ---")
	traffic.reset_positions()
	var bus: Trolleybus = traffic.trolleybus
	var point := Vector3(-29, 0, 29)   # до остановки A; весь остановившийся кузов западнее пешеходного перехода
	world.player.place(point, 0.0)
	await drv.frames(2)
	var at := lane.offset_of(point)
	var player_at: Vector3 = world.player.global_position
	var waited := 0
	var min_gap := INF
	while waited < 30 * 60 and bus.blocked_time < 3.5:
		await physics_frame
		waited += 1
		min_gap = minf(min_gap, fposmod(at - bus.s, lane.length) - bus.size.z * 0.5)
	check(bus.blocked_by == world.player, "trolleybus stopped for Ilyusha (blocked by %s)" % [bus.blocked_by.name if bus.blocked_by else "nothing"])
	check(bus.speed == 0.0 and bus.blocked_time >= 3.0, "trolleybus waits standing ≥ 3 s (%.1f s)" % bus.blocked_time)
	check(min_gap > 3.0 and min_gap <= PathVehicle.SENSOR_RANGE, "trolleybus front stopped %.2f m from Ilyusha's centre" % min_gap)
	check(_flat(world.player.global_position).distance_to(_flat(player_at)) < 0.05, "Ilyusha not pushed")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var resumed := await _wait_until(func(): return bus.speed > 1.0, 5 * 60)
	check(resumed >= 0, "trolleybus drives on after Ilyusha leaves (%d frames)" % resumed)

# =====================================================================================
# 6а. Илюша шагнул под бампер машины на 6 м/с: аварийное торможение ≤ 12 м/с², встаёт до касания (ARENA-01 fix P3)
# =====================================================================================

func _part_hard_brake() -> void:
	print("--- hard brake ---")
	traffic.reset_positions()
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var car: TrafficCar = traffic.cars[0]   # «Жигули»: старт на B у z = 1, на север
	var reached := await _wait_until(func(): return car.speed >= 6.0, 10 * 60)
	if not check(reached >= 0, "%s reaches 6 m/s (%d frames)" % [car.name, reached]):
		return
	# Центр Илюши — в 2,2 м перед бампером (край капсулы ~1,85 м): при 9 м/с² тормозной путь 2,0 м — касание,
	# при 12 м/с² — 1,5 м.
	var v0 := car.speed
	var gap0 := 2.2
	var at := car.s + car.size.z * 0.5 + gap0
	var point := car_lane.position_at(at)
	world.player.place(point, 0.0)
	var player_at: Vector3 = world.player.global_position
	var max_decel := 0.0
	var body_stop := false
	var min_gap := INF
	var frames := 0
	while frames < 3 * 60:
		await physics_frame
		frames += 1
		max_decel = maxf(max_decel, car.last_decel)
		body_stop = body_stop or car.limit_reason == &"body"
		min_gap = minf(min_gap, fposmod(car_lane.offset_of(world.player.global_position) - car.s, car_lane.length) - car.size.z * 0.5 - 0.35)
		if car.speed == 0.0 and frames > 30:
			break
	check(car.speed == 0.0, "%s stopped for Ilyusha stepping in %.1f m ahead at %.1f m/s" % [car.name, gap0, v0])
	check(max_decel <= PathVehicle.HARD_DECEL + 0.05 and max_decel > PathVehicle.EMERGENCY_DECEL, "emergency braking %.1f m/s² (9 < … ≤ 12), no instant stop" % max_decel)
	check(not body_stop, "the last-resort body check never fired (no 6 → 0 m/s in one frame)")
	check(min_gap > 0.0, "stopped before touching: bumper %.2f m short of Ilyusha's capsule" % min_gap)
	check(_flat(world.player.global_position).distance_to(_flat(player_at)) < 0.05, "Ilyusha not pushed")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var resumed := await _wait_until(func(): return car.speed > 1.0, 5 * 60)
	check(resumed >= 0, "%s drives on after Ilyusha leaves (%d frames)" % [car.name, resumed])

# =====================================================================================
# 7. Пауза и диалог
# =====================================================================================

func _part_pause_and_dialog() -> void:
	print("--- pause & dialog ---")
	traffic.reset_positions()
	await drv.frames(120)
	await drv.pause_key()
	await drv.frames(3)
	check(paused, "Esc pauses the game")
	var before: Array = traffic.vehicles.map(func(v): return v.global_position)
	await drv.frames(60)
	var still := true
	for i in traffic.vehicles.size():
		still = still and traffic.vehicles[i].global_position.is_equal_approx(before[i])
	check(still, "vehicles stand still on pause")
	await drv.pause_key()
	await drv.frames(3)
	check(not paused, "resume")
	world.player.place(Layout.BABKA + Vector3(0.6, 0.0, -2.0), 0.0)
	await drv.frames(3)
	await drv.interact()
	await drv.frames(5)
	if not check(world.quest_flow.is_dialog_open(), "dialog with Babka opens (mission %s)" % world.mission.state):
		return
	var dist: Array = traffic.vehicles.map(func(v): return v.distance_travelled)
	var lada_at: Vector3 = world.car.global_position
	var hits := {}
	for frame in 300:
		await physics_frame
		for v in traffic.vehicles:
			for solid in _overlaps(v.global_transform, v.size):
				hits[solid[0]] = true
	var moved := true
	for i in traffic.vehicles.size():
		moved = moved and traffic.vehicles[i].distance_travelled > dist[i] + 1.0
	check(world.quest_flow.is_dialog_open(), "dialog still open after 5 s")
	check(moved, "traffic keeps driving while the dialog is open")
	check(hits.is_empty(), "no vehicle inside a Layout solid during the dialog%s" % ("" if hits.is_empty() else " — %s" % [hits.keys()]))
	check(_flat(world.car.global_position).distance_to(_flat(lada_at)) < 0.05, "Lada untouched during the dialog")
	check(await drv.press_button("ПРИНЯТЬ"), "ПРИНЯТЬ closes the dialog (%s)" % drv.last_error)
	await drv.frames(5)
	check(not world.quest_flow.is_dialog_open() and world.mission.state == &"GO_TO_CAR", "dialog closed, mission GO_TO_CAR (%s)" % world.mission.state)

# =====================================================================================
# 8. POLISH-03 B: перекрытие улицы Б на возврате — транспорт встаёт у ограждения без касания и едет дальше, когда
#    перекрытие сняли (Илюша дома или вышел срок RoadClosure.MAX_SECONDS); пробка не вечная.
# =====================================================================================

func _part_closure() -> void:
	print("--- road closure ---")
	var m := world.mission
	var closure = world.get_node("LevelGeometry/Patrols/RoadClosure")
	traffic.reset_positions()
	world.player.place(Vector3(-20.0, 0.0, -88.0), 0.0)               # тротуар Выборной, вне YARD_HOME и полос
	if m.state == &"GO_TO_CAR":
		m.notify_entered_car()
	m.notify_arrived_kiosk()
	m.add_money(m.money_missing())
	check(m.buy_bread() and m.road_closed, "closure: bought bread — street B closed (mission %s)" % m.state)
	var waited: int = await _wait_until(func(): return closure.is_blocking(), 60 * 40)
	check(closure.is_blocking(), "closure: fence and gap stand within 40 s (%.1f s)" % (waited / 60.0))
	var queued := {}
	var touching := {}
	var own: Array = [closure.van, closure.get_node("Fence"), closure.get_node("GapSection")]
	for frame in 60 * 90:
		await physics_frame
		for v in traffic.vehicles:
			if own.has(v.blocked_by) and v.speed < 0.05:
				queued[v.name] = true
			var p: Vector3 = v.global_position
			if absf(p.z - Layout.CLOSURE_Z) < v.size.z * 0.5 + 0.1 and p.x > Layout.CLOSURE_X.x and p.x < Layout.CLOSURE_X.y:
				touching[v.name] = true
	check(not queued.is_empty(), "closure: ring transport waits at the closure (%s)" % [queued.keys()])
	check(touching.is_empty(), "closure: no vehicle body crosses the closure line while it stands %s" % [touching.keys()])
	var dist: Array = traffic.vehicles.map(func(v): return v.distance_travelled)
	# Илюша домой не спешит — перекрытие снимают по сроку, пробка рассасывается.
	await _wait_until(func(): return not m.road_closed, int(60 * (closure.MAX_SECONDS + 5.0)))
	check(not m.road_closed and not closure.active and closure.timeouts == 1, "closure: lifted after MAX_SECONDS %.0f s without going home (timeouts %d)" % [closure.MAX_SECONDS, closure.timeouts])
	check(not closure.get_node("Fence").visible and closure.get_node("Fence").collision_layer == 0 and not closure.van.visible, "closure: fence and van gone")
	await drv.frames(60 * 30)
	var moved := 0
	for i in traffic.vehicles.size():
		if traffic.vehicles[i].distance_travelled > dist[i] + 20.0:
			moved += 1
	check(moved == traffic.vehicles.size(), "closure: all %d vehicles drive on after the lift (%d moved > 20 m)" % [traffic.vehicles.size(), moved])

# =====================================================================================
# Геометрия и служебное
# =====================================================================================

## Ближайший транспорт позади точки at по пути on.
func _vehicle_behind(at: float, on: PathVehicle.LanePath) -> PathVehicle:
	var best: PathVehicle = null
	var best_d := INF
	for v in traffic.vehicles:
		if v.path != on:
			continue
		var d := fposmod(at - v.s, on.length)
		if d < best_d:
			best_d = d
			best = v
	return best

## Коробки Layout, в которые входит корпус size при xf (прямоугольники на земле; низкие тоже — валы, лавки).
func _overlaps(xf: Transform3D, size: Vector3) -> Array:
	var out := []
	var c := Vector2(xf.origin.x, xf.origin.z)
	var f := Vector2(-xf.basis.z.x, -xf.basis.z.z).normalized()
	var r := Vector2(-f.y, f.x)
	var hw := size.x * 0.5
	var hl := size.z * 0.5
	for solid in _solids:
		var center: Vector2 = solid[1]
		var box: Vector3 = solid[2]
		var h := Vector2(box.x * 0.5, box.z * 0.5)
		var separated := false
		for axis in [Vector2(1, 0), Vector2(0, 1), f, r]:
			var a: Vector2 = axis
			var rv := absf(f.dot(a)) * hl + absf(r.dot(a)) * hw
			var rb := absf(a.x) * h.x + absf(a.y) * h.y
			if absf((c - center).dot(a)) >= rv + rb - 0.01:
				separated = true
				break
		if not separated:
			out.append(solid)
	return out

## Углы корпуса в плане: центр, направление «вперёд», (ширина, длина).
func _obb_corners(c: Vector2, f: Vector2, wl: Vector2) -> Array[Vector2]:
	var r := Vector2(-f.y, f.x)
	var out: Array[Vector2] = []
	for k in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]:
		out.append(c + f * wl.y * 0.5 * k.x + r * wl.x * 0.5 * k.y)
	return out

func _footprint_corners(v: PathVehicle) -> Array[Vector2]:
	var fp: Array = v.footprint()
	return _obb_corners(fp[0], fp[1], fp[2])

## Расстояние от точки до выпуклого четырёхугольника (0 внутри).
func _point_obb_distance(p: Vector2, poly: Array[Vector2]) -> float:
	if Geometry2D.is_point_in_polygon(p, PackedVector2Array(poly)):
		return 0.0
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, q.distance_to(p))
	return best

## Расстояние между двумя выпуклыми четырёхугольниками (0 — касаются или пересекаются).
func _poly_distance(a: Array[Vector2], b: Array[Vector2]) -> float:
	if not Geometry2D.intersect_polygons(PackedVector2Array(a), PackedVector2Array(b)).is_empty():
		return 0.0
	var best := INF
	for p in a:
		best = minf(best, _point_obb_distance(p, b))
	for p in b:
		best = minf(best, _point_obb_distance(p, a))
	return best

func _obb_rect_distance(corners: Array[Vector2], center: Vector2, size: Vector2) -> float:
	var h := size * 0.5
	var rect: Array[Vector2] = [center + Vector2(-h.x, -h.y), center + Vector2(h.x, -h.y), center + h, center + Vector2(-h.x, h.y)]
	return _poly_distance(corners, rect)

func _aabb_distance(box: AABB, p: Vector3) -> float:
	var dx := maxf(maxf(box.position.x - p.x, 0.0), p.x - box.end.x)
	var dz := maxf(maxf(box.position.z - p.z, 0.0), p.z - box.end.z)
	return Vector2(dx, dz).length()

func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

func _wait_until(condition: Callable, max_frames: int) -> int:
	for i in max_frames:
		if condition.call():
			return i
		await physics_frame
	return -1

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		print("FAIL: ", label)
	return condition

func _finish(code := -1) -> void:
	print("TRAFFIC: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))
