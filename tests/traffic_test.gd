extends SceneTree
## ARENA-01 T: транспорт кольца по контракту C8 на настоящей сцене main.tscn (набор TRAFFIC).
## Если интегратор ещё не подключил узел Traffic к LevelGeometry, тест добавляет его сам.
## Проверки: путь — правая полоса RING со скруглением 6 м; старт — равномерно, ≥ 20 м от CAR_SPAWN, стоянки «Лады»
## у киоска (конец ROUTE_DRIVE) и окна, VAN_PARK; слои тел; путь каждого корпуса не входит в коробки Layout.all_solids(); за прогон все три машины
## проходят полный круг, троллейбус стоит ≈6 с на обеих остановках со звуком дверей, отклонение от оси на
## прямых ≤ RING_LANE + 0,5, дистанция между своими ≥ 10 м; машина тормозит перед стоящей на полосе «Ладой» и
## не сдвигает её, троллейбус — перед Илюшей; после ухода препятствия едут дальше; на паузе транспорт стоит,
## при открытом диалоге едет и мир не ломает.
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
var lane: PathVehicle.LanePath
var _solids: Array = []
var _sim_time := 0.0
var _door_events: Array = []   # [время, "open"/"close", индекс остановки, позиция]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: traffic test exceeded 900 simulated seconds")
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
	for spec in Layout.all_solids():
		_solids.append([spec[0], spec[2], spec[3]])
	traffic.trolleybus.doors_opened.connect(func(i): _door_events.append([_sim_time, "open", i, traffic.trolleybus.global_position]))
	traffic.trolleybus.doors_closed.connect(func(i): _door_events.append([_sim_time, "close", i, traffic.trolleybus.global_position]))
	physics_frame.connect(func(): _sim_time += 1.0 / Engine.physics_ticks_per_second)
	_part_path()
	_part_start()
	_part_sweep()
	await _part_laps()
	await _part_lada_block()
	await _part_player_block()
	await _part_pause_and_dialog()
	drv.release_all()
	_finish()

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
	var offsets: Array[float] = TrafficScript.start_offsets(lane.length)
	check(offsets == TrafficScript.start_offsets(lane.length), "start offsets are constants (same on a second call)")
	var step := lane.length / offsets.size()
	for i in offsets.size():
		var p := lane.position_at(offsets[i])
		var name: String = traffic.vehicles[i].name
		var d_car := _flat(p).distance_to(_flat(Layout.CAR_SPAWN))
		# Киоск — стоянка «Лады» (конец ROUTE_DRIVE) и окно: KIOSK_ZONE после EXT-01 захватывает край улицы B
		# у заезда на парковку, и полоса кольца идёт вдоль неё — мерить до коробки зоны стало бессмысленно.
		var d_kiosk := minf(_flat(p).distance_to(_flat(Layout.ROUTE_DRIVE[-1])), _flat(p).distance_to(_flat(Layout.VENDOR_WINDOW)))
		var d_van := _flat(p).distance_to(_flat(Layout.VAN_PARK))
		check(d_car >= 20.0 and d_kiosk >= 20.0 and d_van >= 20.0, "%s starts at (%.1f, %.1f): CAR_SPAWN %.1f, kiosk parking/window %.1f, VAN_PARK %.1f m (≥ 20)" % [name, p.x, p.z, d_car, d_kiosk, d_van])
		var gap := fposmod(offsets[(i + 1) % offsets.size()] - offsets[i], lane.length)
		check(absf(gap - step) < 0.01, "%s: next one %.1f m ahead (even spacing %.1f)" % [name, gap, step])
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
		while at < lane.length:
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
	for frame in max_frames:
		await physics_frame
		for v in traffic.vehicles:
			var front: float = v.s + v.wheelbase * 0.5
			var rear: float = v.s - v.wheelbase * 0.5
			var d := lane.axis_distance(v.global_position)
			if lane.in_arc(front) or lane.in_arc(rear) or lane.in_arc(v.s):
				worst_corner = maxf(worst_corner, d)
			else:
				worst_lane = maxf(worst_lane, absf(d - Layout.RING_LANE))
		for i in traffic.vehicles.size():
			var a: PathVehicle = traffic.vehicles[i]
			for b in traffic.vehicles:
				if b == a:
					continue
				var ahead := fposmod(b.s - a.s, lane.length)
				if ahead < lane.length * 0.5:
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
		check(car.distance_travelled >= lane.length, "%s made a full lap (%.0f of %.0f m)" % [car.name, car.distance_travelled, lane.length])
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
		if car.distance_travelled < lane.length:
			return false
	return true

# =====================================================================================
# 5. «Лада» стоит на полосе: машина тормозит, не трогает её, ждёт; «Лада» ушла — едет
# =====================================================================================

func _part_lada_block() -> void:
	print("--- Lada blocks the lane ---")
	traffic.reset_positions()
	var lada_point := Vector3(67, 0, 0)   # улица B, полоса на юг; «Газель» стартует севернее (z ≈ −35)
	var at := lane.offset_of(lada_point)
	var dir := lane.direction_at(at)
	var car: PathVehicle = _vehicle_behind(at)
	world.car.reset_to(lada_point, atan2(-dir.x, -dir.z))
	await drv.frames(2)
	var lada_at: Vector3 = world.car.global_position
	var waited := 0
	var min_gap := INF
	while waited < 30 * 60 and car.blocked_time < 3.5:
		await physics_frame
		waited += 1
		var gap := fposmod(at - car.s, lane.length) - car.size.z * 0.5 - Lada.SIZE.z * 0.5
		min_gap = minf(min_gap, gap)
	check(car.blocked_by == world.car, "%s stopped for the Lada (blocked by %s)" % [car.name, car.blocked_by.name if car.blocked_by else "nothing"])
	check(car.speed == 0.0 and car.blocked_time >= 3.0, "%s waits standing ≥ 3 s (%.1f s), no overtaking" % [car.name, car.blocked_time])
	check(min_gap > 2.5 and min_gap <= PathVehicle.SENSOR_RANGE, "%s stopped %.2f m short of the Lada (2.5…8)" % [car.name, min_gap])
	check(_flat(world.car.global_position).distance_to(_flat(lada_at)) < 0.05, "Lada not pushed (moved %.3f m)" % _flat(world.car.global_position).distance_to(_flat(lada_at)))
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	var resumed := await _wait_until(func(): return car.speed > 1.0, 5 * 60)
	check(resumed >= 0, "%s drives on after the Lada leaves (%d frames)" % [car.name, resumed])

# =====================================================================================
# 6. Илюша стоит на полосе перед троллейбусом
# =====================================================================================

func _part_player_block() -> void:
	print("--- Ilyusha on the lane ---")
	traffic.reset_positions()
	var bus: Trolleybus = traffic.trolleybus
	var point := Vector3(-14, 0, 29)   # улица A, перед стартом троллейбуса (x ≈ 6), до остановки x = −30
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
# Геометрия и служебное
# =====================================================================================

## Ближайший транспорт позади точки at по пути.
func _vehicle_behind(at: float) -> PathVehicle:
	var best: PathVehicle = null
	var best_d := INF
	for v in traffic.vehicles:
		var d := fposmod(at - v.s, lane.length)
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
