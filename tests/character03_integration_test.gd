extends SceneTree
## Independent CHARACTER-03 acceptance on actual Main/Residents/Life.
## Fixtures reposition existing actors on Layout-derived ground, never replace
## the predictor, snapshot manager, route authority or canonical can_step.
## Headless geometry/state evidence; renderer, naturalness and FPS NOT_RUN.

const Layout = preload("res://game/world/layout.gd")
const ResidentScript = preload("res://game/npc/resident.gd")
const LadaScript = preload("res://game/vehicles/lada.gd")
const Motion = preload("res://game/npc/pedestrian_motion.gd")
const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const DT := 1.0 / 60.0
const SEPARATION := 0.69

class CompletedPhysics:
	extends Node
	signal completed
	func _physics_process(_delta: float) -> void:
		completed.emit()

class CarTrajectory:
	extends Node
	var car: CharacterBody3D
	var travel := Vector3.ZERO
	func _physics_process(delta: float) -> void:
		if is_instance_valid(car):
			car.velocity = travel
			car.global_position += travel * delta

var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var manager: Node
var observer: CompletedPhysics
var car_trajectory: CarTrajectory
var patch := Vector3.INF
var far := Vector3.ZERO
var active: Array = []
var audit := {}
var grounds: Array[Rect2] = []
var roads: Array[Rect2] = []
var solids: Array[Rect2] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("CHARACTER03_INTEGRATION: " + message)
	return ok

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		printerr("CHARACTER03_INTEGRATION requires --headless")
		quit(2)
		return
	create_timer(600.0, true, false, true).timeout.connect(func(): quit(2))
	observer = CompletedPhysics.new()
	observer.process_physics_priority = 1000
	root.add_child(observer)
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/CHARACTER-03/independent-%d.json" % OS.get_process_id()
	root.add_child(main)
	main.start_game()
	await _frames(6)
	world = main.world
	manager = world.get_node("LevelGeometry/Residents")
	check(manager.residents.size() == Layout.RESIDENT_ROUTES.size() and manager.residents.size() == 64,
		"real Main retains its canonical 64 residents and real Life owner")
	check(manager.life != null and manager.trolley != null, "actual Residents binds Life and the original trolley")
	var capsules := true
	for resident: Resident in manager.residents:
		var collider := resident.body.get_child(0) as CollisionShape3D
		capsules = capsules and collider != null and collider.shape is CapsuleShape3D
		if collider != null and collider.shape is CapsuleShape3D:
			var capsule := collider.shape as CapsuleShape3D
			capsules = capsules and is_equal_approx(capsule.radius, ResidentScript.BODY_RADIUS) \
				and is_equal_approx(capsule.height, ResidentScript.BODY_HEIGHT) \
				and collider.position.is_equal_approx(Vector3.UP * ResidentScript.BODY_HEIGHT * 0.5)
	check(capsules, "actual resident collision capsules retain canonical radius, height and grounded root offset")
	_freeze(world)
	manager.set_physics_process(true)
	car_trajectory = CarTrajectory.new()
	car_trajectory.process_physics_priority = -1000
	car_trajectory.car = world.car
	root.add_child(car_trajectory)
	_cache_geometry()
	patch = _find_patch(manager.residents[0])
	if not check(patch != Vector3.INF, "Layout contains a verified open pedestrian fixture patch"):
		await _finish()
		return
	for route: Array in Layout.RESIDENT_ROUTES:
		for point: Vector3 in route:
			if point.distance_to(patch) > far.distance_to(patch): far = point
	print("CHARACTER03_FIXTURE ", JSON.stringify({"patch": str(patch), "far": str(far), "test_sha256": FileAccess.get_sha256(get_script().resource_path)}))
	await _peer_passage(false)
	await _peer_passage(true)
	await _player_wait()
	await _car_prediction()
	await _dynamic_side_block()
	await _pair_footprints()
	await _sparse_lod()
	await _paired_sparse_lod()
	await _reservation_and_activity()
	await _passenger_after_yield()
	await _certified_crossing()
	await _small_place_presentation()
	await _paired_small_place_presentation()
	await _knock_and_reset()
	await _finish()

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): _freeze(child)

func _isolate() -> void:
	active.clear()
	car_trajectory.travel = Vector3.ZERO
	world.car.velocity = Vector3.ZERO
	world.car.reset_to(far, 0.0)
	world.player.place(far, 0.0)
	world.player.hide()
	world.player.set_physics_process(false)
	manager.life.reset()
	for resident in manager.residents:
		resident.set_physics_process(false)
		resident._act_stop()
		resident._hide(&"qa_inactive")
		resident._look().set_physics_process(false)
	audit = {"ground": true, "solids": true, "bounded": true, "bodies": true, "previous": {}}

func _activate(index: int, start: Vector3, goal: Vector3) -> Resident:
	var resident: Resident = manager.residents[index]
	resident.errand = false
	resident.rider = false
	resident.smoke_point = -1
	resident.wait_point = -1
	resident._act_stop()
	resident.setup(index, [start, goal], [1], 0)
	resident.start_leg = [start, goal]
	resident.route_flags = [&""]
	resident.speed = 1.2
	resident.pause_seconds = 1000.0
	resident.reset_to_start()
	resident._met = true
	resident._locomotion_position = Vector3.INF
	resident._lod_acc = 0.0
	resident._lod_n = 0
	resident.set_physics_process(true)
	resident._look().set_physics_process(true)
	active.append(resident)
	return resident

func _find_patch(probe: Resident) -> Vector3:
	var candidates: Array[Vector3] = []
	for route: Array in Layout.RESIDENT_ROUTES:
		for i in range(route.size() - 1): candidates.append((route[i] + route[i + 1]) * 0.5)
	for area: Rect2 in Layout.LIFE_GROUNDS:
		for x in [0.25, 0.5, 0.75]:
			for z in [0.25, 0.5, 0.75]:
				candidates.append(Vector3(area.position.x + area.size.x * x, 0, area.position.y + area.size.y * z))
	for center: Vector3 in candidates:
		var valid := _permitted_ground(center) and _solid_clear(center)
		if not valid: continue
		for x in [-3.5, -1.75, 0.0, 1.75, 3.5]:
			for z in [-3.5, -1.75, 0.0, 1.75, 3.5]:
				var point := center + Vector3(x, 0, z)
				if not _permitted_ground(point) or not _solid_clear(point) or not probe._motion_step_clear(center, point):
					valid = false
					break
			if not valid: break
		if valid: return center
	return Vector3.INF

func _peer_passage(crossing: bool) -> void:
	_isolate()
	var a := _activate(0, patch + Vector3.LEFT * 2.5, patch + Vector3.RIGHT * 2.5)
	var b := _activate(1, patch + (Vector3.FORWARD if crossing else Vector3.RIGHT) * 2.5,
		patch + (Vector3.BACK if crossing else Vector3.LEFT) * 2.5)
	var routes := [a.route.duplicate(), b.route.duplicate()]
	var minimum := INF
	var yielding := false
	for frame in 720:
		await _frames(1)
		minimum = minf(minimum, _planar(a.global_position - b.global_position).length())
		yielding = yielding or a.motion.mode in [&"yield", &"dodge", &"stopped"] or b.motion.mode in [&"yield", &"dodge", &"stopped"]
		_audit_active()
		if a.state == &"pause" and b.state == &"pause": break
	var label := "crossing" if crossing else "opposed"
	check(yielding, label + " actual peers reach the local contact/yield boundary")
	check(minimum >= SEPARATION, label + " actual capsule centers remain physically separated: %.4f" % minimum)
	check(a.global_position.distance_to(routes[0][1]) < 0.06 and b.global_position.distance_to(routes[1][1]) < 0.06,
		label + " both stable priorities arrive in finite time")
	check(a.route == routes[0] and b.route == routes[1], label + " avoidance leaves canonical routes unchanged")
	_report_audit(label)

func _player_wait() -> void:
	_isolate()
	var resident := _activate(0, patch + Vector3.LEFT * 2.5, patch + Vector3.RIGHT * 2.5)
	world.player.show()
	world.player.place(patch, 0.0)
	world.player.set_physics_process(false)
	var minimum := INF
	for frame in 180:
		await _frames(1)
		minimum = minf(minimum, _planar(resident.global_position - world.player.global_position).length())
		_audit_active()
	var stopped := resident.global_position
	await _frames(60)
	check(resident.global_position.distance_to(stopped) < 0.01 and minimum >= SEPARATION,
		"stationary real player causes a safe sustained wait")
	var found_player := false
	for hazard: Dictionary in manager.motion_obstacles(resident, Motion.HORIZON):
		found_player = found_player or hazard.kind == &"player"
	check(found_player, "the actual manager snapshot includes the blocking real player")
	world.player.hide()
	world.player.place(far, 0.0)
	for frame in 480:
		await _frames(1)
		_audit_active()
		if resident.state == &"pause": break
	check(resident.global_position.distance_to(patch + Vector3.RIGHT * 2.5) < 0.06,
		"releasing the real player resumes the same route without a timer deadlock")
	_report_audit("player wait/release")

func _car_prediction() -> void:
	for approaching: bool in [true, false]:
		_isolate()
		var resident := _activate(0, patch + Vector3.LEFT * 2.5, patch + Vector3.RIGHT * 2.5)
		world.car.reset_to(resident.global_position + Vector3.RIGHT * 6.5, -PI * 0.5)
		car_trajectory.travel = Vector3.LEFT * 5.0 if approaching else Vector3.RIGHT * 5.0
		var reacted := false
		var minimum := INF
		for frame in 18:
			await _frames(1)
			minimum = minf(minimum, _car_clearance(resident.global_position))
			reacted = reacted or resident.motion.mode in [&"stopped", &"yield", &"dodge"]
			_audit_active()
		check(minimum > 0.2, "predictive car witness stays outside actual pre-contact geometry")
		check(reacted if approaching else not reacted, "approaching actual Lada is anticipated" if approaching else "receding actual Lada creates no spurious yield")
		check(resident.knocks == 0 and resident.lada_bumps == 0, "pre-contact prediction does not manufacture KNOCK or post-contact relocation")
		_report_audit("approaching car" if approaching else "receding car")
	# Counterpart of the rounded-corner defect on the actual Lada and manager.
	_isolate()
	var resident := _activate(0, patch, patch + Vector3.RIGHT * 3.0)
	var half: Vector3 = LadaScript.SIZE * 0.5
	world.car.reset_to(patch - Vector3(half.x + 0.35, 0, half.z + 0.35), 0.0)
	car_trajectory.travel = Vector3.FORWARD
	await _frames(2)
	var before := resident.global_position
	await _frames(12)
	check(_car_clearance(resident.global_position) > 0.0 and resident.global_position.x > before.x + 0.02,
		"a safely receding real Lada corner permits physical pedestrian progress")
	check(resident.turnarounds == 0 and resident.lada_bumps == 0 and resident.motion.mode == &"following",
		"rounded-corner separation does not trigger legacy reverse/relocate or predictor yield")
	# Existing parked-car reverse policy remains safe and releases when removed.
	_isolate()
	resident = _activate(0, patch + Vector3.LEFT * 2.5, patch + Vector3.RIGHT * 2.5)
	world.car.reset_to(patch + Vector3.RIGHT * 1.0, -PI * 0.5)
	await _frames(120)
	check(_car_clearance(resident.global_position) >= -0.01 and resident.knocks == 0,
		"parked real Lada retains the safe original wait/reverse policy")
	world.car.reset_to(far, 0.0)
	for frame in 720:
		await _frames(1)
		if resident.state == &"pause": break
	check(resident.state == &"pause" and resident.global_position.distance_to(resident.route[1]) < 0.06,
		"removing a parked car eventually restores canonical arrival")

func _dynamic_side_block() -> void:
	_isolate()
	var a := _activate(0, patch + Vector3.LEFT * 2.5, patch + Vector3.RIGHT * 2.5)
	var blocker := _activate(1, a.global_position + Vector3.RIGHT * 1.6, patch + Vector3.RIGHT * 2.5)
	blocker.set_physics_process(false)
	var began := false
	for frame in 120:
		await _frames(1)
		if absf(a.global_position.z - patch.z) > 0.0001 and a.motion.mode == &"dodge":
			began = true
			break
	if not check(began, "dynamic side-block fixture reaches an actual physical dodge"):
		return
	blocker._hide(&"qa_inactive")
	var side := signf(a.global_position.z - patch.z)
	world.player.show()
	world.player.place(Vector3(a.global_position.x, 0, patch.z + side * 0.86), 0.0)
	world.player.set_physics_process(false)
	# The existing introduction stare is separate from replanning an active dodge.
	# Far-away player ticks clear this flag, so establish the stated already-met case
	# only after the real player has entered the fixture.
	a._met = true
	var start_x := a.global_position.x
	var minimum := INF
	for frame in 120:
		await _frames(1)
		minimum = minf(minimum, _planar(a.global_position - world.player.global_position).length())
		_audit_active()
	print("CHARACTER03_DYNAMIC_SIDE ", JSON.stringify({"state": str(a.state), "mode": str(a.motion.mode),
		"progress": a.global_position.x - start_x, "minimum": minimum, "met": a._met,
		"player_distance": a.global_position.distance_to(world.player.global_position)}))
	check(minimum >= SEPARATION, "new actual body blocking the chosen side never gets penetrated")
	check(a.global_position.x > start_x + 0.6 and a.motion.mode in [&"following", &"return"],
		"expired blocked side commitment releases and makes progress on the now-clear canonical route")
	_report_audit("dynamic blocked side")

func _pair_footprints() -> void:
	_isolate()
	var leader := _activate(6, patch + Vector3.LEFT * 2.5, patch + Vector3.RIGHT * 2.5)
	var follower: Resident = manager.residents[8]
	follower.errand = false
	follower._show()
	follower.state = &"walk"
	follower.follow_offset = Vector3.BACK * manager.FOLLOW_GAP
	follower.place(leader.global_position + follower.follow_offset)
	follower._mirror(leader)
	follower.set_physics_process(true)
	follower._look().set_physics_process(true)
	active.append(follower)
	await _frames(3)
	var self_hazard := false
	for obstacle: Dictionary in manager.motion_obstacles(leader, Motion.HORIZON):
		self_hazard = self_hazard or int(obstacle.unit_id) == leader.motion_unit_id()
	check(not self_hazard and leader.motion_footprints().size() == 2,
		"real pair contributes two footprints and ignores its own manager unit")
	world.player.show()
	world.player.place(follower.global_position + Vector3.RIGHT * 1.4, 0.0)
	world.player.set_physics_process(false)
	leader._met = true
	follower._met = true
	var minimum := INF
	for frame in 120:
		await _frames(1)
		minimum = minf(minimum, _planar(follower.global_position - world.player.global_position).length())
		_audit_active()
	check(minimum >= SEPARATION and leader.global_position.x < world.player.global_position.x - 0.5,
		"a hazard on the real follower footprint stops the complete pair safely")
	world.player.hide()
	world.player.place(far, 0.0)
	for frame in 600:
		await _frames(1)
		_audit_active()
		if leader.state == &"pause": break
	check(leader.state == &"pause" and follower.leader == leader and leader.follower == follower,
		"pair ownership and canonical progress survive the wait")
	check(_planar(follower.global_position - leader.global_position).distance_to(follower.follow_offset) < 0.01,
		"follower body retains its original paired root offset")
	_report_audit("real pair")

func _sparse_lod() -> void:
	_isolate()
	var resident := _activate(0, patch + Vector3.LEFT * 2.5, patch + Vector3.RIGHT * 2.5)
	resident.errand = true
	resident.spot_id = &""
	var witness := _activate(1, patch + Vector3.BACK * 2.8, patch + Vector3.BACK * 3.0)
	witness.set_physics_process(false)
	var rig: Node3D = world.get_node("CameraRig")
	var rig_process_mode := rig.process_mode
	# SpringArm3D has native internal physics in addition to script callbacks.
	# Suspend the real controller subtree while positioning its actual camera.
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := world.get_viewport().get_camera_3d()
	var camera_transform := camera.global_transform
	camera.global_position = far + Vector3.UP * 10.0
	camera.look_at(camera.global_position + (far - patch).normalized(), Vector3.UP)
	camera.reset_physics_interpolation()
	var initial_gate := _lod_gate(resident, camera)
	print("CHARACTER03_LOD_GATE_INITIAL ", JSON.stringify(initial_gate))
	var gate_valid: bool = initial_gate.ready
	var skipped := 0
	var bad_speed := 0
	var snapshot_samples := 0
	var bad_snapshot_speed := 0
	var sparse_diagnostics: Array[Dictionary] = []
	var gait_min := INF
	var gait_max := 0.0
	var previous := resident.global_position
	for frame in 120:
		await _frames(1)
		var gate := _lod_gate(resident, camera)
		gate_valid = gate_valid and gate.ready
		if frame < 3:
			gate["frame"] = frame
			gate["lod_n"] = resident._lod_n
			gate["locomotion_delta"] = resident._locomotion_delta
			print("CHARACTER03_LOD_GATE_TICK ", JSON.stringify(gate))
		var look := resident._look()
		var gait: RefCounted = look.uniform_visual.gait
		if frame > 30:
			gait_min = minf(gait_min, gait.speed)
			gait_max = maxf(gait_max, gait.speed)
		if frame > 30 and resident.global_position == previous:
			skipped += 1
			if gait.speed < resident.speed * 0.5 or gait.speed > resident.speed * 1.5:
				bad_speed += 1
				if sparse_diagnostics.size() < 8:
					sparse_diagnostics.append({"frame": frame, "gait_speed": gait.speed, "gait_mode": str(gait.mode),
						"published_velocity": str(look._velocity), "published_mode": str(look._pose_mode),
						"controlled": look._controlled, "state": str(resident.state), "hidden": resident.hidden,
						"look_visible": look.is_visible_in_tree(), "look_physics": look.is_physics_processing(),
						"actor_position": str(resident.global_position), "locomotion_delta": resident._locomotion_delta,
						"lod_n": resident._lod_n, "camera_distance": camera.global_position.distance_to(resident.global_position),
						"in_frustum": camera.is_position_in_frustum(resident.global_position + Vector3.UP)})
		if frame > 30:
			for record: Dictionary in manager.motion_obstacles(witness, Motion.HORIZON):
				if record.kind != &"peer" or int(record.id) != resident.index: continue
				snapshot_samples += 1
				var measured := Vector3(record.velocity).length()
				if measured < resident.speed * 0.5 or measured > resident.speed * 1.5: bad_snapshot_speed += 1
		previous = resident.global_position
	print("CHARACTER03_SPARSE ", JSON.stringify({"skipped": skipped, "bad_gait_speed": bad_speed,
		"gait_min": gait_min, "gait_max": gait_max, "snapshot_samples": snapshot_samples,
		"bad_snapshot_speed": bad_snapshot_speed, "actor_state": str(resident.state),
		"final_published_velocity": str(resident._look()._velocity), "bad_samples": sparse_diagnostics}))
	check(gate_valid, "actual Life camera, offscreen distance and both hazard distances enable sparse LOD throughout the witness")
	check(skipped > 40 and bad_speed == 0, "actual sparse Resident retains average root velocity without zero/fourfold gait pulses")
	check(snapshot_samples == 89 and bad_snapshot_speed == 0,
		"actual manager snapshots retain sparse peer average velocity on update and skipped physics frames")
	resident.state = &"pause"
	resident._wait = 1000.0
	await _frames(60)
	check(resident._look().uniform_visual.gait.speed < 0.02 and resident.motion.velocity.length() < 0.001,
		"a sparse Resident stop clears steering and settles real gait")
	camera.global_transform = camera_transform
	camera.reset_physics_interpolation()
	rig.process_mode = rig_process_mode

func _paired_sparse_lod() -> void:
	_isolate()
	var leader := _activate(6, patch + Vector3.LEFT * 1.8, patch + Vector3.RIGHT * 2.5)
	leader.errand = true
	leader.spot_id = &""
	leader._trail_seed(Vector3.RIGHT)
	var follower: Resident = manager.residents[8]
	follower.errand = true
	follower._show()
	follower._mirror(leader)
	follower.place(follower.global_position)
	follower.set_physics_process(true)
	follower._look().set_physics_process(true)
	active.append(follower)
	await _frames(60)
	check(follower.leader == leader and leader.follower == follower and follower.state == &"walk" \
		and absf(Vector3(follower._look()._velocity).length() - leader.speed) < 0.15,
		"paired LOD witness starts with real trail ownership and warmed ordinary follower speed")
	var rig: Node3D = world.get_node("CameraRig")
	var rig_process_mode := rig.process_mode
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := world.get_viewport().get_camera_3d()
	var camera_transform := camera.global_transform
	camera.global_position = far + Vector3.UP * 10.0
	camera.look_at(camera.global_position + (far - patch).normalized(), Vector3.UP)
	camera.reset_physics_interpolation()
	var gate_valid := true
	var skipped := 0
	var updated := 0
	var bad_skip_velocity := 0
	var bad_update_velocity := 0
	var bad_gait := 0
	var minimum_velocity := INF
	var maximum_velocity := 0.0
	var previous := leader.global_position
	for frame in 120:
		await _frames(1)
		var gate := _lod_gate(leader, camera)
		gate_valid = gate_valid and gate.ready and follower.life.camera == camera
		if frame > 30:
			var measured := Vector3(follower._look()._velocity).length()
			var gait_speed: float = follower._look().uniform_visual.gait.speed
			minimum_velocity = minf(minimum_velocity, measured)
			maximum_velocity = maxf(maximum_velocity, measured)
			var wrong_velocity := measured < leader.speed * 0.5 or measured > leader.speed * 1.5
			if leader.global_position == previous:
				skipped += 1
				if wrong_velocity: bad_skip_velocity += 1
			else:
				updated += 1
				if wrong_velocity: bad_update_velocity += 1
			if gait_speed < leader.speed * 0.5 or gait_speed > leader.speed * 1.5: bad_gait += 1
		previous = leader.global_position
	print("CHARACTER03_PAIR_SPARSE ", JSON.stringify({"skipped": skipped, "updated": updated,
		"bad_skip_velocity": bad_skip_velocity, "bad_update_velocity": bad_update_velocity,
		"bad_gait": bad_gait, "min_velocity": minimum_velocity, "max_velocity": maximum_velocity,
		"leader_clock": leader.clock, "follower_clock": follower.clock,
		"follower_sample_clock": follower.motion_sample_clock(), "gate_valid": gate_valid}))
	check(gate_valid and skipped > 40 and updated > 10 and skipped + updated == 89,
		"real paired leader reaches sparse LOD with valid camera/hazard gates and both skip/update samples")
	check(bad_skip_velocity == 0 and bad_update_velocity == 0,
		"real follower retains average published velocity during leader skips and avoids fourfold update pulses")
	check(bad_gait == 0, "real paired sparse follower retains ordinary gait speed on every observed physics frame")
	leader.state = &"pause"
	leader._wait = 1000.0
	await _frames(60)
	check(follower._look().uniform_visual.gait.speed < 0.02 and Vector3(follower._look()._velocity).length() < 0.02,
		"a real sparse paired stop clears retained follower velocity and gait")
	camera.global_transform = camera_transform
	camera.reset_physics_interpolation()
	rig.process_mode = rig_process_mode

func _lod_gate(resident: Resident, camera: Camera3D) -> Dictionary:
	var life_camera: Camera3D = resident.life.camera if resident.life != null else null
	var distance := life_camera.global_position.distance_to(resident.global_position) if is_instance_valid(life_camera) else -1.0
	var in_frustum := life_camera.is_position_in_frustum(resident.global_position + Vector3.UP) if is_instance_valid(life_camera) else true
	var player_distance := _planar(resident.player.global_position - resident.global_position).length() if is_instance_valid(resident.player) else INF
	var car_distance := _planar(resident.lada.global_position - resident.global_position).length() if is_instance_valid(resident.lada) else INF
	var same_camera := life_camera == camera and camera == world.get_viewport().get_camera_3d()
	var ready := resident.errand and resident.leader == null and resident.state != &"knocked" \
		and same_camera and distance > ResidentScript.LOD_DISTANCE and not in_frustum \
		and player_distance >= ResidentScript.LOD_NEAR and car_distance >= ResidentScript.LOD_NEAR
	return {"ready": ready, "errand": resident.errand, "leader_null": resident.leader == null,
		"state": str(resident.state), "life_present": resident.life != null, "same_camera": same_camera,
		"camera_position": str(camera.global_position), "life_camera_distance": distance,
		"life_camera_frustum": in_frustum, "viewport_camera_distance": camera.global_position.distance_to(resident.global_position),
		"player_distance": player_distance, "car_distance": car_distance}

func _reservation_and_activity() -> void:
	_isolate()
	var resident: Resident = manager.residents[0]
	var chosen: StringName = &""
	var best := INF
	var start := Vector3.INF
	for origin: Vector3 in manager.life.nodes.values():
		for id: StringName in manager.life.spots:
			var spot: Dictionary = manager.life.spots[id]
			if spot.kind not in [&"look", &"chat"] or not manager.life.anchor_intact(id): continue
			var path: Dictionary = manager.life.path(origin, id)
			var points: Array = path.points
			if points.size() < 2 or points[0].distance_to(points[1]) < 2.4: continue
			if not path.flags.is_empty() and path.flags[0] != &"": continue
			if not resident._motion_step_clear(points[0], points[1]): continue
			var cost := 0.0
			for i in range(points.size() - 1): cost += points[i].distance_to(points[i + 1])
			if cost < best:
				best = cost
				chosen = id
				start = origin
	if not check(chosen != &"", "canonical Life graph supplies an ordinary reserved activity leg"):
		return
	resident = _activate(0, start, start + Vector3.RIGHT)
	_park_car_away_from(start)
	resident.errand = true
	resident._from_spot = &""
	resident._go_to(chosen)
	var route: Array = resident.route.duplicate()
	var leg: Vector3 = route[1] - route[0]
	world.player.show()
	world.player.place(route[0] + leg.normalized() * 1.8, 0.0)
	world.player.set_physics_process(false)
	await _frames(120)
	var waiting_at := resident.global_position
	await _frames(30)
	check(resident.state == &"walk" and not resident._acting and resident.global_position.distance_to(waiting_at) < 0.01,
		"real player physically holds the reserved Life leg before activity arrival")
	check(resident.spot_id == chosen and manager.life.reserved.get(chosen, []).has(resident) and resident.route == route,
		"actual yield preserves Life reservation, selected activity and canonical route")
	world.player.hide()
	world.player.place(far, 0.0)
	var arrival_budget := ceili((best / resident.speed + 8.0) / DT)
	for frame in arrival_budget:
		await _frames(1)
		if resident._acting and resident.state == &"activity": break
	check(resident.spot_id == chosen and resident._acting and resident.state == &"activity" and manager.life.reserved.get(chosen, []).has(resident),
		"releasing the blocker reaches the original reserved activity with real Life ownership")
	await _frames(2)
	check(resident.motion.velocity.length() < 0.001 and resident._look().uniform_visual.gait.mode == &"activity",
		"actual activity cancels local steering and outranks ordinary gait")

func _passenger_after_yield() -> void:
	_isolate()
	var route: Array = Layout.RESIDENT_ROUTES[manager.RIDER]
	var resident := _activate(manager.RIDER, route[0], route[1])
	_park_car_away_from(route[0])
	resident.rider = true
	resident.wait_point = 1
	var midpoint: Vector3 = (route[0] + route[1]) * 0.5
	world.player.show()
	world.player.place(midpoint, 0.0)
	world.player.set_physics_process(false)
	await _frames(180)
	var waiting_at := resident.global_position
	await _frames(30)
	check(resident.state == &"walk" and resident.global_position.distance_to(waiting_at) < 0.01,
		"actual passenger is held on its walking leg by the real player")
	check(resident.rider and resident.trolley == manager.trolley and resident.route == route,
		"passenger role, trolley owner and canonical stop leg survive a real player wait")
	world.player.hide()
	world.player.place(far, 0.0)
	for frame in 720:
		await _frames(1)
		if resident.state == &"wait_trolley": break
	check(resident.state == &"wait_trolley", "released actual passenger reaches its canonical bus stop")
	var traffic: Node = world.get_node("LevelGeometry/Traffic")
	var trolley: Node = manager.trolley
	trolley.setup(traffic.path, traffic.path.offset_of(Layout.TROLLEY_STOPS[0]))
	trolley._set_doors(true)
	trolley.doors_opened.emit(0)
	check(resident.state == &"board", "actual trolley signal starts boarding through Residents")
	for frame in 720:
		await _frames(1)
		if resident.hidden: break
	await _frames(2)
	check(resident.hidden and resident.state == &"ride" and resident.body.collision_layer == 0,
		"boarding relinquishes the pedestrian body and local motion")
	check(manager.riders().count(resident) == 1 and trolley.people.riders.count(resident) == 1,
		"passenger exists exactly once in real Residents and cabin ownership")
	check(resident.motion.velocity.length() < 0.001, "hidden passenger has no residual local steering")

func _certified_crossing() -> void:
	_isolate()
	var edge: Array = []
	for candidate: Array in manager.life.edges:
		if candidate[2] != &"" and manager.life.nodes[candidate[0]].distance_to(manager.life.nodes[candidate[1]]) > 3.0:
			edge = candidate
			break
	if not check(not edge.is_empty(), "actual Life graph has a canonical gated crossing"):
		return
	var from: Vector3 = manager.life.nodes[edge[0]]
	var to: Vector3 = manager.life.nodes[edge[1]]
	var resident := _activate(0, from, to)
	_park_car_away_from(from)
	resident.errand = true
	resident.spot_id = &""
	resident.route_flags = [edge[2]]
	resident._cross_ok = 1 # fixture is already admitted; admission itself belongs to LIFE01.
	var peer := _activate(1, from + (to - from).normalized() * 1.9, to)
	peer.set_physics_process(false)
	await _frames(12)
	check(resident.global_position.distance_to(from) > 0.04 and resident.state == &"walk" and resident.motion.mode == &"following",
		"an already admitted canonical crossing does not add a new prediction wait")
	check(resident.global_position.distance_to(peer.global_position) >= SEPARATION,
		"short admitted-crossing witness remains pre-contact")

func _small_place_presentation() -> void:
	_isolate()
	var resident := _activate(0, patch + Vector3.LEFT * 2.5, patch + Vector3.RIGHT * 2.5)
	await _frames(60)
	var before := resident.global_position
	await _frames(1)
	var ordinary := (resident.global_position - before) / DT
	var look := resident._look()
	var ordinary_published: Vector3 = look._velocity
	var ordinary_gait: float = look.uniform_visual.gait.speed
	check(resident.state == &"walk" and ordinary.length() > 0.5 \
		and ordinary_published.distance_to(ordinary) < 0.005 \
		and ordinary_gait > 0.5 and ordinary_gait <= resident.speed * 1.5,
		"small-place witness starts with real ordinary motion and matching published velocity/gait")
	resident.place(resident.global_position + Vector3.RIGHT * 0.5)
	var placed_at := resident.global_position
	await _frames(1)
	var resolved := (resident.global_position - placed_at) / DT
	var published: Vector3 = look._velocity
	var gait_speed: float = look.uniform_visual.gait.speed
	print("CHARACTER03_SMALL_PLACE ", JSON.stringify({"ordinary_velocity": str(ordinary),
		"ordinary_published": str(ordinary_published), "ordinary_gait": ordinary_gait,
		"resolved_after_place": str(resolved), "published_after_place": str(published),
		"gait_after_place": gait_speed, "state": str(resident.state),
		"epoch": str(resident.motion_sample_epoch())}))
	check(published.length() <= resident.speed + 0.2 and published.distance_to(resolved) < 0.005,
		"a real 0.5m place excludes relocation from next published locomotion velocity")
	check(gait_speed <= resident.speed * 1.5,
		"a real 0.5m place causes no artificial high-speed gait pulse")

func _paired_small_place_presentation() -> void:
	_isolate()
	var leader := _activate(6, patch + Vector3.LEFT * 2.5, patch + Vector3.RIGHT * 2.5)
	var follower: Resident = manager.residents[8]
	follower.errand = false
	follower._show()
	follower.follow_offset = Vector3.BACK * manager.FOLLOW_GAP
	follower.place(leader.global_position + follower.follow_offset)
	follower._mirror(leader)
	follower.set_physics_process(true)
	follower._look().set_physics_process(true)
	active.append(follower)
	await _frames(60)
	var before := follower.global_position
	await _frames(1)
	var ordinary := (follower.global_position - before) / DT
	var look := follower._look()
	check(follower.leader == leader and leader.follower == follower and follower.state == &"walk" \
		and ordinary.length() > 0.5 and Vector3(look._velocity).distance_to(ordinary) < 0.005,
		"paired-place witness starts with real ownership and correctly measured follower walking")
	leader.place(leader.global_position + Vector3.RIGHT * 0.5)
	await _frames(1)
	var published: Vector3 = look._velocity
	var gait_speed: float = look.uniform_visual.gait.speed
	print("CHARACTER03_PAIR_SMALL_PLACE ", JSON.stringify({"ordinary_velocity": str(ordinary),
		"published_after_leader_place": str(published), "gait_after_leader_place": gait_speed,
		"leader_epoch": str(leader.motion_sample_epoch()), "follower_epoch": str(follower.motion_sample_epoch()),
		"offset": str(follower.global_position - leader.global_position)}))
	check(published.length() <= leader.speed + 0.2 and gait_speed <= leader.speed * 1.5,
		"real leader placement and mirroring create no follower velocity or gait pulse")
	await _frames(60)
	before = follower.global_position
	await _frames(1)
	var resumed := (follower.global_position - before) / DT
	check(resumed.length() > 0.5 and Vector3(look._velocity).distance_to(resumed) < 0.005 \
		and absf(float(look.uniform_visual.gait.speed) - resumed.length()) < 0.15,
		"the same real follower resumes ordinary measured locomotion after leader placement")
	check(_planar(follower.global_position - leader.global_position).distance_to(follower.follow_offset) < 0.01,
		"leader placement preserves the actual paired root offset and ownership")

func _knock_and_reset() -> void:
	_isolate()
	var resident := _activate(0, patch + Vector3.LEFT * 2.5, patch + Vector3.RIGHT * 2.5)
	await _frames(60)
	check(resident.motion.velocity.length() > 0.5, "cancellation witness starts with actual local motion")
	world.car.reset_to(resident.global_position, -PI * 0.5)
	car_trajectory.travel = Vector3.RIGHT * 8.0
	await _frames(2)
	car_trajectory.travel = Vector3.ZERO
	world.car.reset_to(far, 0.0)
	check(resident.state == &"knocked" and resident.knocks > 0 and resident.motion.velocity.length() < 0.001,
		"real car contact gives KNOCK authority priority over local steering")
	resident.reset_to_start()
	check(resident.state == &"walk" and resident.motion.velocity.length() < 0.001 and resident.global_position.distance_to(resident.route[0]) < 0.001,
		"real Resident reset restores its canonical root and clears reaction motion")
	# Stay inside the fresh stationary query radius while keeping real capsules clear.
	var witness_at := resident.global_position + Vector3.BACK * 1.5
	var witness := _activate(1, witness_at, witness_at + Vector3.BACK)
	witness.set_physics_process(false)
	var speeds: Array[float] = []
	var reset_samples: Array[Dictionary] = []
	for frame in 3:
		await _frames(1)
		var records: Array[Dictionary] = manager.motion_obstacles(witness, Motion.HORIZON)
		var found := false
		for record: Dictionary in records:
			if record.kind == &"peer" and int(record.id) == resident.index:
				speeds.append(Vector3(record.velocity).length())
				found = true
		reset_samples.append({"frame": frame, "found": found, "obstacles": records.size(),
			"distance": witness.global_position.distance_to(resident.global_position),
			"minimum_query_reach": witness.motion_search_speed() * Motion.HORIZON + 2.0 * ResidentScript.BODY_RADIUS,
			"epoch": str(resident.motion_sample_epoch()), "snapshot_frame": manager.motion_snapshot_state().frame})
	print("CHARACTER03_RESET ", JSON.stringify({"speeds": speeds, "samples": reset_samples}))
	check(speeds.size() == 3 and float(speeds.max()) <= resident.speed + 0.2,
		"reset epoch never appears as an artificial high-speed peer")

func _audit_active() -> void:
	for resident: Resident in active:
		if resident.hidden or resident.state == &"knocked": continue
		var point: Vector3 = resident.global_position
		audit.ground = audit.ground and _permitted_ground(point)
		audit.solids = audit.solids and _solid_clear(point)
		audit.bodies = audit.bodies and _planar(resident.body.global_position - point).length() < 0.001
		if audit.previous.has(resident.index):
			var travelled := _planar(point - Vector3(audit.previous[resident.index])).length()
			audit.bounded = audit.bounded and travelled <= maxf(resident.speed, Motion.DODGE_SPEED) * DT + 0.003
		audit.previous[resident.index] = point

func _permitted_ground(point: Vector3) -> bool:
	var at := Vector2(point.x, point.z)
	for rect: Rect2 in roads:
		if rect.has_point(at): return false
	for rect: Rect2 in grounds:
		if rect.has_point(at): return true
	return false

func _solid_clear(point: Vector3) -> bool:
	for rect: Rect2 in solids:
		if rect.has_point(Vector2(point.x, point.z)): return false
	return true

func _cache_geometry() -> void:
	grounds.append(Layout.RESIDENT_ENTRANCE_AREA)
	grounds.append_array(Layout.LIFE_GROUNDS)
	for surface: Array in Layout.SURFACES:
		var rect := Rect2(Vector2(surface[2]) - Vector2(surface[3]) * 0.5, surface[3])
		if surface[1] == "road": roads.append(rect.grow(ResidentScript.BODY_RADIUS - 0.01))
		if surface[1] in ["sidewalk", "yard_road"]: grounds.append(rect)
	for spec: Array in Layout.all_solids():
		var size: Vector3 = spec[3]
		var extent := Vector2(size.x, size.z)
		solids.append(Rect2(Vector2(spec[2]) - extent * 0.5, extent).grow(ResidentScript.BODY_RADIUS - 0.01))
	for spec: Array in Layout.BREAKABLES + Layout.PROPS_BREAKABLES:
		solids.append(Breakables.spec_rect(spec).grow(ResidentScript.BODY_RADIUS - 0.01))

func _report_audit(label: String) -> void:
	check(audit.ground and audit.solids, label + " actual roots stay on permitted non-road ground outside canonical solids")
	check(audit.bounded and audit.bodies, label + " actual bodies follow bounded resolved root displacement")
	check(manager.motion_snapshot_state().frame == Engine.get_physics_frames(), label + " uses the current actual manager snapshot")

func _car_clearance(point: Vector3) -> float:
	var local: Vector3 = world.car.global_transform.affine_inverse() * point
	var half: Vector3 = LadaScript.SIZE * 0.5
	var outside := Vector2(absf(local.x) - half.x, absf(local.z) - half.z)
	return outside.max(Vector2.ZERO).length() + minf(maxf(outside.x, outside.y), 0.0) - ResidentScript.BODY_RADIUS

func _planar(point: Vector3) -> Vector3:
	return Vector3(point.x, 0, point.z)

func _park_car_away_from(point: Vector3) -> void:
	var remote := point
	for route: Array in Layout.RESIDENT_ROUTES:
		for candidate: Vector3 in route:
			if candidate.distance_to(point) > remote.distance_to(point): remote = candidate
	world.car.reset_to(remote, 0.0)

func _frames(count: int) -> void:
	for frame in count: await observer.completed

func _finish() -> void:
	if is_instance_valid(main):
		for kind in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
			for player: Node in main.find_children("*", kind, true, false): player.stop()
		main.queue_free()
	if is_instance_valid(car_trajectory): car_trajectory.queue_free()
	main = null
	world = null
	manager = null
	active.clear()
	await _frames(4)
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	observer.queue_free()
	await process_frame
	OS.delay_msec(100)
	await process_frame
	print("CHARACTER03_INTEGRATION_NOT_RUN: full city endurance/regression suites, renderer, GPU naturalness, FPS")
	print("CHARACTER03_INTEGRATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
