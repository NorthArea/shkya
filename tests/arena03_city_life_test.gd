extends SceneTree
## ARENA-03: реальные жители, очереди и пешие продолжения квартала.

const Layout = preload("res://game/world/layout.gd")
const Life = preload("res://game/world/life.gd")
var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var people: Node
var life
var buyer: Resident
var first: Resident
var second: Resident

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(12)
	world = main.world
	people = world.get_node("LevelGeometry/Residents")
	life = people.life
	if not check(people.residents.size() >= 64, "at least 64 actual residents are instantiated"):
		await _finish()
		return
	check(life.connected(), "all pedestrian neighbourhoods belong to one connected graph")
	for resident: Resident in people.residents:
		if resident.leader == null:
			check(resident.home != &"" and not resident.plan.is_empty(), "%s has a home and personal errands" % resident.name)
	for id in [&"door_h11", &"edge_d_n", &"edge_a_w", &"chat_i1", &"chat_i2"]:
		check(life.spots.has(id), "live destination %s exists" % id)
	for id in [&"notice_h11", &"notice_h7"]:
		check(life.spots.has(id), "local errand %s is attached to an actual entrance noticeboard" % id)
	var phased: Array = people.residents.filter(func(resident): return resident.get("plan_start") != null and int(resident.get("plan_start")) > 0)
	check(phased.size() >= 3, "local residents start in different phases of their daily routines")
	for resident: Resident in people.residents:
		resident.set_physics_process(false)
		resident._act_stop()
		resident._show()
	life.reset()
	buyer = people.residents[46]
	first = people.residents[47]
	second = people.residents[53]
	_queue()
	_near_customers()
	_worksite()
	_h11_entrance()
	_store_entrances()
	_shop_pair_turn()
	await _direct_d_crossing()
	if OS.get_cmdline_user_args().has("break"):
		_broken_services()
	else:
		print("NOT_RUN: BREAK integration scenarios; run this suite with user argument 'break' after BREAK-03 integration")
	await _frames(2)
	await _finish()

func _at(resident: Resident, id: StringName) -> void:
	resident._act_stop()
	if resident.spot_id != &"": life.release(resident.spot_id, resident)
	resident.spot_id = id
	resident.knock_phase = &""
	resident._show()
	resident.place(life.spots[id].pos)
	resident._go_to(id)

func _queue() -> void:
	_at(buyer, &"press")
	var destination: StringName = life.choose(first, &"press", first.home, first.rng)
	check(destination == &"press_q1", "an occupied press window offers the first waiting place")
	_at(first, destination)
	destination = life.choose(second, &"press", second.home, second.rng)
	check(destination == &"press_q2", "the next visitor joins behind the first")
	_at(second, destination)
	check(life.queue_next(first) == &"" and life.queue_next(second) == &"", "both wait while the customer is served")
	check(first.is_visible_in_tree() and not first.hidden, "waiting customers remain visibly present")
	life.release(&"press", buyer)
	buyer._act_stop()
	check(life.choose(buyer, &"press", buyer.home, buyer.rng) == &"", "a newcomer cannot overtake the existing queue")
	check(life.queue_next(first) == &"press", "the first waiting customer can claim the free service")
	check(life.queue_next(second) == &"", "the second cannot overtake the first")
	first._tick_activity(1.0 / 60.0)
	check(first.spot_id == &"press" and first.state == &"walk", "service release starts the real walk to the window")
	check(not life.reserved.get(&"press_q1", []).has(first) and life.reserved.get(&"press", []).has(first), "the customer transfers the reservation once")
	check(first.global_position.distance_to(life.spots[&"press"].pos) > 1.0, "service does not teleport or complete remotely")
	check(life.queue_next(second) == &"press_q1", "the remaining queue advances into the vacant front place")
	second._tick_activity(1.0 / 60.0)
	check(second.spot_id == &"press_q1", "the second resident reserves and approaches the front place")
	_walk_queue_front(second, &"press_q1")
	_at(first, &"press")
	var visits_before := first.visits.size()
	first._wait = 0.01
	first._tick_activity(0.02)
	check(not life.reserved.get(&"press", []).has(first), "completed purchase releases the window")
	check(first.spot_id != &"press" and first.visits.size() == visits_before, "the customer continues their personal plan rather than completing the next errand remotely")
	life.reset()
	_at(first, &"press_q1")
	_at(second, &"press_q2")
	world.car.reset_to(first.global_position, -PI * 0.5)
	world.car.velocity = Vector3(4.0, 0.0, 0.0)
	var knocks_before := first.knocks
	first._physics_process(1.0 / 60.0)
	check(first.knocks == knocks_before + 1 and first.knock_phase == &"fly", "the real car contact launches a waiting customer through the normal knock lifecycle")
	check(life.queue_next(second) == &"press", "a genuinely knocked waiting customer does not block the next shopper")
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	world.car.velocity = Vector3.ZERO
	for i in 3600:
		first._physics_process(1.0 / 60.0)
		if first.knock_phase == &"" and first.is_playing(&"queue"): break
	check(first.knock_phase == &"" and first.is_playing(&"queue"), "the waiting customer recovers and walks back to their reserved place")
	life.reset()
	_at(buyer, &"shaw")
	check(life.choose(first, &"shaw", first.home, first.rng) == &"shaw_q1", "shawarma uses the same bounded queue mechanism")
	_at(first, &"shaw_q2")
	first._tick_activity(1.0 / 60.0)
	_walk_queue_front(first, &"shaw_q1")
	for id in life.spots:
		var spot: Dictionary = life.spots[id]
		if spot.kind == &"queue":
			check(not Layout.KIOSK_SQUARE.has_point(Vector2(spot.pos.x, spot.pos.z)), "%s does not enter the bread stealth area" % id)

func _walk_queue_front(resident: Resident, destination: StringName) -> void:
	var target: Vector3 = life.spots[destination].pos
	var previous := resident.global_position
	var remaining := previous.distance_to(target)
	var reverse := false
	var jump := false
	for i in 600:
		resident._physics_process(1.0 / 60.0)
		var at := resident.global_position
		var next_remaining := at.distance_to(target)
		reverse = reverse or next_remaining > remaining + 0.001
		jump = jump or at.distance_to(previous) > 0.15
		previous = at
		remaining = next_remaining
		if resident.is_playing(&"queue"): break
	check(remaining < 0.02 and resident.is_playing(&"queue") and not reverse and not jump, "%s advances by real monotonic steps without overshooting the waiting place" % destination)

func _near_customers() -> void:
	life.reset()
	buyer._act_stop()
	buyer._show()
	buyer.place(life.nodes[&"a_s_e3"])
	buyer._go_to(&"shaw")
	check(buyer.state == &"walk" and not life.reserved.get(&"shaw", []).has(buyer), "a distant customer has an intention, without reserving an empty service window")
	_at(first, &"shaw_q1")
	var visits_before := first.visits.size()
	first._tick_activity(1.0 / 60.0)
	check(first.spot_id == &"shaw" and first.state == &"walk", "an actually waiting customer can approach the empty window while the distant customer is still walking")
	check(first.visits.size() == visits_before and not first.is_playing(&"window"), "claiming service does not serve the waiting customer remotely")
	for i in 1200:
		first._physics_process(1.0 / 60.0)
		if first.is_playing(&"window"): break
	check(first.is_playing(&"window") and first.global_position.distance_to(life.spots[&"shaw"].pos) < 0.02, "the local customer is served after the real walk to the window")
	check(buyer.global_position.distance_to(life.spots[&"shaw"].pos) > 15.0, "the distant customer's unfinished journey does not block local service")
	# Двое подошли к занятому окну в одном шаге; порядок очереди — по реальному приходу.
	_at(second, &"shaw")
	_at(buyer, &"shaw")
	check(life.reserved.get(&"shaw", []).size() == 1 and life.reserved[&"shaw"][0] == first, "simultaneous newcomers cannot claim an occupied service window")
	var arrivals: Array = []
	for i in 1200:
		for resident: Resident in [second, buyer]:
			resident._physics_process(1.0 / 60.0)
			if resident.is_playing(&"queue") and not arrivals.has(resident): arrivals.append(resident)
		if arrivals.size() == 2: break
	check(arrivals.size() == 2 and arrivals[0].spot_id == &"shaw_q1" and arrivals[1].spot_id == &"shaw_q2", "two approaching customers join different waiting places in order of arrival")
	life.release(&"shaw", first)
	first._act_stop()
	if arrivals.size() == 2:
		check(life.queue_next(arrivals[0]) == &"shaw" and life.queue_next(arrivals[1]) == &"", "the first real arrival retains priority when service is released")

func _worksite() -> void:
	life.reset()
	_at(first, &"dig_2")
	first.sound_counts.clear()
	for i in 180:
		first._tick_activity(1.0 / 60.0)
		first._process(1.0 / 60.0)
	check(first.sound_counts.get(&"dig", 0) == 0, "the observer does not produce imaginary shovel strikes")
	check(first._work_tool == null or not first._work_tool.visible, "the observer has no working shovel")
	_at(first, &"dig_1")
	for i in 180:
		first._tick_activity(1.0 / 60.0)
		first._process(1.0 / 60.0)
	check(first.sound_counts.get(&"dig", 0) > 0 and first._work_tool.visible, "the actual digger works visibly and produces the worksite sound")

func _h11_entrance() -> void:
	life.reset()
	first._act_stop()
	first._show()
	first.home = &"door_h11"
	first.plan = [&"home", &"apteka"]
	first.plan_i = 0
	first.place(life.nodes[&"dw_h11"])
	first._go_to(&"door_h11")
	var entered := false
	var left := false
	var crossed_gate := false
	var bad_steps := false
	var hit_fence := false
	var previous := first.global_position
	for i in 7200:
		first._physics_process(1.0 / 60.0)
		var p := first.global_position
		bad_steps = bad_steps or p.distance_to(previous) > 0.15
		previous = p
		for spec in Layout.PROPS_BREAKABLES:
			if String(spec[0]).begins_with("Z18_1_") and spec[1] == &"fence":
				var rect: Rect2 = Breakables.spec_rect(spec)
				if rect.grow(Resident.BODY_RADIUS).has_point(Vector2(p.x, p.z)):
					hit_fence = true
		if absf(p.x + 84.6) < 0.1 and absf(p.z + 70.5) < 0.2: crossed_gate = true
		if first.hidden: entered = true
		if entered and not first.hidden and p.distance_to(life.spots[&"door_h11"].pos) > 3.0:
			left = true
			break
	check(entered and left, "a resident walks from the connected sidewalk into H11 and back out on their next errand")
	check(crossed_gate and not hit_fence and not bad_steps, "H11 entrance uses the permanent railing opening without clipping or teleportation")

func _store_entrances() -> void:
	for id in [&"apteka", &"gastro"]:
		var entrance: Node3D = world.get_node("LevelGeometry/Buildings/StoreEntrance_%s" % id)
		var spot: Dictionary = life.spots[id]
		var forward := Vector3(-sin(spot.yaw), 0.0, -cos(spot.yaw))
		check(entrance.global_position.distance_to(spot.pos + forward * 0.58) < 0.02, "%s has a visible door at the real arrival point" % id)

func _shop_pair_turn() -> void:
	life.reset()
	var lead: Resident = people.residents[6]
	var follower: Resident = people.residents[8]
	lead._act_stop()
	lead._show()
	lead.home = &"door_h10w"
	lead.plan = [&"shop24", &"home"]
	lead.plan_i = 0
	lead.place(life.spots[&"shop24"].pos)
	lead._go_to(&"shop24")
	follower._mirror(lead)
	var closest := INF
	var samples := 0
	for i in 6000:
		lead._physics_process(1.0 / 60.0)
		if lead.hidden or lead.state != &"walk": continue
		var goal: Vector3 = life.spots[lead.spot_id].pos
		var away := lead._trail.size() > 1 and lead.global_position.distance_to(lead._trail[0]) > 3.0 and lead.global_position.distance_to(goal) > 3.0
		if away:
			samples += 1
			closest = minf(closest, lead.global_position.distance_to(follower.global_position))
		if lead.target_point >= 3 and lead.global_position.distance_to(life.spots[&"shop24"].pos) > 6.0: break
	check(samples >= 10 and closest >= 0.3, "a real pair leaving the shop door remains separated through the pavement turn (%.9f m)" % closest)

func _direct_d_crossing() -> void:
	var route: Dictionary = life.path(life.spots[&"door_h11"].pos, &"shop24", &"door_h11")
	var length := 0.0
	for i in route.points.size() - 1: length += route.points[i].distance_to(route.points[i + 1])
	check(length < 90.0, "H11 can reach the shop opposite without a circuit of the district (%.1f m)" % length)
	var crossing: Array = []
	for edge in life.edges:
		var a: Vector3 = life.nodes[edge[0]]
		var b: Vector3 = life.nodes[edge[1]]
		if edge[2] == &"cross" and minf(a.x, b.x) < -66.0 and maxf(a.x, b.x) > -54.0 and a.z < 0.0:
			crossing = [a, b]
	if not check(not crossing.is_empty(), "the D connection is a real pedestrian crossing, not an unmarked walk across traffic"):
		return
	life.reset()
	first._act_stop()
	first._show()
	first.place(life.spots[&"door_h11"].pos)
	first._from_spot = &"door_h11"
	first._go_to(&"shop24")
	var midpoint: Vector3 = (crossing[0] + crossing[1]) * 0.5
	world.car.reset_to(midpoint, 0.0)
	world.car.velocity = Vector3.ZERO
	world.enter_car()
	for i in 7200:
		first._physics_process(1.0 / 60.0)
		if first.state == &"wait_cross": break
	check(first.state == &"wait_cross" and first.global_position.x < -66.0 - Resident.BODY_RADIUS, "a resident waits on the pavement while the occupied Lada blocks D (state=%s at=%s)" % [first.state, first.global_position])
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	check(world.exit_car(), "Ilyusha leaves the real car after moving it away from the crossing")
	var road_samples := 0
	var bad_snow := false
	var arrived := false
	for i in 7200:
		await physics_frame
		first._physics_process(1.0 / 60.0)
		var at := first.global_position
		if at.x > -66.0 and at.x < -54.0:
			road_samples += 1
			if road_samples == 1:
				check(first.on_crossing(), "D road movement keeps its actual crossing permission")
		if at.x > -70.6 and at.x < -50.7 and absf(at.z + 40.0) < 0.5:
			for bank in Layout.snow_banks():
				var rect := Rect2(bank[0] - bank[1] * 0.5, bank[1])
				bad_snow = bad_snow or rect.grow(Resident.BODY_RADIUS).has_point(Vector2(at.x, at.z))
		if not first.visits.is_empty() and first.visits[-1][1] == &"shop24":
			arrived = true
			break
	check(arrived and road_samples > 10 and not bad_snow, "the resident physically crosses D through both snow-bank openings and enters the real shop")

func _broken_services() -> void:
	if not check(life.has_method("environment_support"), "BREAK-03 environment support API is integrated"):
		return
	var breaks: Node = get_first_node_in_group(&"breakables_root")
	for service in [&"press", &"shaw"]:
		life.reset()
		_at(buyer, service)
		_at(first, StringName("%s_q1" % service))
		_at(second, StringName("%s_q2" % service))
		var supports: Array = life.environment_support(service)
		if not check(not supports.is_empty(), "%s uses its real breakable service building" % service): continue
		var support = breaks.env_at_index(supports[0])
		support.smash(&"punch", Vector3.RIGHT)
		check(not life.anchor_intact(service), "%s becomes unavailable after the real kiosk is smashed" % service)
		for resident in [buyer, first, second]: resident._tick_activity(1.0 / 60.0)
		for id in [service, StringName("%s_q1" % service), StringName("%s_q2" % service)]:
			check(life.reserved.get(id, []).is_empty(), "%s releases all service/queue reservations after destruction" % id)
		check(life.choose(second, service, second.home, second.rng) == &"", "the destroyed %s cannot serve a new or waiting customer" % service)
		support.reset()
		check(life.anchor_intact(service), "%s can be used again after actual restoration" % service)

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok: failures.append(message)
	print("PASS: " if ok else "FAIL: ", message)
	return ok

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _finish() -> void:
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	main.queue_free()
	await _frames(6)
	OS.delay_msec(100)
	await process_frame
	print("ARENA03_CITY_LIFE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
