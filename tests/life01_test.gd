extends SceneTree
## LIFE-01: жители живут по цепочкам целей (набор LIFE). Сцена main.tscn, как RESIDENTS.
## 1. Данные (Layout.LIFE_*, C1): граф связный; обычные рёбра — по тротуарам, Yard_Drive, площадке у подъезда и газонам
##    LIFE_GROUNDS, ни метра по проезжей части; от коробок all_solids() и разрушаемых ≥ LIFE_CLEARANCE (−0,05); ≥ 8 м от
##    постов и чекпоинта; вне KIOSK_ZONE и KIOSK_SQUARE; ≥ 2 м от ROUTE_WALK/ROUTE_DRIVE (кроме &"route"); ≥ 1,5 м от
##    путей SNEAK_*; переходы &"cross" начинаются и кончаются вне проезжей части; места точек и подходы к ним (от узла и
##    от ближайшего ребра) не в коробках и не в разрушаемых (≥ 0,5 м), двери подъездов — у дверей Buildings.door_log;
##    у каждого жителя-одиночки — персона с домом и цепочкой из существующих шагов.
## 2. Город SIM_SECONDS с: у каждого есть цель (точка), каждый посетил ≥ 2 разных точек; никто не стоит в ходьбе дольше
##    STALL_LIMIT; никто не на проезжей части вне переходов и не в коробках; все занятия PEOPLE-03 (domino, hood, dig, sweep,
##    slide, bench, carpet) и уход в подъезд и магазин запускались; кто-то ехал троллейбусом; в кадре камеры не больше
##    MAX_ON_SCREEN жителей.
## 3. Сбит «Ладой» по дороге к цели — встал и дошёл до той же цели.
## 4. reset_positions(): все на стартах, брони сняты.
## PEOPLE-03 (P2): данные — петля санок и площадка хоккея без коробок, пулы реплик занятий в лимитах TEXT-01; в городе
## запускаются hockey, snowball, trade, sled и звучат занятия; отдельно (часть P2): торговка у прилавка, хоккеисты
## катаются и пасуют шайбу, дети кидаются снежками и попадают, санки едут за бабушкой, птицы (голуби у контейнеров и
## голубятни, синицы у кормушки) взлетают от Илюши и «Лады» и садятся обратно, звук занятия слышен рядом и не
## запускается вдали, реплики занятий — из своих пулов без повторов подряд, сбитый хоккеист продолжает игру.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/life01_test.gd (после «--» слово data — только п. 1)

const Layout = preload("res://game/world/layout.gd")
const LifeScript = preload("res://game/world/life.gd")
const BuildingsScript = preload("res://game/world/buildings.gd")
const Driver = preload("res://tests/playthrough_driver.gd")

const SIM_SECONDS := 480.0
const STALL_LIMIT := 3.0
const MAX_ON_SCREEN := 12
const POST_CLEARANCE := 8.0
const ROUTE_CLEARANCE := 2.0
const SNEAK_CLEARANCE := 1.5
const SPOT_CLEARANCE := 0.5
const P1_KINDS: Array[StringName] = [&"domino", &"hood", &"dig", &"sweep", &"slide", &"bench", &"carpet", &"door", &"shop"]
const P2_KINDS: Array[StringName] = [&"hockey", &"snowball", &"trade", &"sled"]
const P2_SOUNDS: Array[StringName] = [&"domino", &"sweep", &"slide", &"stick", &"sled"]
const LINE_MAX_WORDS := 7
const LINE_MAX_CHARS := 40
const HOCKEY_KIDS: Array[int] = [20, 21]
const SNOW_KIDS: Array[int] = [13, 22]
const TRADER := 23
const SLED_GRAN := 24

var failures: Array[String] = []
var checks := 0
var main: Node
var drv
var world: DemoWorld
var residents_node: Node3D
var residents: Array = []
var life
var _solids: Array = []      # [имя, Rect2]
var _breaks: Array = []      # [id, Rect2]
var _roads: Array = []
var _walkable: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(2400.0, true, false, true).timeout.connect(func():
		push_error("FAIL: life01 test exceeded 2400 simulated seconds")
		_finish(2))
	var data_only := OS.get_cmdline_user_args().has("data")
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
	if not check(residents_node != null, "LevelGeometry/Residents attached"):
		_finish()
		return
	residents = residents_node.residents
	life = residents_node.life
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false
	for spec in Layout.all_solids():
		var c: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		_solids.append(["%s@(%.1f,%.1f)" % [spec[0], c.x, c.y], Rect2(c - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))])
	for spec in Layout.BREAKABLES + Layout.PROPS_BREAKABLES:
		_breaks.append([spec[0], Breakables.spec_rect(spec)])
	for surface in Layout.SURFACES:
		var rect := Rect2(surface[2] - surface[3] * 0.5, surface[3])
		if surface[1] == "road":
			_roads.append([surface[0], rect])
		elif surface[1] == "sidewalk" or surface[1] == "yard_road":
			_walkable.append(rect)
	_walkable.append(Layout.RESIDENT_ENTRANCE_AREA)
	_walkable.append_array(Layout.LIFE_GROUNDS)
	_part_data()
	if not data_only:
		await _part_city()
		await _part_p2()
		await _part_knock()
		_part_reset()
	_finish()

# =====================================================================================
# 1. Данные
# =====================================================================================

func _part_data() -> void:
	print("--- data ---")
	check(life != null and life.connected(), "path graph is connected (%d nodes, %d edges)" % [Layout.LIFE_NODES.size(), Layout.LIFE_EDGES.size()])
	var posts := [Layout.OFFICER_POST, Layout.OFFICER_POST_AFTER, Layout.OFFICER2_POST, Layout.ACCOUNT_OFFICER, Layout.STEALTH_CHECKPOINT]
	var sneaks: Array = []
	for path in [Layout.SNEAK_EAST, Layout.SNEAK_WEST, Layout.SNEAK_BACK, Layout.SNEAK_AGAIN]:
		var line: Array = []
		for part in path:
			if part is Array:
				line.append_array(part)
		sneaks.append(line)
	var kiosk := Rect2(Layout.KIOSK_ZONE.position.x, Layout.KIOSK_ZONE.position.z, Layout.KIOSK_ZONE.size.x, Layout.KIOSK_ZONE.size.z)
	for e in Layout.LIFE_EDGES:
		var flag: StringName = e[2] if e.size() > 2 else &""
		var a: Vector2 = Layout.LIFE_NODES[e[0]]
		var b: Vector2 = Layout.LIFE_NODES[e[1]]
		var label := "edge %s–%s%s" % [e[0], e[1], "" if flag == &"" else " (%s)" % flag]
		var bad := []
		var near_solid := [INF, ""]
		var min_post := INF
		var min_route := INF
		var min_sneak := INF
		var n := maxi(1, ceili(a.distance_to(b) / 0.25))
		for j in n + 1:
			var q := a.lerp(b, float(j) / n)
			if flag != &"cross":
				if not _walkable.any(func(w): return w.has_point(q)):
					bad.append("off-walk (%.1f, %.1f)" % [q.x, q.y])
				for road in _roads:
					if _rect_distance(road[1], q) < Resident.BODY_RADIUS:
						bad.append("on %s (%.1f, %.1f)" % [road[0], q.x, q.y])
			for s in _solids + _breaks:
				var d := _rect_distance(s[1], q)
				if d < near_solid[0]:
					near_solid = [d, s[0]]
			for p in posts:
				min_post = minf(min_post, q.distance_to(Vector2(p.x, p.z)))
			if flag == &"":
				min_route = minf(min_route, minf(_polyline_distance(Layout.ROUTE_WALK, q), _polyline_distance(Layout.ROUTE_DRIVE, q)))
			for line in sneaks:
				min_sneak = minf(min_sneak, _polyline_distance(line, q))
			if _rect_distance(kiosk, q) < 1.0 or Layout.KIOSK_SQUARE.has_point(q):
				bad.append("kiosk area (%.1f, %.1f)" % [q.x, q.y])
		if flag == &"cross":
			for q in [a, b]:
				for road in _roads:
					if _rect_distance(road[1], q) < Resident.BODY_RADIUS:
						bad.append("crossing ends on %s" % road[0])
				min_route = minf(min_route, minf(_polyline_distance(Layout.ROUTE_WALK, q), _polyline_distance(Layout.ROUTE_DRIVE, q)))
		var clear: float = Layout.LIFE_CLEARANCE - 0.05
		check(bad.is_empty() and near_solid[0] >= clear and min_post >= POST_CLEARANCE and min_route >= ROUTE_CLEARANCE and min_sneak >= SNEAK_CLEARANCE,
			"%s: walkable, solids %.2f m (%s), posts %.1f, routes %.1f, sneak %.1f%s" % [label, near_solid[0], near_solid[1], min_post, min_route, min_sneak, "" if bad.is_empty() else " — " + ", ".join(bad.slice(0, 3))])
	# Места точек и подходы.
	var doors: Array = BuildingsScript.door_log
	for s in Layout.LIFE_SPOTS:
		var id: StringName = s[0]
		var pos: Vector2 = s[3]
		var node: Vector2 = Layout.LIFE_NODES.get(s[2], Vector2.INF)
		if not check(node != Vector2.INF, "spot %s: node %s exists" % [id, s[2]]):
			continue
		var hit: Array = life.nearest_on_graph(Vector3(pos.x, 0, pos.y))
		var proj := Vector2(hit[0].x, hit[0].z)
		var worst := [INF, ""]
		var min_post := INF
		var min_route := INF
		for seg in [[node, pos], [proj, pos]]:
			var n := maxi(1, ceili(seg[0].distance_to(seg[1]) / 0.2))
			for j in n + 1:
				var q: Vector2 = seg[0].lerp(seg[1], float(j) / n)
				for r in _solids + _breaks:
					var d := _rect_distance(r[1], q)
					if d < worst[0]:
						worst = [d, r[0]]
				for p in posts:
					min_post = minf(min_post, q.distance_to(Vector2(p.x, p.z)))
				min_route = minf(min_route, minf(_polyline_distance(Layout.ROUTE_WALK, q), _polyline_distance(Layout.ROUTE_DRIVE, q)))
		var on_road := _roads.any(func(r): return _rect_distance(r[1], pos) < Resident.BODY_RADIUS)
		check(worst[0] >= SPOT_CLEARANCE and min_post >= POST_CLEARANCE and min_route >= ROUTE_CLEARANCE and not on_road,
			"spot %s (%s): place and approaches clear (%.2f m from %s), posts %.1f, routes %.1f" % [id, s[1], worst[0], worst[1], min_post, min_route])
		if s[1] == &"door":
			var nearest := INF
			for d in doors:
				nearest = minf(nearest, Vector2(d.x, d.z).distance_to(pos))
			check(nearest < 0.7, "spot %s: a built entrance door within 0.7 m (%.2f)" % [id, nearest])
	var kinds := {}
	for s in Layout.LIFE_SPOTS:
		kinds[s[1]] = true
	for i in residents.size():
		var r: Resident = residents[i]
		if r.leader != null:
			continue
		var persona: Dictionary = LifeScript.PERSONAS[i]
		var ok: bool = life.spots.has(persona.get("home", &"")) and not persona.get("plan", []).is_empty()
		for step in persona.get("plan", []):
			ok = ok and (step == &"home" or kinds.has(step) or life.spots.has(step))
		check(ok and r.errand, "%s: persona with a home door and a plan of known steps %s" % [r.name, persona.get("plan", [])])
	_part_p2_data(posts)

## PEOPLE-03 (P2): петля санок — по газонам, ≥ LIFE_CLEARANCE от коробок и разрушаемых, ≥ 8 м от постов, ≥ 2 м от
## путей игрока; площадка хоккея — внутри коробки, ≥ 1 м от бортов; пулы реплик занятий — 1–7 слов, ≤ 40 знаков.
func _part_p2_data(posts: Array) -> void:
	print("--- P2 data ---")
	var loop: Array = Layout.LIFE_SLED_LOOP
	var worst := [INF, ""]
	var off := []
	var min_post := INF
	var min_route := INF
	for i in loop.size() - 1:
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[i + 1]
		var n := maxi(1, ceili(a.distance_to(b) / 0.25))
		for j in n + 1:
			var q := a.lerp(b, float(j) / n)
			if not _walkable.any(func(w): return w.has_point(q)):
				off.append("(%.1f, %.1f)" % [q.x, q.y])
			for r in _solids + _breaks:
				var d := _rect_distance(r[1], q)
				if d < worst[0]:
					worst = [d, r[0]]
			for p in posts:
				min_post = minf(min_post, q.distance_to(Vector2(p.x, p.z)))
			min_route = minf(min_route, minf(_polyline_distance(Layout.ROUTE_WALK, q), _polyline_distance(Layout.ROUTE_DRIVE, q)))
	check(off.is_empty() and worst[0] >= Layout.LIFE_CLEARANCE - 0.05 and min_post >= POST_CLEARANCE and min_route >= ROUTE_CLEARANCE,
		"sled loop: walkable, %.2f m from %s, posts %.1f, routes %.1f%s" % [worst[0], worst[1], min_post, min_route, "" if off.is_empty() else " — off at " + ", ".join(off.slice(0, 3))])
	var sled_pos: Vector3 = life.spots[&"sled"].pos
	check(loop[0] == Vector2(sled_pos.x, sled_pos.z) and loop[0] == loop[-1], "sled loop starts and ends at the sled spot")
	var area: Rect2 = Layout.LIFE_RINK_AREA
	var rink := Rect2(Layout.RINK[0] - Vector2(Layout.RINK[1].x, Layout.RINK[1].z) * 0.5, Vector2(Layout.RINK[1].x, Layout.RINK[1].z))
	var board := INF
	for corner in [area.position, area.end, Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.position.y)]:
		board = minf(board, minf(minf(corner.x - rink.position.x, rink.end.x - corner.x), minf(corner.y - rink.position.y, rink.end.y - corner.y)))
	check(rink.encloses(area) and board >= 1.0, "hockey area inside the rink, ≥ 1 m from the boards (%.2f m)" % board)
	for id in [&"hockey_w", &"hockey_e", &"hockey_c"]:
		var pos: Vector3 = life.spots[id].pos
		check(area.has_point(Vector2(pos.x, pos.z)), "spot %s inside the hockey area" % id)
	for kind in QuestLines.ACTIVITY_LINES:
		var pool: Array = QuestLines.activity_lines(kind)
		var bad := []
		var seen := {}
		for text: String in pool:
			var words := QuestLines.word_count(text)
			if words < 1 or words > LINE_MAX_WORDS or text.length() > LINE_MAX_CHARS or seen.has(text):
				bad.append(text)
			seen[text] = true
		check(pool.size() >= 5 and bad.is_empty(), "activity lines %s: %d lines, 1–%d words, ≤ %d chars, no repeats %s" % [kind, pool.size(), LINE_MAX_WORDS, LINE_MAX_CHARS, bad])
	check(QuestLines.activity_lines(&"domino").has("Рыба!"), "domino players say «Рыба!»")

# =====================================================================================
# 2. Город: цели, посещения, застревания, дорога, занятия, троллейбус, кадр
# =====================================================================================

func _part_city() -> void:
	print("--- city %d s ---" % int(SIM_SECONDS))
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	residents_node.reset_positions()
	await drv.frames(1)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var stall := {}
	var worst_stall := {}
	var last := {}
	var no_goal := {}
	var road_hits := {}
	var solid_hits := {}
	var max_screen := 0
	var kinds := {}
	var rides := 0
	for r in residents:
		stall[r] = 0.0
		worst_stall[r] = 0.0
		last[r] = Vector3(r.global_position)
	var camera := world.get_viewport().get_camera_3d()
	var frames := int(SIM_SECONDS / dt)
	for frame in frames:
		await physics_frame
		var screen := 0
		for r in residents:
			var here := Vector3(r.global_position.x, 0, r.global_position.z)
			if r.state == &"walk" and not r.hidden:
				stall[r] = stall[r] + dt if here.distance_to(last[r]) < 0.0005 else 0.0
				worst_stall[r] = maxf(worst_stall[r], stall[r])
			else:
				stall[r] = 0.0
			last[r] = here
			if r.leader == null and r.spot_id == &"" and r.state != &"knocked" and frame > 60 * 30:
				no_goal[r.name] = "%s without a goal at %.0f s (%s)" % [r.name, frame * dt, r.state]
			if frame % 6 == 0 and not r.hidden and not r.state in [&"board", &"alight", &"transit", &"knocked"]:
				var q := Vector2(here.x, here.z)
				var on_cross: bool = r.on_crossing()
				for road in _roads:
					if not on_cross and _rect_distance(road[1], q) < Resident.BODY_RADIUS:
						road_hits[r.name] = "%s on %s at (%.1f, %.1f) %s" % [r.name, road[0], q.x, q.y, r.state]
				if r.global_position.y < 0.3 and not r.on_slide():   # лесенка горки — внутри коробки горки
					for s in _solids:
						if _rect_distance(s[1], q) < Resident.BODY_RADIUS:
							solid_hits[r.name] = "%s in %s at (%.1f, %.1f)" % [r.name, s[0], q.x, q.y]
			if frame % 30 == 0 and not r.hidden and camera and camera.is_position_in_frustum(r.global_position + Vector3.UP) \
					and camera.global_position.distance_to(r.global_position) < 60.0:
				screen += 1
		max_screen = maxi(max_screen, screen)
	for r in residents:
		for e in r.activity_log:
			kinds[e[1]] = kinds.get(e[1], 0) + 1
		rides += r.events.filter(func(e): return e[1] == &"board").size()
	print("INFO: activities started %s, boardings %d, max residents on screen %d" % [kinds, rides, max_screen])
	for r in residents:
		var distinct := {}
		for v in r.visits:
			distinct[v[1]] = true
		var lead: Resident = r.leader if r.leader != null else r
		print("INFO: %s visits %s" % [r.name, lead.visits.map(func(v): return "%s@%.0f" % [v[1], v[0]])])
		if r.leader == null:
			check(distinct.size() >= 2, "%s visited %d different spots in %.0f s (≥ 2)" % [r.name, distinct.size(), SIM_SECONDS])
		check(worst_stall[r] <= STALL_LIMIT, "%s: never stuck while walking (longest stall %.2f s)" % [r.name, worst_stall[r]])
	check(no_goal.is_empty(), "every resident always has a goal %s" % [no_goal.values().slice(0, 4)])
	check(road_hits.is_empty(), "nobody on a road outside crossings%s" % ("" if road_hits.is_empty() else " — " + ", ".join(road_hits.values().slice(0, 4))))
	check(solid_hits.is_empty(), "nobody inside a Layout solid%s" % ("" if solid_hits.is_empty() else " — " + ", ".join(solid_hits.values().slice(0, 4))))
	for k in P1_KINDS + P2_KINDS:
		check(kinds.get(k, 0) >= 1, "activity %s started (%d)" % [k, kinds.get(k, 0)])
	print("INFO: activity sounds %s" % [residents_node.activity_sounds])
	for k in P2_SOUNDS:
		check(int(residents_node.activity_sounds.get(k, 0)) >= 1, "activity sound %s emitted (%d)" % [k, residents_node.activity_sounds.get(k, 0)])
	var act_said := {}
	for r in residents:
		for b in r.bubble_log:
			for kind in QuestLines.ACTIVITY_LINES:
				if QuestLines.activity_lines(kind).has(b[2]):
					act_said[kind] = int(act_said.get(kind, 0)) + 1
	print("INFO: activity lines said %s" % [act_said])
	check(not act_said.is_empty(), "residents at their activities speak lines from the activity pools %s" % [act_said])
	check(rides >= 1, "someone rode trolleybus 13 (%d boardings)" % rides)
	check(max_screen >= 1 and max_screen <= MAX_ON_SCREEN, "residents on screen within 60 m: max %d (1–%d)" % [max_screen, MAX_ON_SCREEN])

# =====================================================================================
# P2. Занятия PEOPLE-03: торговка, хоккей, снежки, санки, птицы, звук, реплики, сбитый хоккеист
# =====================================================================================

func _part_p2() -> void:
	print("--- P2 activities ---")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	residents_node.reset_positions()
	var trader: Resident = residents[TRADER]
	var gran: Resident = residents[SLED_GRAN]
	var hockey: Array = HOCKEY_KIDS.map(func(i): return residents[i])
	var snow: Array = SNOW_KIDS.map(func(i): return residents[i])
	# Торговка — у прилавка, лицом к тротуару; банки на прилавке.
	var t := await _wait_until(func(): return trader.is_playing(&"trade"), 60 * 60)
	var spot: Dictionary = life.spots[&"trade"]
	check(t >= 0 and Resident._flat(trader.global_position).distance_to(spot.pos) < 0.05 and is_equal_approx(trader.facing_yaw, spot.yaw),
		"trader stands at the stall facing the sidewalk (%.0f s)" % (t / 60.0))
	var stall_ok: bool = residents_node.get_node_or_null("LifeProps/Stall") != null
	var b_root = get_first_node_in_group(&"breakables_root")
	if b_root and b_root.has_method(&"get_by_id") and b_root.get_by_id(Layout.LIFE_STALL) != null:
		stall_ok = true
	check(stall_ok and life.props.has(&"jars") and life.props[&"jars"].visible, "the stall and the pickle jars are there while she trades")
	# Санки — едут за бабушкой.
	await _wait_until(func(): return gran.is_playing(&"sled"), 60 * 60)
	var walked: float = gran.distance_walked
	var max_gap := 0.0
	for k in 600:
		await physics_frame
		if gran.sled_node():
			max_gap = maxf(max_gap, Resident._flat(gran.sled_node().global_position).distance_to(Resident._flat(gran.global_position)))
	check(gran.is_playing(&"sled") and gran.distance_walked - walked > 5.0 and gran.sled_node() != null and max_gap <= Resident.SLED_BACK + 0.3,
		"granny pulls the sled around Z15 (%.1f m in 10 s, sled ≤ %.2f m behind)" % [gran.distance_walked - walked, max_gap])
	# Хоккей: оба на льду, катаются внутри площадки, шайба ходит.
	t = await _wait_until(func(): return hockey.all(func(r): return r.is_playing(&"hockey")), 90 * 60)
	check(t >= 0, "both hockey kids skate in the rink (%.0f s)" % (t / 60.0))
	var moves: int = life.hockey_passes + life.hockey_shots
	var puck: Node3D = life.props.get(&"puck")
	var puck_from: Vector3 = puck.global_position if puck else Vector3.ZERO
	var outside := 0
	for k in 20 * 60:
		await physics_frame
		for r in hockey:
			if r.is_playing(&"hockey") and not Layout.LIFE_RINK_AREA.grow(0.05).has_point(Vector2(r.global_position.x, r.global_position.z)):
				outside += 1
	var sticks: bool = hockey.all(func(r): return r.get_node_or_null("Stick") != null and r.get_node("Stick").visible)
	check(life.hockey_passes + life.hockey_shots - moves >= 3 and puck != null and puck.global_position.distance_to(puck_from) > 1.0,
		"the puck goes around: %d passes, %d shots" % [life.hockey_passes, life.hockey_shots])
	check(outside == 0 and sticks, "hockey kids stay inside the rink area with sticks (%d frames outside)" % outside)
	# Снежки: двое у крепости, кидают и попадают.
	t = await _wait_until(func(): return snow.all(func(r): return r.is_playing(&"snowball")), 150 * 60)
	check(t >= 0, "two kids at the snow fort (%.0f s)" % (t / 60.0))
	var thrown: int = snow[0].snowballs + snow[1].snowballs
	await _wait_until(func(): return snow[0].snow_hits + snow[1].snow_hits >= 1 and snow[0].snowballs + snow[1].snowballs - thrown >= 3, 30 * 60)
	check(snow[0].snowballs + snow[1].snowballs - thrown >= 3 and snow[0].snow_hits + snow[1].snow_hits >= 1,
		"snowballs fly across the fort and hit (%d thrown, %d hits)" % [snow[0].snowballs + snow[1].snowballs, snow[0].snow_hits + snow[1].snow_hits])
	await _part_p2_sound(hockey)
	await _part_p2_birds()
	_part_p2_lines()
	await _part_p2_knock(hockey)

## Звук занятия: рядом с коробкой клюшка слышна, от спавна (≈ 90 м) — не запускается.
func _part_p2_sound(hockey: Array) -> void:
	var sound: Node = world.get_node_or_null("SoundDirector")
	if not check(sound != null and sound.get("life_players") != null, "SoundDirector has activity sound players"):
		return
	world.player.place(Vector3(62.0, 0, 84.0), 0.0)
	await drv.frames(90)
	var near: int = sound.played["life_stick"]
	await _wait_until(func(): return sound.played["life_stick"] - near >= 2, 30 * 60)
	check(sound.played["life_stick"] - near >= 2, "hockey stick heard next to the rink (%d)" % (sound.played["life_stick"] - near))
	var p: AudioStreamPlayer3D = sound.life_players[&"stick"]
	check(p.max_distance <= 40.0 and p.volume_db <= -6.0, "activity sounds are quiet 3D: %.0f dB, heard to %.0f m" % [p.volume_db, p.max_distance])
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await drv.frames(90)
	var far: int = sound.played["life_stick"]
	var skipped: int = sound.played["life_far"]
	for k in 15 * 60:
		await physics_frame
	check(sound.played["life_stick"] == far and sound.played["life_far"] > skipped and hockey.any(func(r): return r.is_playing(&"hockey")),
		"…and silent from the spawn (%d far sounds skipped)" % (sound.played["life_far"] - skipped))

## Птицы: голуби у контейнеров и синицы у кормушки — от Илюши, голуби у голубятни — от «Лады»; садятся обратно.
func _part_p2_birds() -> void:
	var amb: Node = world.get_node_or_null("LevelGeometry/Ambient")
	var sound: Node = world.get_node_or_null("SoundDirector")
	if not check(amb != null and amb.pigeons.size() >= 6 and amb.tits.size() >= 2, "pigeons and tits are there (%d, %d)" % [amb.pigeons.size() if amb else 0, amb.tits.size() if amb else 0]):
		return
	check(amb.pigeons.all(func(b): return b.state == &"sit") and amb.tits.all(func(b): return b.state == &"sit"), "birds start sitting")
	var bins_flock: Array = amb.flocks[2][0]
	var wings: int = sound.played["life_wings"]
	world.player.place(Vector3(-33.0, 0, 72.0), 0.0)
	await drv.frames(30)
	check(bins_flock.all(func(b): return b.state != &"sit") and amb.bird_flushes[&"pigeon"] >= 1, "pigeons at the yard bins take off when Ilyusha comes near")
	check(sound.played["life_wings"] > wings, "wings flap heard (%d)" % (sound.played["life_wings"] - wings))
	world.player.place(Vector3(-64.0, 0, 95.5), 0.0)
	await drv.frames(30)
	check(amb.tits.all(func(b): return b.state != &"sit") and amb.bird_flushes[&"tit"] >= 1, "tits at the feeder fly up when Ilyusha comes near")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var settled := await _wait_until(func(): return bins_flock.all(func(b): return b.state == &"sit") and amb.tits.all(func(b): return b.state == &"sit"), 40 * 60)
	check(settled >= 0, "…and they settle back once he is gone (%.1f s)" % (settled / 60.0))
	var roof: Array = amb.flocks[0][0]
	world.car.reset_to(Vector3(86.0, 0, 105.5), 0.0)
	await drv.frames(30)
	check(roof.all(func(b): return b.state != &"sit"), "pigeons on the dovecote take off from the Lada")
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	check(amb.coos >= 1, "pigeons coo (%d)" % amb.coos)

## Реплики занятий: idle и walk на занятии — из пула занятия, подряд без повторов.
func _part_p2_lines() -> void:
	var r: Resident = residents[0]
	var was_acting: bool = r._acting
	var was_kind: StringName = r._act_kind
	for kind in QuestLines.ACTIVITY_LINES:
		r._acting = true
		r._act_kind = kind
		var pool: Array = QuestLines.activity_lines(kind)
		var seq := []
		for k in pool.size() * 3:
			seq.append(r.pick_line(&"idle" if k % 2 == 0 else &"walk"))
		var repeats := 0
		for k in range(1, seq.size()):
			if seq[k] == seq[k - 1]:
				repeats += 1
		check(seq.all(func(x): return pool.has(x)) and repeats == 0, "%s: idle/walk lines come from its pool, no repeats in a row" % kind)
	r._acting = was_acting
	r._act_kind = was_kind

## Сбитый хоккеист встаёт и продолжает игру с места.
func _part_p2_knock(hockey: Array) -> void:
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var r: Resident = hockey[0]
	if not check(await _wait_until(func(): return r.is_playing(&"hockey"), 60 * 60) >= 0, "%s plays hockey before the knock" % r.name):
		return
	var resumes: int = r.resumes
	world.car.reset_to(Vector3(Layout.RINK[0].x, 0, Layout.RINK[0].y), 0.0)
	var hit := -1
	for frame in 240:
		var to: Vector3 = Resident._flat(r.global_position) - Resident._flat(world.car.global_position)
		world.car.velocity = to.normalized() * 6.0
		await physics_frame
		if r.state == &"knocked":
			hit = frame
			break
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	check(hit >= 0, "Lada knocks %s on the ice (frame %d)" % [r.name, hit])
	await _wait_until(func(): return r.knock_phase == &"", 20 * 60)
	check(r.resumes == resumes + 1 and r.is_playing(&"hockey"), "after getting up %s goes on playing hockey (%s)" % [r.name, r.state])

# =====================================================================================
# 3. Сбит по дороге к цели — встал и дошёл до той же цели
# =====================================================================================

func _part_knock() -> void:
	print("--- knocked on the way ---")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	residents_node.reset_positions()
	var r: Resident = residents[3]   # улица A, северный тротуар: первый отрезок на запад
	await _wait_until(func(): return r.state == &"walk" and r.spot_id != &"" and r.global_position.x < 38.0, 40 * 60)
	if not check(r.spot_id != &"", "%s walks to a goal (%s)" % [r.name, r.spot_id]):
		return
	var goal: StringName = r.spot_id
	var visits: int = r.visits.size()
	var dir := Vector3(-1, 0, 0)
	world.car.reset_to(r.global_position - dir * (Lada.SIZE.z * 0.5 + 1.2), atan2(-dir.x, -dir.z))
	var hit := -1
	for frame in 90:
		world.car.velocity = dir * 6.0
		await physics_frame
		if r.state == &"knocked":
			hit = frame
			break
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	check(hit >= 0 and r.knocks == 1, "Lada at 6 m/s knocks %s (frame %d)" % [r.name, hit])
	await _wait_until(func(): return r.knock_phase == &"", 20 * 60)
	check(r.state != &"knocked" and r.spot_id == goal, "after getting up %s keeps its goal %s (%s)" % [r.name, goal, r.spot_id])
	var arrived := await _wait_until(func(): return r.visits.size() > visits, 120 * 60)
	check(arrived >= 0 and r.visits[-1][1] == goal, "…and reaches it (%s)" % [r.visits[-1] if r.visits.size() > visits else "no visit"])

# =====================================================================================
# 4. reset_positions()
# =====================================================================================

func _part_reset() -> void:
	print("--- reset ---")
	residents_node.reset_positions()
	var worst := 0.0
	for r in residents:
		var start: Vector3 = Layout.RESIDENT_ROUTES[r.index][Layout.RESIDENT_STARTS[r.index]]
		if r.leader == null:
			worst = maxf(worst, Vector2(r.global_position.x - start.x, r.global_position.z - start.z).length())
	var held := 0
	for id in life.reserved:
		held += life.reserved[id].size()
	var visible := residents.all(func(r): return r.visible and not r.hidden and r.visits.size() <= 1 and r.goals <= 1)
	check(worst < 0.001, "reset_positions(): everyone on the start (worst %.4f m)" % worst)
	check(visible, "reset_positions(): visible, logs cleared")
	var smokers := residents.filter(func(r): return r.state == &"smoke" or life.spots.get(r.spot_id, {}).get("kind") == &"smoke")
	check(held == residents.filter(func(r): return r.spot_id != &"" and r.leader == null).size(), "reset_positions(): only the first goals reserved (%d)" % held)
	check(smokers.size() == 2 and residents[10].state == &"smoke", "the two smokers go for a smoke at the entrance, resident 10 already smoking (%d)" % smokers.size())

# =====================================================================================
# Служебное
# =====================================================================================

func _rect_distance(rect: Rect2, q: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - q.x, 0.0), q.x - rect.end.x)
	var dz := maxf(maxf(rect.position.y - q.y, 0.0), q.y - rect.end.y)
	return Vector2(dx, dz).length()

func _polyline_distance(points: Array, q: Vector2) -> float:
	var best := INF
	for i in points.size() - 1:
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[i + 1].x, points[i + 1].z)
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best

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
	print("LIFE01: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))
