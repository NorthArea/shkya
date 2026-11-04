extends SceneTree
## Independent DRIVER-01 composition oracle: an actual Lada slide contact while the explicit
## driver is active must yield physical displacement/spin, damp, and resume the same mission.
## Expected results come from DRIVER-01 and C8, before inspection of DriverAI/TrafficCar.
## Only initial fixture placement is written; no pose/velocity/reset changes after contact.
const Layout = preload("res://game/world/layout.gd")
const Traffic = preload("res://game/vehicles/traffic_car.gd")
const Materials = preload("res://game/world/materials.gd")
const EnvDress = preload("res://game/world/environment_dress.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const DT := 1.0 / 60.0
const EVIDENCE := "res://builds/checks/DRIVER-01/impact-composition/"
var main: Node
var world: DemoWorld
var lane: PathVehicle.LanePath
var failures: Array[String] = []
var checks := 0
var episodes: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = EVIDENCE + "achievements-%d.json" % OS.get_process_id()
	root.add_child(main)
	await process_frame
	main.start_game()
	await frames(8)
	world = main.world
	for sensor in get_nodes_in_group(&"detection_sensors"): sensor.enabled = false
	var traffic: Node = world.get_node("LevelGeometry/Traffic")
	for body in traffic.vehicles:
		body.set_physics_process(false)
		body.collision_layer = 0
	lane = PathVehicle.LanePath.build(Layout.CAR_RING, Layout.RING_LANE, PathVehicle.CAR_TURN_RADIUS)
	world.enter_car()
	await frames(2)
	for kind: StringName in [&"zhiguli", &"gazelle"]:
		for mode: StringName in [&"race", &"pursue", &"evade"]:
			await episode(kind, mode)
	var report := {"checks": checks, "failures": failures, "episodes": episodes,
		"renderer": RenderingServer.get_current_rendering_method(), "audio_driver": AudioServer.get_driver_name(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second}
	var file := FileAccess.open(EVIDENCE + "result.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		check(false, "composition evidence file is writable")
	await finish()

func episode(kind: StringName, mode: StringName) -> void:
	var label := "%s/%s" % [kind, mode]
	Input.action_release(&"car_gas")
	Input.action_release(&"car_brake")
	Input.action_release(&"handbrake")
	# The previous episode is over and its NPC was freed. Stage the striker away before
	# constructing this independent initial fixture, so the warm-up has a clear road.
	world.car.reset_to(Vector3(-80, 0, 32), 0)
	await frames(2)
	var car: TrafficCar = Traffic.new()
	car.kind = kind
	world.add_child(car)
	car.setup(lane, lane.offset_of(Vector3(73, 0, -30)))
	# A mission's observed target is independent of the striker. It has no physics override,
	# impact callback or scripted movement; the actual Lada and TrafficCar own every contact.
	var mission_target := Node3D.new()
	world.add_child(mission_target)
	mission_target.global_position = lane.position_at(car.s + (48.0 if mode == &"pursue" else -20.0))
	var checkpoints: Array[Vector3] = [lane.position_at(car.s + 55), lane.position_at(car.s + 90)]
	var accepted := car.start_driving(mode, null, checkpoints) if mode == &"race" else car.start_driving(mode, mission_target)
	check(accepted, label + ": explicit mode is accepted before contact")
	await frames(45)
	check(car.driver_ai.mode == mode and car.distance_travelled > 0.1, label + ": production driver is already moving in its selected mode")
	# Initial impact fixture, on the existing road. The offset gives a real eccentric rear contact.
	world.car.reset_to(car.global_position + car.global_basis.z * (car.size.z * 0.5 + Lada.SIZE.z * 0.5 + 0.8) + car.global_basis.x * 0.55, car.global_rotation.y)
	await frames(2)
	world.car.velocity = -world.car.global_basis.z * 20.0
	Input.action_press(&"car_gas")
	var impact_started := false
	var actual_contact := false
	var same_mode := true
	var settled := false
	var resumed := false
	var saw_first := false
	var saw_second := false
	var impact_origin := car.global_position
	var impact_heading := car.global_rotation.y
	var settled_position := car.global_position
	var first_impulse := 0.0
	var peak_impulse := 0.0
	var min_after_peak := INF
	var impact_displacement := 0.0
	var impact_turn := 0.0
	var max_step := 0.0
	var max_turn_step := 0.0
	var resumed_distance := 0.0
	var goal_progress := 0.0
	var last := car.global_position
	var last_heading := car.global_rotation.y
	var overlaps := 0
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = car.size - Vector3(0.1, 0.1, 0.1)
	query.shape = box
	query.collision_mask = 1
	query.exclude = [car.get_rid()]
	var trace: Array[Dictionary] = []
	for frame in 1200:
		await frames(1)
		for index in world.car.get_slide_collision_count():
			if world.car.get_slide_collision(index).get_collider() == car:
				actual_contact = true
		query.transform = car.global_transform.translated_local(Vector3.UP * car.size.y * 0.5)
		if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): overlaps += 1
		var step := car.global_position.distance_to(last)
		max_step = maxf(max_step, step)
		max_turn_step = maxf(max_turn_step, absf(angle_difference(last_heading, car.global_rotation.y)))
		if car.global_position.distance_to(checkpoints[0]) < 8: saw_first = true
		if saw_first and car.global_position.distance_to(checkpoints[1]) < 8: saw_second = true
		var completed := mode == &"race" and saw_first and saw_second and car.driver_ai.state == &"arrived"
		same_mode = same_mode and (car.driver_ai.mode == mode or completed)
		if car.impact_active:
			if not impact_started:
				impact_started = true
				impact_origin = last
				impact_heading = last_heading
				first_impulse = car.impact_velocity.length()
				# Braking is an ordinary driver input; no participant is moved or frozen after impact.
				Input.action_release(&"car_gas")
				Input.action_press(&"handbrake")
			var impulse := car.impact_velocity.length()
			if impulse > peak_impulse:
				peak_impulse = impulse
				min_after_peak = impulse
			else:
				min_after_peak = minf(min_after_peak, impulse)
			impact_displacement = maxf(impact_displacement, car.global_position.distance_to(impact_origin))
			impact_turn = maxf(impact_turn, absf(angle_difference(impact_heading, car.global_rotation.y)))
		elif impact_started:
			if not settled:
				settled = true
				settled_position = car.global_position
			else:
				resumed_distance += step
				goal_progress = car.global_position.distance_to(mission_target.global_position) - settled_position.distance_to(mission_target.global_position) if mode == &"evade" else settled_position.distance_to(checkpoints[0] if mode == &"race" else mission_target.global_position) - car.global_position.distance_to(checkpoints[0] if mode == &"race" else mission_target.global_position)
				resumed = resumed or (resumed_distance > 3.0 and goal_progress > 2.0 and car.speed > 0.5)
		if frame % 15 == 0 or (car.impact_active and not settled):
			trace.append({"frame": frame, "position": [car.global_position.x, car.global_position.y, car.global_position.z], "yaw": car.global_rotation.y, "speed": car.speed, "impact": car.impact_active, "impulse_speed": car.impact_velocity.length(), "mode": car.driver_ai.mode, "state": car.driver_ai.state, "reason": car.driver_ai.reason, "obstacle_gap": car.obstacle_gap if is_finite(car.obstacle_gap) else -1.0, "blocked_by": str(car.blocked_by.get_path()) if is_instance_valid(car.blocked_by) and car.blocked_by is Node else str(car.blocked_by)})
		last = car.global_position
		last_heading = car.global_rotation.y
		if settled and resumed and frame > 240: break
		if not impact_started and frame >= 120: break
	check(actual_contact and impact_started and first_impulse > 0.1, label + ": actual Lada slide contact transfers a nonzero physical impulse")
	check(impact_displacement > 0.03 and impact_turn > 0.001, label + ": eccentric impact physically displaces and rotates the active driver")
	check(settled and min_after_peak < peak_impulse * 0.5, label + ": impulse damps and physical impact relinquishes control in finite time")
	check(same_mode, label + ": selected mission mode survives the collision")
	check(resumed, label + ": without repositioning, the settled driver resumes mission progress")
	check(max_step <= 30.0 * DT + 0.01 and max_turn_step < PI / 12.0, label + ": impact and handoff preserve continuous body motion")
	check(overlaps == 0, label + ": displaced and recovering body never overlaps solid road geometry")
	var result := {"solid_overlap_frames": overlaps, "kind": kind, "mode": mode, "actual_slide_contact": actual_contact, "impact_started": impact_started, "first_impulse": first_impulse, "peak_impulse": peak_impulse, "min_after_peak": min_after_peak if is_finite(min_after_peak) else -1.0, "impact_displacement": impact_displacement, "impact_yaw": impact_turn, "settled": settled, "resumed": resumed, "mission_mode_preserved": same_mode, "resumed_distance": resumed_distance, "goal_progress": goal_progress, "max_step": max_step, "max_yaw_step": max_turn_step, "final_state": car.driver_ai.state, "trace": trace}
	episodes.append(result)
	print("EPISODE " + JSON.stringify(result).left(1800))
	car.queue_free()
	mission_target.queue_free()
	await frames(2)

func frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool, text: String) -> bool:
	checks += 1
	print(("PASS " if ok else "FAIL ") + text)
	if not ok: failures.append(text)
	return ok

func finish() -> void:
	Input.action_release(&"car_gas")
	Input.action_release(&"handbrake")
	for type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player in main.find_children("*", type, true, false): player.stop()
	main.queue_free()
	await frames(3)
	main = null
	world = null
	lane = null
	Materials.clear_cache()
	EnvDress.clear_cache()
	VehicleMesh.cache().clear()
	OS.delay_msec(100)
	await process_frame
	print("DRIVER_IMPACT_COMPOSITION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
