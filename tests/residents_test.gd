extends SceneTree
## PEOPLE-01, часть B: жители города Н. на настоящей сцене main.tscn (набор RESIDENTS).
## Если интегратор ещё не подключил узел Residents к LevelGeometry, тест добавляет его сам.
## Проверки: состав (6–8 жителей, 4 силуэта), скорость 1,2–1,6 м/с и паузы 2–5 с — константы по индексу;
## маршруты — только Walk_*, Yard_Drive и площадка у подъезда, ни одной точки на "road" (с радиусом тела), от коробок
## Layout.all_solids() ≥ 1 м, вне KIOSK_ZONE, ≥ 8 м от постов стелса, ≥ 2 м от ROUTE_WALK/ROUTE_DRIVE; слой тела
## (Car: Илюша и транспорт видят, луч сенсоров и камера — нет), не в detection_sensors; прогон — каждый проходит
## ≥ 95 % маршрута без застреваний, не выходя на проезжую часть и не входя в коробки; Илюша в 2 м — стоит ≥ 1 с,
## смотрит на него и идёт дальше; Илюша прямо по ходу — ждёт и не толкает, Илюша в жителя упирается; «Лада» на
## жителе — житель на ближайшей свободной точке маршрута; reset_positions() — все на стартах.
## CITY-01 (часть P): 12–16 жителей (14); пары — маршрут второго = маршрут первого + постоянный сдвиг (1,2 м по ходу),
## в прогоне дистанция постоянна; курящие стоят 40–60 с, поворачиваются, уходят и возвращаются; пассажир садится в
## троллейбус у A (исчезает в дверях, не позже закрытия), выходит на B у передней двери (вне KIOSK_ZONE/KIOSK_SQUARE,
## тело выключено у парковки), переходит улицу и исчезает в «ГАСТРОНОМЕ», на следующей стоянке у A выходит из двери;
## не больше одной посадки и одного выхода на остановку за стоянку; гудок — ближние в 20 м оглядываются на 2 с, дальние
## нет; «Лада» с водителем ближе 5 м — пузырь из QuestLines.RESIDENT_LINES на 2 с, не чаще раза в 20 с;
## реплики — не больше шести коротких, без запрещённых слов.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/residents_test.gd

const Layout = preload("res://game/world/layout.gd")
const ResidentsScript = preload("res://game/world/residents.gd")
const DetectionSensorScript = preload("res://game/stealth/detection_sensor.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")

const CLEARANCE := 1.0        # м от оси маршрута до коробки
const POST_CLEARANCE := 8.0   # м до постов стелса
const TEST_PATH_CLEARANCE := 2.0
const STALL_LIMIT := 0.5      # с без продвижения в состоянии walk
const TRANSIT_STATES: Array[StringName] = [&"board", &"alight", &"transit"]   # пассажир у дверей и на переходе — не по маршруту
const FORBIDDEN := ["мобилизац", "бусификац"]

var failures: Array[String] = []
var checks := 0
var main: Node
var drv
var world: DemoWorld
var residents_node: Node3D
var residents: Array = []
var _solids: Array = []
var _roads: Array = []
var _walkable: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(1500.0, true, false, true).timeout.connect(func():
		push_error("FAIL: residents test exceeded 1500 simulated seconds")
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
	residents_node = world.get_node_or_null("LevelGeometry/Residents")
	if residents_node == null:
		residents_node = ResidentsScript.new()
		world.get_node("LevelGeometry").add_child(residents_node)
		print("INFO: Residents attached by the test (LevelGeometry has no Residents yet)")
	else:
		print("INFO: Residents attached by LevelGeometry")
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false   # Илюшу ставим где угодно — наблюдатели не мешают
	await drv.frames(3)
	residents = residents_node.residents
	for spec in Layout.all_solids():
		_solids.append([spec[0], spec[2], spec[3]])
	for surface in Layout.SURFACES:
		var rect := Rect2(surface[2] - surface[3] * 0.5, surface[3])
		if surface[1] == "road":
			_roads.append([surface[0], rect])
		elif surface[1] == "sidewalk" or surface[1] == "yard_road":
			_walkable.append([surface[0], rect])
	_walkable.append(["ENTRANCE_AREA", Layout.RESIDENT_ENTRANCE_AREA])
	_part_roster()
	_part_routes()
	_part_layers()
	await _part_walk()
	await _part_notice()
	await _part_block()
	await _part_lada()
	await _part_reset()
	_part_lines()
	await _part_city()
	await _part_horn()
	await _part_bubble()
	_finish()

# =====================================================================================
# 1. Состав и константы
# =====================================================================================

func _part_roster() -> void:
	print("--- roster ---")
	check(residents.size() >= 12 and residents.size() <= 16, "12–16 residents (%d)" % residents.size())
	var looks := {}
	for look in Layout.RESIDENT_LOOKS:
		looks[look] = true
	# PEOPLE-02: персонажи ШКЯ — шесть силуэтов (пацан в двух палитрах), все с рисунками resident_<look>.
	var expected := [&"shuba", &"beret", &"violet", &"ushanka", &"tourist", &"kid", &"kid2"]
	var all_known := true
	for look in looks:
		all_known = all_known and expected.has(look)
	check(looks.size() >= 6 and all_known, "ШКЯ silhouettes only (%s)" % [looks.keys()])
	for look in looks:
		check(ResidentsScript.character_for(look).begins_with("resident_"), "look %s has resident art" % look)
	check(Layout.RESIDENT_ROUTES.size() == residents.size() and Layout.RESIDENT_PAUSES.size() == residents.size() and Layout.RESIDENT_STARTS.size() == residents.size() and Layout.RESIDENT_LOOKS.size() == residents.size(), "one route, pause list, start and look per resident")
	for r in residents:
		check(r.speed >= 1.2 and r.speed <= 1.6 and r.speed == Resident.SPEEDS[r.index], "%s: speed %.2f m/s (1.2–1.6, constant by index)" % [r.name, r.speed])
		check(r.pause_seconds >= 2.0 and r.pause_seconds <= 5.0 and r.pause_seconds == Resident.PAUSES[r.index], "%s: pause %.1f s (2–5, constant by index)" % [r.name, r.pause_seconds])
		if r.leader != null:
			check(r.speed == r.leader.speed, "%s: same pace as its pair leader %s" % [r.name, r.leader.name])
		check(not r.pause_points.is_empty(), "%s: route has pause points %s" % [r.name, r.pause_points])
		var look: StringName = Layout.RESIDENT_LOOKS[r.index]
		check(r.character == ResidentsScript.character_for(look), "%s: look %s → character %s" % [r.name, look, r.character])

# =====================================================================================
# 2. Маршруты: тротуары, не дорога, запас от коробок, постов и тестовых путей
# =====================================================================================

func _part_routes() -> void:
	print("--- routes ---")
	var posts := {"OFFICER_POST": Layout.OFFICER_POST, "OFFICER_POST_AFTER": Layout.OFFICER_POST_AFTER,
		"ACCOUNT_OFFICER": Layout.ACCOUNT_OFFICER, "STEALTH_CHECKPOINT": Layout.STEALTH_CHECKPOINT}
	var kiosk := Rect2(Layout.KIOSK_ZONE.position.x, Layout.KIOSK_ZONE.position.z, Layout.KIOSK_ZONE.size.x, Layout.KIOSK_ZONE.size.z)
	for i in Layout.RESIDENT_ROUTES.size():
		var route: Array = Layout.RESIDENT_ROUTES[i]
		var label := "route %d (%s)" % [i, Layout.RESIDENT_LOOKS[i]]
		var off_walk := []
		var on_road := {}
		var min_solid := INF
		var min_solid_name := ""
		var min_post := INF
		var min_test_path := INF
		var in_kiosk := false
		for p in _samples(route, 0.25):
			var q := Vector2(p.x, p.z)
			if not _walkable.any(func(w): return w[1].has_point(q)):
				off_walk.append("(%.1f, %.1f)" % [q.x, q.y])
			for road in _roads:
				if _rect_distance(road[1], q) < Resident.BODY_RADIUS:
					on_road[road[0]] = true
			for solid in _solids:
				var d := _rect_distance(Rect2(solid[1] - Vector2(solid[2].x, solid[2].z) * 0.5, Vector2(solid[2].x, solid[2].z)), q)
				if d < min_solid:
					min_solid = d
					min_solid_name = "%s@(%.1f,%.1f)" % [solid[0], solid[1].x, solid[1].y]
			for key in posts:
				min_post = minf(min_post, q.distance_to(Vector2(posts[key].x, posts[key].z)))
			min_test_path = minf(min_test_path, minf(_polyline_distance(Layout.ROUTE_WALK, q), _polyline_distance(Layout.ROUTE_DRIVE, q)))
			if _rect_distance(kiosk, q) < 1.0:
				in_kiosk = true
		check(off_walk.is_empty(), "%s: every point on Walk_*/Yard_Drive/entrance area%s" % [label, "" if off_walk.is_empty() else " — off at " + ", ".join(off_walk.slice(0, 4))])
		check(on_road.is_empty(), "%s: body never on a road surface%s" % [label, "" if on_road.is_empty() else " — %s" % [on_road.keys()]])
		check(min_solid >= CLEARANCE, "%s: ≥ %.1f m from every solid (nearest %s, %.2f m)" % [label, CLEARANCE, min_solid_name, min_solid])
		check(not in_kiosk, "%s: outside KIOSK_ZONE (+1 m)" % label)
		check(min_post >= POST_CLEARANCE, "%s: ≥ 8 m from stealth posts and checkpoint (%.1f m)" % [label, min_post])
		check(min_test_path >= TEST_PATH_CLEARANCE, "%s: ≥ 2 m from ROUTE_WALK / ROUTE_DRIVE (%.1f m)" % [label, min_test_path])
		if ResidentsScript.PAIRS.has(i):
			var lead: Array = Layout.RESIDENT_ROUTES[ResidentsScript.PAIRS[i]]
			var offset := _flat(route[0]) - _flat(lead[0])
			var same: bool = route.size() == lead.size() and Layout.RESIDENT_PAUSES[i] == Layout.RESIDENT_PAUSES[ResidentsScript.PAIRS[i]] \
				and Layout.RESIDENT_STARTS[i] == Layout.RESIDENT_STARTS[ResidentsScript.PAIRS[i]]
			for k in mini(route.size(), lead.size()):
				same = same and (_flat(route[k]) - _flat(lead[k])).distance_to(offset) < 0.001
			var first_leg := _flat(lead[(Layout.RESIDENT_STARTS[i] + 1) % lead.size()]) - _flat(lead[Layout.RESIDENT_STARTS[i]])
			var behind := -offset.dot(first_leg.normalized())
			check(same, "%s: leader's route shifted by a constant (%.2f, %.2f), same pauses and start" % [label, offset.x, offset.y])
			check(absf(behind - ResidentsScript.FOLLOW_GAP) < 0.05, "%s: %.2f m behind the leader at the start (1.2)" % [label, behind])
		var start: Vector3 = route[Layout.RESIDENT_STARTS[i]]
		var d_start := minf(minf(_flat(start).distance_to(_flat(Layout.SPAWN)), _flat(start).distance_to(_flat(Layout.BABKA))), _flat(start).distance_to(_flat(Layout.CAR_SPAWN)))
		check(d_start >= 5.0, "%s: start ≥ 5 m from SPAWN, BABKA, CAR_SPAWN (%.1f m)" % [label, d_start])

# =====================================================================================
# 3. Слой тела: Илюша и транспорт видят, луч сенсоров и камера — нет; не в detection_sensors
# =====================================================================================

func _part_layers() -> void:
	print("--- layers ---")
	var player: Ilyusha = world.player
	var arm: SpringArm3D = _find_spring_arm(world.camera_rig)
	for r in residents:
		var body: CollisionObject3D = r.body
		var ok := body is AnimatableBody3D and body.collision_layer == Resident.BODY_LAYER and body.collision_mask == 0
		check(ok, "%s: AnimatableBody3D, layer %d, mask 0" % [r.name, body.collision_layer])
		check(body.collision_layer & DetectionSensorScript.WORLD_MASK == 0, "%s: not on the sensors' ray layer (WORLD_MASK %d)" % [r.name, DetectionSensorScript.WORLD_MASK])
		check(body.collision_layer & PathVehicle.SENSOR_MASK != 0, "%s: seen by the traffic sensor (mask %d)" % [r.name, PathVehicle.SENSOR_MASK])
		check(body.collision_layer & player.collision_mask != 0, "%s: solid for Ilyusha (his mask %d)" % [r.name, player.collision_mask])
		if arm:
			check(body.collision_layer & arm.collision_mask == 0, "%s: camera spring arm ignores it (arm mask %d)" % [r.name, arm.collision_mask])
		check(not r.is_in_group(&"detection_sensors") and r.find_children("*", "DetectionSensor", true, false).is_empty(), "%s: no DetectionSensor, not in detection_sensors" % r.name)
		check(not r.interactable.enabled and r.interactable.prompt == "", "%s: no E zone" % r.name)
	# Луч по слою World сквозь жителя — пусто; по слою Car — попадает в тело.
	var r1: Resident = residents[1]
	var from: Vector3 = r1.global_position + Vector3(-3, 1.2, 0)
	var to: Vector3 = r1.global_position + Vector3(3, 1.2, 0)
	var space := world.get_world_3d().direct_space_state
	var hit_world := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, DetectionSensorScript.WORLD_MASK))
	var hit_car := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Resident.BODY_LAYER))
	check(hit_world.is_empty() or hit_world.get("collider") != r1.body, "sensor ray (World) passes through %s" % r1.name)
	check(hit_car.get("collider") == r1.body, "ray on the Car layer hits %s's body" % r1.name)

func _find_spring_arm(node: Node) -> SpringArm3D:
	if node == null:
		return null
	for child in node.find_children("*", "SpringArm3D", true, false):
		return child
	return null

# =====================================================================================
# 4. Прогон: каждый проходит ≥ 95 % маршрута без застреваний, не на дороге, не в коробках
# =====================================================================================

func _part_walk() -> void:
	print("--- walk the loops ---")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	residents_node.reset_positions()
	var lada_at: Vector3 = world.car.global_position
	var player_at: Vector3 = world.player.global_position
	var limit := 0.0
	for r in residents:
		var smoke := Resident.SMOKE_SECONDS.y if r.smoke_point >= 0 else 0.0
		limit = maxf(limit, (r.loop_length() / r.speed + r.pause_points.size() * r.pause_seconds + smoke) * 1.3 + 10.0)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var stall := {}
	var worst_stall := {}
	var last := {}
	var road_hits := {}
	var solid_hits := {}
	for r in residents:
		stall[r] = 0.0
		worst_stall[r] = 0.0
		last[r] = 0.0
	var frames := int(limit / dt)
	var done_at := -1.0
	for frame in frames:
		await physics_frame
		var all_done := true
		for r in residents:
			if r.state == &"walk":
				stall[r] = stall[r] + dt if r.distance_walked <= last[r] + 0.0001 else 0.0
				worst_stall[r] = maxf(worst_stall[r], stall[r])
			else:
				stall[r] = 0.0
			last[r] = r.distance_walked
			if not r.rider:
				all_done = all_done and r.distance_walked >= 0.95 * r.loop_length()
			if frame % 6 == 0 and not r.hidden and not r.state in TRANSIT_STATES:
				var q := Vector2(r.global_position.x, r.global_position.z)
				for road in _roads:
					if _rect_distance(road[1], q) < Resident.BODY_RADIUS:
						road_hits[r.name] = "%s on %s at (%.1f, %.1f)" % [r.name, road[0], q.x, q.y]
				for solid in _solids:
					if _rect_distance(Rect2(solid[1] - Vector2(solid[2].x, solid[2].z) * 0.5, Vector2(solid[2].x, solid[2].z)), q) < Resident.BODY_RADIUS:
						solid_hits[r.name] = "%s in %s at (%.1f, %.1f)" % [r.name, solid[0], q.x, q.y]
		if all_done:
			done_at = frame * dt
			break
	for r in residents:
		if r.rider:
			continue   # пассажир ждёт троллейбус, а не ходит по кругу — _part_city
		var share: float = r.distance_walked / r.loop_length()
		check(share >= 0.95, "%s walked %.0f of %.0f m (%.0f %%, ≥ 95 %%)" % [r.name, r.distance_walked, r.loop_length(), share * 100.0])
		check(worst_stall[r] <= STALL_LIMIT, "%s: never stuck while walking (longest stall %.2f s)" % [r.name, worst_stall[r]])
		check(r.stare_count == 0 and r.lada_bumps == 0 and r.turnarounds == 0, "%s: undisturbed lap (stares %d, Lada bumps %d, turnarounds %d)" % [r.name, r.stare_count, r.lada_bumps, r.turnarounds])
	check(done_at > 0.0, "all residents covered 95 %% of their loops in %.0f s (limit %.0f s)" % [done_at if done_at > 0.0 else frames * dt, limit])
	check(road_hits.is_empty(), "nobody on a road surface during the run%s" % ("" if road_hits.is_empty() else " — " + ", ".join(road_hits.values())))
	check(solid_hits.is_empty(), "nobody inside a Layout solid during the run%s" % ("" if solid_hits.is_empty() else " — " + ", ".join(solid_hits.values())))
	check(_flat(world.car.global_position).distance_to(_flat(lada_at)) < 0.05, "parked Lada untouched")
	check(_flat(world.player.global_position).distance_to(_flat(player_at)) < 0.05, "Ilyusha untouched")

# =====================================================================================
# 5. Илюша в 2 м сбоку: стоит ≥ 1 с, смотрит на него, потом идёт дальше
# =====================================================================================

func _part_notice() -> void:
	print("--- Ilyusha 2 m to the side ---")
	residents_node.reset_positions()
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var r: Resident = residents[3]   # улица A, северный тротуар: сбоку к югу — снег, без коробок
	await drv.frames(180)
	check(r.state == &"walk", "%s walking before the approach (%s)" % [r.name, r.state])
	var spot: Vector3 = r.global_position + Vector3(0, 0, -2.0)
	world.player.place(spot, 0.0)
	var player_at: Vector3 = world.player.global_position
	var at: Vector3 = r.global_position
	var still := 0
	var moved_at := -1
	var looked := false
	for frame in 8 * 60:
		await physics_frame
		if moved_at < 0 and _flat(r.global_position).distance_to(_flat(at)) < 0.0001:
			still = frame + 1
		elif moved_at < 0:
			moved_at = frame
		if frame == 60:
			var to := world.player.global_position - r.global_position
			var wanted := atan2(-to.x, -to.z)
			looked = absf(angle_difference(r.visual.rotation.y, wanted)) < 0.2 and r.state == &"stare"
	var stood := still / 60.0
	check(r.stare_count == 1, "%s noticed Ilyusha once (%d)" % [r.name, r.stare_count])
	check(stood >= 1.0, "%s stood %.2f s (≥ 1 s)" % [r.name, stood])
	check(looked, "%s turned to look at Ilyusha after 1 s" % r.name)
	check(moved_at > 0 and r.state != &"stare", "%s walked on after %.1f s with Ilyusha still there (%s)" % [r.name, moved_at / 60.0, r.state])
	check(_flat(world.player.global_position).distance_to(_flat(player_at)) < 0.05, "Ilyusha not moved")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)

# =====================================================================================
# 6. Илюша прямо по ходу в 1 м: житель ждёт, не толкает; Илюша в жителя упирается
# =====================================================================================

func _part_block() -> void:
	print("--- Ilyusha in the way ---")
	residents_node.reset_positions()
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var r: Resident = residents[7]   # улица C, южный тротуар
	await drv.frames(120)
	var goal: Vector3 = Layout.RESIDENT_ROUTES[7][r.target_point]
	var here := Vector3(r.global_position.x, 0.0, r.global_position.z)
	var dir := (Vector3(goal.x, 0.0, goal.z) - here).normalized()
	world.player.place(here + dir * 1.0, 0.0)
	await drv.frames(2)
	var player_at: Vector3 = world.player.global_position
	var walked: float = r.distance_walked
	var closest := INF
	for frame in 6 * 60:
		await physics_frame
		closest = minf(closest, _flat(r.global_position).distance_to(_flat(world.player.global_position)))
	check(r.distance_walked - walked < 0.01, "%s waits while Ilyusha blocks the way (walked %.2f m in 6 s)" % [r.name, r.distance_walked - walked])
	check(closest >= 2.0 * Resident.BODY_RADIUS - 0.01, "%s never walks into Ilyusha (closest %.2f m)" % [r.name, closest])
	check(_flat(world.player.global_position).distance_to(_flat(player_at)) < 0.05, "Ilyusha not pushed (%.3f m)" % _flat(world.player.global_position).distance_to(_flat(player_at)))
	var motion := Vector3(r.global_position.x - world.player.global_position.x, 0.0, r.global_position.z - world.player.global_position.z)
	var hit: KinematicCollision3D = world.player.move_and_collide(motion, true)
	check(hit != null and hit.get_collider() == r.body, "Ilyusha bumps into %s's body (%s)" % [r.name, hit.get_collider().name if hit else "nothing"])
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var resumed := await _wait_until(func(): return r.distance_walked > walked + 0.5, 5 * 60)
	check(resumed >= 0, "%s walks on after Ilyusha leaves (%d frames)" % [r.name, resumed])

# =====================================================================================
# 7. «Лада» на жителе: на ближайшую свободную точку маршрута, «Лада» не сдвинута
# =====================================================================================

func _part_lada() -> void:
	print("--- Lada touches a resident ---")
	residents_node.reset_positions()
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var r: Resident = residents[6]   # улица D, восточный тротуар
	await drv.frames(60)
	var at: Vector3 = r.global_position
	world.car.reset_to(Vector3(at.x, 0.0, at.z), 0.0)
	await drv.frames(2)
	var lada_at: Vector3 = world.car.global_position
	check(r.lada_bumps == 1, "%s stepped aside once (%d)" % [r.name, r.lada_bumps])
	check(not r._lada_touches(r.global_position, 0.0), "%s clear of the Lada" % r.name)
	var off := _polyline_distance(Layout.RESIDENT_ROUTES[6], Vector2(r.global_position.x, r.global_position.z), true)
	check(off < 0.01, "%s stands on its route (%.3f m off)" % [r.name, off])
	var jump := _flat(r.global_position).distance_to(_flat(at))
	check(jump <= Lada.SIZE.z * 0.5 + Resident.BODY_RADIUS + Resident.LADA_CLEAR + 0.6, "%s moved to the nearest free point (%.2f m)" % [r.name, jump])
	# Дальше житель доходит до конца маршрута и идёт обратно — к стоящей «Ладе»: разворот, без касания.
	var bumps: int = r.lada_bumps
	var turned := await _wait_until(func(): return r.turnarounds > 0, 80 * 60)
	check(turned >= 0, "%s turned back before the parked Lada (%.0f s)" % [r.name, turned / 60.0])
	check(r.lada_bumps == bumps and not r._lada_touches(r.global_position, 0.0), "%s did not walk into the parked Lada (bumps %d → %d)" % [r.name, bumps, r.lada_bumps])
	var clear := INF
	for frame in 5 * 60:
		await physics_frame
		clear = minf(clear, _flat(r.global_position).distance_to(_flat(world.car.global_position)))
	check(r.lada_bumps == bumps and r.state != &"stare", "%s walks away from the Lada (closest %.2f m from its centre)" % [r.name, clear])
	check(_flat(world.car.global_position).distance_to(_flat(lada_at)) < 0.05, "Lada not moved by the resident")
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	await drv.frames(2)

# =====================================================================================
# 8. reset_positions(): все на стартах
# =====================================================================================

func _part_reset() -> void:
	print("--- reset ---")
	await drv.frames(120)
	residents_node.reset_positions()
	var worst := 0.0
	var states_ok := true
	for r in residents:
		var start: Vector3 = Layout.RESIDENT_ROUTES[r.index][Layout.RESIDENT_STARTS[r.index]]
		worst = maxf(worst, _flat(r.global_position).distance_to(_flat(start)))
		var start_state := &"smoke" if r.smoke_point == r.start_point else &"walk"
		states_ok = states_ok and r.state == start_state and r.direction == 1 and r.distance_walked == 0.0 and not r.hidden and r.visible
	check(worst < 0.001, "reset_positions(): everyone on their start (worst %.4f m)" % worst)
	check(states_ok, "reset_positions(): walking forward (smokers smoking), visible, counters cleared")

# =====================================================================================
# 9. Реплики: не больше шести коротких, без запрещённых слов
# =====================================================================================

func _part_lines() -> void:
	print("--- lines ---")
	var lines: Array = QuestLines.RESIDENT_LINES
	check(lines.size() >= 1 and lines.size() <= 6, "RESIDENT_LINES: 1–6 lines (%d)" % lines.size())
	for text in lines:
		var low := String(text).to_lower()
		check(String(text).length() <= 20, "short line '%s' (%d chars ≤ 20)" % [text, String(text).length()])
		check(FORBIDDEN.all(func(w): return not low.contains(w)), "forbidden words absent in '%s'" % text)

# =====================================================================================
# 10. Город 200 с: пары держат дистанцию, курящие уходят и возвращаются, пассажир ездит троллейбусом
# =====================================================================================

func _part_city() -> void:
	print("--- city run: pairs, smokers, trolleybus ---")
	var traffic: Node = world.get_node_or_null("LevelGeometry/Traffic")
	if not check(traffic != null and residents_node.trolley == traffic.trolleybus, "residents listen to trolleybus 13"):
		return
	var bus: Trolleybus = traffic.trolleybus
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	traffic.reset_positions()
	residents_node.reset_positions()
	await drv.frames(1)
	var rider: Resident = residents[ResidentsScript.RIDER]
	var clock := [0.0]   # в массиве: лямбды захватывают локальные переменные по значению
	var dt := 1.0 / Engine.physics_ticks_per_second
	var dwells: Array = []   # [остановка, открыты, закрыты]
	var on_open := func(stop: int): dwells.append([stop, clock[0], -1.0])
	var on_close := func(stop: int):
		if not dwells.is_empty() and dwells[-1][0] == stop:
			dwells[-1][2] = clock[0]
	bus.doors_opened.connect(on_open)
	bus.doors_closed.connect(on_close)
	# пары
	var pair_dev := {}
	for f in ResidentsScript.PAIRS:
		pair_dev[f] = 0.0
	# курящие: [время ухода с перекура, вернулся и снова курит, поворотов за перекур, время начала перекура]
	var smoke := {}
	for i in ResidentsScript.SMOKERS:
		var r: Resident = residents[i]
		smoke[i] = {"start": 0.0 if r.state == &"smoke" else -1.0, "left": -1.0, "back": -1.0, "turns": 0, "yaw": r.facing_yaw, "spells": []}
	# пассажир
	var alight_b_at := Vector3.INF
	var alight_b_door := Vector3.INF
	var in_zone_with_body := false
	var on_road_with_body_outside_crossing := false
	var shop_at := -1.0
	var shop_pos := Vector3.INF
	var board_hidden_in_dwell := false
	var alight_a_at := Vector3.INF
	var alight_a_door := Vector3.INF
	var events_seen := 0
	var kiosk_square := Layout.KIOSK_SQUARE
	var zone := Rect2(Layout.KIOSK_ZONE.position.x, Layout.KIOSK_ZONE.position.z, Layout.KIOSK_ZONE.size.x, Layout.KIOSK_ZONE.size.z)
	var in_square := false
	var near_post := INF
	var crossed_cars_stopped := 0
	for frame in int(320.0 / dt):
		await physics_frame
		clock[0] += dt
		var t: float = clock[0]
		for f in ResidentsScript.PAIRS:
			var second: Resident = residents[f]
			var first: Resident = residents[ResidentsScript.PAIRS[f]]
			var d := _flat(second.global_position).distance_to(_flat(first.global_position))
			pair_dev[f] = maxf(pair_dev[f], absf(d - Vector2(second.follow_offset.x, second.follow_offset.z).length()))
		for i in smoke:
			var r: Resident = residents[i]
			var rec: Dictionary = smoke[i]
			if r.state == &"smoke":
				if rec["start"] < 0.0:
					rec["start"] = t
				if absf(angle_difference(r.facing_yaw, rec["yaw"])) > 0.3:
					rec["turns"] += 1
				rec["yaw"] = r.facing_yaw
				if rec["left"] >= 0.0 and rec["back"] < 0.0 and _flat(r.global_position).distance_to(_flat(r.route[0])) < 0.01:
					rec["back"] = t
			elif rec["start"] >= 0.0 and rec["left"] < 0.0 and r.state == &"walk":
				rec["left"] = t
				rec["spells"].append(t - rec["start"])
		# пассажир
		while events_seen < rider.events.size():
			var e: Array = rider.events[events_seen]
			events_seen += 1
			if e[1] == &"alight" and e[2] == 1:
				alight_b_at = rider.global_position
				alight_b_door = Resident.door_point(bus, 0)
			elif e[1] == &"alight" and e[2] == 0:
				alight_a_at = rider.global_position
				alight_a_door = Resident.door_point(bus, 2)
			elif e[1] == &"board" and not dwells.is_empty() and dwells[-1][2] < 0.0 and rider.hidden:
				board_hidden_in_dwell = true
		if not rider.hidden:
			var q := _flat(rider.global_position)
			if rider.body.collision_layer != 0 and _rect_distance(zone, q) < Resident.BODY_RADIUS:
				in_zone_with_body = true
			if kiosk_square.has_point(q):
				in_square = true
			for post in [Layout.OFFICER_POST, Layout.OFFICER_POST_AFTER, Layout.OFFICER2_POST, Layout.STEALTH_CHECKPOINT]:
				near_post = minf(near_post, q.distance_to(_flat(post)))
		if rider.state == &"shop" and shop_at < 0.0:
			shop_at = t
			shop_pos = rider.global_position
		if alight_a_at != Vector3.INF and rider.state == &"wait_trolley":
			break
	bus.doors_opened.disconnect(on_open)
	bus.doors_closed.disconnect(on_close)
	print("INFO: city run %.0f s, dwells %s" % [clock[0], dwells.map(func(d): return "[%d %.1f–%.1f]" % [d[0], d[1], d[2]])])
	print("INFO: rider events %s" % [rider.events.map(func(e): return "%s@%d %.1f" % [e[1], e[2], e[0]])])
	for f in ResidentsScript.PAIRS:
		check(pair_dev[f] < 0.01, "%s keeps %.2f m from %s all the run (max deviation %.3f m)" % [residents[f].name, Vector2(residents[f].follow_offset.x, residents[f].follow_offset.z).length(), residents[ResidentsScript.PAIRS[f]].name, pair_dev[f]])
		var off := _polyline_distance(residents[f].route, _flat(residents[f].global_position), true)
		check(off < 0.01, "%s stays on its (shifted) route (%.3f m off)" % [residents[f].name, off])
	for i in smoke:
		var rec: Dictionary = smoke[i]
		var spell: float = rec["spells"][0] if not rec["spells"].is_empty() else -1.0
		check(spell >= Resident.SMOKE_SECONDS.x - 0.05 and spell <= Resident.SMOKE_SECONDS.y + 0.05, "%s smoked %.1f s at the entrance and left (40–60)" % [residents[i].name, spell])
		check(rec["turns"] >= 3, "%s turned %d times while smoking (≥ 3)" % [residents[i].name, rec["turns"]])
		check(rec["back"] - rec["left"] >= 10.0, "%s came back to the smoking spot (%.0f s after leaving at %.0f s)" % [residents[i].name, rec["back"] - rec["left"], rec["left"]])
	var per_dwell := {}
	for e in rider.events:
		var key := "%d@%d" % [e[2], _dwell_of(dwells, e[0], e[2])]
		per_dwell[key + String(e[1])] = per_dwell.get(key + String(e[1]), 0) + 1
	check(per_dwell.values().all(func(n): return n <= 1), "at most one boarding and one alighting per stop per dwell (%s)" % [per_dwell])
	var boarded := rider.events.filter(func(e): return e[1] == &"board" and e[2] == 0)
	check(not boarded.is_empty() and board_hidden_in_dwell, "rider waiting at stop A boarded and vanished while the doors were open (%d boardings)" % boarded.size())
	check(alight_b_at != Vector3.INF and _flat(alight_b_at).distance_to(_flat(alight_b_door)) < 0.05, "a 'new' passenger stepped out of the front door at stop B (%.2f m from the door)" % (_flat(alight_b_at).distance_to(_flat(alight_b_door)) if alight_b_at != Vector3.INF else INF))
	check(not in_zone_with_body, "passenger never inside KIOSK_ZONE with a live body")
	check(not in_square, "passenger never on KIOSK_SQUARE")
	check(near_post >= 8.0, "passenger ≥ 8 m from stealth posts and checkpoint (%.1f m)" % near_post)
	var shop: Vector3 = Layout.RESIDENT_RIDER_B_PATH[-1]
	check(shop_at > 0.0 and _flat(shop_pos).distance_to(_flat(shop)) < 0.05, "passenger crossed street B and went into the ГАСТРОНОМ (%.0f s)" % shop_at)
	check(alight_a_at != Vector3.INF and _flat(alight_a_at).distance_to(_flat(alight_a_door)) < 0.05, "next time at stop A the passenger stepped out of the rear door")
	check(rider.state == &"wait_trolley" and _flat(rider.global_position).distance_to(_flat(rider.route[ResidentsScript.RIDER_WAIT_POINT])) < 0.01, "…and walked back to wait at the pavilion (%s)" % rider.state)

func _dwell_of(dwells: Array, at: float, stop: int) -> int:
	for k in range(dwells.size() - 1, -1, -1):
		if dwells[k][0] == stop and dwells[k][1] <= at + 0.001:
			return k
	return -1

# =====================================================================================
# 11. Гудок: ближние в 20 м оглядываются на 2 с, дальние — нет
# =====================================================================================

func _part_horn() -> void:
	print("--- horn ---")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	residents_node.reset_positions()
	await drv.frames(30)
	var r: Resident = residents[3]   # улица A, северный тротуар
	var horn := Node3D.new()
	horn.name = "TestHorn"
	world.add_child(horn)
	horn.global_position = r.global_position + Vector3(0, 0, 9.0)   # на улице A
	var near := []
	var far := []
	for x in residents:
		if x.hidden:
			continue
		var d := _flat(x.global_position).distance_to(_flat(horn.global_position))
		if d <= Resident.HORN_RADIUS - 0.5 and x.state in [&"walk", &"pause", &"smoke", &"wait_trolley"]:
			near.append(x)
		elif d > Resident.HORN_RADIUS + 0.5:
			far.append(x)
	var before := {}
	for x in residents:
		before[x] = [x.state, x.glance_count]
	var sound: Node = world.get_node("SoundDirector")
	sound.horn_sounded.emit(horn)
	await drv.frames(30)
	for x in near:
		var lead: Resident = x.leader if x.leader else x
		var to: Vector3 = horn.global_position - x.global_position
		var looking := absf(angle_difference(x.visual.rotation.y, atan2(-to.x, -to.z))) < 0.35
		check(lead.state == &"glance" and lead._look_target == horn and looking, "%s (%.1f m) turns to the horn" % [x.name, _flat(x.global_position).distance_to(_flat(horn.global_position))])
	check(not near.is_empty(), "someone within 20 m of the horn (%d)" % near.size())
	check(far.all(func(x): return x.glance_count == before[x][1]), "nobody farther than 20 m turned (%d checked)" % far.size())
	await drv.frames(int((Resident.GLANCE_SECONDS - 0.5) * 60) + 10)
	check(near.all(func(x): return (x.leader if x.leader else x).state != &"glance"), "after %.0f s they go on (%s)" % [Resident.GLANCE_SECONDS, near.map(func(x): return String(x.state))])
	horn.queue_free()

# =====================================================================================
# 12. «Лада» с водителем ближе 5 м: пузырь-реплика 2 с, не чаще раза в 20 с
# =====================================================================================

func _part_bubble() -> void:
	print("--- Lada bubble ---")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	residents_node.reset_positions()
	await drv.frames(10)
	var r: Resident = residents[1]   # двор, восточный проезд x = −1: западнее — открытый двор
	# Без водителя — молчат.
	for frame in 60:
		world.car.reset_to(Vector3(r.global_position.x - 4.2, 0.0, r.global_position.z), 0.0)
		await physics_frame
	check(r.bubble_times.is_empty(), "no bubble from a Lada without a driver 4.2 m away")
	world.enter_car()
	var shown := []
	var was := false
	var looked := false
	var t := 0.0
	for frame in 25 * 60:
		world.car.reset_to(Vector3(r.global_position.x - 4.2, 0.0, r.global_position.z), 0.0)   # едет рядом в 4,2 м
		await physics_frame
		t += 1.0 / 60.0
		var on := r.bubble_visible()
		if on and not was:
			shown.append([t, -1.0, r.bubble_text])
		elif was and not on:
			shown[-1][1] = t
		was = on
		if shown.size() == 1 and t - shown[0][0] < 1.0 and r._look_target == world.car:
			looked = true
	var lines: Array = QuestLines.RESIDENT_LINES
	print("INFO: bubbles %s" % [shown])
	check(shown.size() == 2, "two bubbles in 25 s with the Lada alongside (%d)" % shown.size())
	if shown.size() >= 1:
		check(shown[0][0] < 0.2, "first bubble at once (%.2f s)" % shown[0][0])
		check(absf(shown[0][1] - shown[0][0] - Resident.BUBBLE_SECONDS) < 0.1, "bubble shown %.2f s (2)" % (shown[0][1] - shown[0][0]))
		check(lines.has(shown[0][2]), "bubble text '%s' from RESIDENT_LINES" % shown[0][2])
		check(looked, "%s looks at the Lada while speaking" % r.name)
	if shown.size() >= 2:
		check(shown[1][0] - shown[0][0] >= Resident.BUBBLE_COOLDOWN - 0.05, "next bubble no sooner than 20 s (%.2f s)" % (shown[1][0] - shown[0][0]))
		check(shown[1][2] != shown[0][2], "a different line the second time ('%s')" % shown[1][2])
	var back: Sprite3D = r.get_node_or_null("BubbleBack")
	var label: Label3D = back.get_node_or_null("Bubble") if back else null
	check(back != null and back.billboard == BaseMaterial3D.BILLBOARD_ENABLED and label != null and label.font == DialogPanelScript.ui_font() and label.modulate == Resident.INK, "bubble in the quest style (paper sprite, UI font, ink)")
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	await drv.frames(2)
	world.exit_car()
	await drv.frames(2)
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await drv.frames(2)

# =====================================================================================
# Геометрия и служебное
# =====================================================================================

## Точки замкнутой ломаной через step м.
func _samples(route: Array, step: float) -> Array:
	var out := []
	for i in route.size():
		var a: Vector3 = route[i]
		var b: Vector3 = route[(i + 1) % route.size()]
		var n := maxi(1, ceili(a.distance_to(b) / step))
		for j in n:
			out.append(a.lerp(b, float(j) / n))
	return out

func _rect_distance(rect: Rect2, q: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - q.x, 0.0), q.x - rect.end.x)
	var dz := maxf(maxf(rect.position.y - q.y, 0.0), q.y - rect.end.y)
	return Vector2(dx, dz).length()

func _polyline_distance(points: Array, q: Vector2, closed := false) -> float:
	var best := INF
	var count := points.size() if closed else points.size() - 1
	for i in count:
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[(i + 1) % points.size()].x, points[(i + 1) % points.size()].z)
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best

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
	print("RESIDENTS: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))
