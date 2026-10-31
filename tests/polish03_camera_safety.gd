extends "res://tests/polish03a_test.gd"
## Independent focused oracle. Original POLISH03A executes unchanged before extra Input scenarios.
## Run at --fixed-fps 60 --max-fps 60, original graphical profile; no engine run by author.
## process_frame is after physics/native SpringArm. Missing physics poses invalidate a phase.

const WORLD_MASK := 1 # C2 camera policy, independently stated, not production ARM_MASK/raw-safe.
const CAST_NUMERIC_EPS_M := 0.001 # 1 mm cast fraction tolerance; full-radius overlaps stay strict.
const WALL_ID := "H3_North"
var safety_checks := 0
var safety_failures: Array[String] = []
var _watch := false
var _phase := ""
var _last_physics := -1
var _stats: Dictionary = {}
var _sphere := SphereShape3D.new()
var _wall_z := NAN
var _wall_x := NAN

func _run() -> void:
	process_frame.connect(_post_physics_pose)
	print("CAMERA_SAFETY_PROFILE ", JSON.stringify({
		"engine": Engine.get_version_info(), "physics_hz": Engine.physics_ticks_per_second,
		"display_server": DisplayServer.get_name(), "args": OS.get_cmdline_args(),
		"camera_sha256": FileAccess.get_sha256("res://game/camera/camera_rig.gd"),
		"original_test_sha256": FileAccess.get_sha256("res://tests/polish03a_test.gd"),
		"oracle_sha256": FileAccess.get_sha256(get_script().resource_path),
		"sampling": "process_frame after native physics; every observed physics pose required",
		"shape": "full actual arm sphere radius, independent queries, query margin zero (full physical sphere; no assumed native padding)",
		"scope": "original Babka/vendor; H3 real approach/contact/look/retreat; Input E follow(false) car to foot",
		"world_mask": WORLD_MASK, "cast_numeric_epsilon_m": CAST_NUMERIC_EPS_M,
		"original_jerk_oracle": "inherited unchanged; no windows, timings, assertions or threshold overrides"}))
	_safety_check(Engine.physics_ticks_per_second == 60, "original 60 Hz physics profile")
	await super._run()

func _talk_series(label: String, open: Callable, close: Callable) -> void:
	_start_phase("original-" + label)
	await super._talk_series(label, open, close)
	# Do not delay inherited flow: its last physics_frame resumes before native Arm.
	_end_original_phase_after_pose(_phase, 160, Engine.get_physics_frames())

func _end_original_phase_after_pose(label: String, min_samples: int, closing_physics: int) -> void:
	# Sampler was connected first; it records the closing tick before this continuation.
	# The original next fixture may already have changed state; record that actual boundary.
	await process_frame
	if not _watch or _phase != label:
		_safety_check(false, label + ": phase ownership changed before closing native pose")
		return
	if _last_physics < closing_physics:
		var s: Dictionary = _stats[label]
		s["invalid"] = int(s["invalid"]) + 1
	_end_phase(min_samples)

func _start_phase(label: String) -> void:
	_phase = label
	_last_physics = -1
	_stats[label] = {"samples": 0, "missed_physics": 0, "invalid": 0,
		"endpoint_hits": 0, "pivot_hits": 0, "sweep_hits": 0, "ray_hits": 0,
		"h3_contacts": 0, "nominal_h3_blocked": 0, "min_radius": INF,
		"max_radius": 0.0, "max_native_shortening": 0.0, "unsafe_prints": 0}
	_watch = true

func _end_phase(min_samples: int) -> void:
	_watch = false
	var s: Dictionary = _stats[_phase]
	print("CAMERA_SAFETY_PHASE ", JSON.stringify({"phase": _phase, "statistics": s}))
	_safety_check(int(s["samples"]) >= min_samples, _phase + ": enough actual postphysics poses")
	_safety_check(int(s["missed_physics"]) == 0 and int(s["invalid"]) == 0, _phase + ": no missing physics poses or invalid queries")
	for key in ["endpoint_hits", "pivot_hits", "sweep_hits", "ray_hits"]:
		_safety_check(int(s[key]) == 0, _phase + ": " + key + " = 0")

func _exclusions(rig: CameraRig) -> Array[RID]:
	var excluded: Array[RID] = rig.permanent_exclusions.duplicate()
	if rig.target is CollisionObject3D:
		excluded.append((rig.target as CollisionObject3D).get_rid())
	return excluded

func _query(at: Vector3, excluded: Array[RID]) -> PhysicsShapeQueryParameters3D:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.margin = 0.0 # Test the full physical sphere; native shape casting does not subtract arm.margin.
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = WORLD_MASK
	q.exclude = excluded
	return q

func _hit_paths(hits: Array) -> Array[String]:
	var paths: Array[String] = []
	for hit: Dictionary in hits:
		var collider := hit.get("collider") as Node
		paths.append(str(collider.get_path()) if is_instance_valid(collider) else str(hit))
	return paths

func _post_physics_pose() -> void:
	if not _watch or not is_instance_valid(world):
		return
	var frame := Engine.get_physics_frames()
	if frame == _last_physics:
		return
	var s: Dictionary = _stats[_phase]
	if _last_physics >= 0 and frame > _last_physics + 1:
		s["missed_physics"] = int(s["missed_physics"]) + frame - _last_physics - 1
	_last_physics = frame
	var rig: CameraRig = world.camera_rig
	if not (rig.arm.shape is SphereShape3D) or rig.camera != world.get_viewport().get_camera_3d():
		s["invalid"] = int(s["invalid"]) + 1
		return
	_sphere.radius = (rig.arm.shape as SphereShape3D).radius
	if _sphere.radius <= 0.0 or rig.arm.margin < 0.0:
		s["invalid"] = int(s["invalid"]) + 1
		return
	var excluded := _exclusions(rig)
	var space := world.get_world_3d().direct_space_state
	var pivot := rig.arm.global_position
	var camera_at := rig.camera.global_position
	var span := camera_at - pivot
	var radius := span.length()
	var endpoint_hits := _hit_paths(space.intersect_shape(_query(camera_at, excluded), 32))
	var pivot_hits := _hit_paths(space.intersect_shape(_query(pivot, excluded), 32))
	var sweep_query := _query(pivot, excluded)
	sweep_query.motion = span
	var sweep := space.cast_motion(sweep_query)
	var blocked_m := 0.0
	if sweep.size() == 2:
		blocked_m = radius * (1.0 - float(sweep[0]))
	else:
		s["invalid"] = int(s["invalid"]) + 1
	var ray_query := PhysicsRayQueryParameters3D.create(pivot, camera_at, WORLD_MASK, excluded)
	ray_query.hit_from_inside = true
	var ray_hit := space.intersect_ray(ray_query) if radius > 0.00001 else {}
	var nominal: float = CameraRig.PROFILES[rig.profile]["distance"]
	var nominal_ray := PhysicsRayQueryParameters3D.create(pivot, pivot + rig.global_basis.z * nominal, WORLD_MASK, excluded)
	nominal_ray.hit_from_inside = true
	var nominal_hit := space.intersect_ray(nominal_ray)
	var nominal_collider := nominal_hit.get("collider") as Node
	if is_instance_valid(nominal_collider) and str(nominal_collider.name) == WALL_ID:
		s["nominal_h3_blocked"] = int(s["nominal_h3_blocked"]) + 1
	var contacts: Array[String] = []
	if world.control_mode == &"on_foot":
		for i in world.player.get_slide_collision_count():
			var contact := world.player.get_slide_collision(i)
			var collider := contact.get_collider() as Node
			if is_instance_valid(collider) and str(collider.name) == WALL_ID and contact.get_normal().z > 0.7:
				contacts.append(str(collider.get_path()))
		if not contacts.is_empty():
			s["h3_contacts"] = int(s["h3_contacts"]) + 1
	s["samples"] = int(s["samples"]) + 1
	s["min_radius"] = minf(float(s["min_radius"]), radius)
	s["max_radius"] = maxf(float(s["max_radius"]), radius)
	s["max_native_shortening"] = maxf(float(s["max_native_shortening"]), rig.arm.spring_length - rig.arm.get_hit_length())
	var unsafe := false
	for item in [["endpoint_hits", not endpoint_hits.is_empty()], ["pivot_hits", not pivot_hits.is_empty()], ["sweep_hits", blocked_m > CAST_NUMERIC_EPS_M], ["ray_hits", not ray_hit.is_empty()]]:
		if bool(item[1]):
			s[item[0]] = int(s[item[0]]) + 1
			unsafe = true
	if int(s["samples"]) == 1 or int(s["samples"]) % 15 == 0 or (unsafe and int(s["unsafe_prints"]) < 8):
		var ray_paths: Array[String] = []
		if not ray_hit.is_empty():
			ray_paths = _hit_paths([ray_hit])
		print("CAMERA_SAFETY_POSE ", JSON.stringify({"phase": _phase, "physics_frame": frame,
			"player": str(world.player.global_position), "player_velocity": str(world.player.velocity),
			"input": str(Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")),
			"profile": str(rig.profile), "target": str(rig.target.get_path()),
			"pivot": str(pivot), "camera": str(camera_at), "actual_radius": radius,
			"sphere_radius": _sphere.radius, "native_margin": rig.arm.margin,
			"spring_length": rig.arm.spring_length, "native_hit_length": rig.arm.get_hit_length(),
			"endpoint_hits": endpoint_hits, "pivot_hits": pivot_hits, "sweep_blocked_m": blocked_m,
			"ray_hits": ray_paths, "h3_contacts": contacts,
			"excluded_count": excluded.size(), "yaw": rig.yaw, "input_yaw": rig.input_yaw}))
		if unsafe:
			s["unsafe_prints"] = int(s["unsafe_prints"]) + 1

func _post_ticks(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _release_safety_input() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"look_left", &"look_right", &"interact"]:
		Input.action_release(action)

func _press_world_direction(direction: Vector3) -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(action)
	var local := direction.rotated(Vector3.UP, -world.camera_rig.yaw)
	if local.x > 0.001:
		Input.action_press(&"move_right", local.x)
	elif local.x < -0.001:
		Input.action_press(&"move_left", -local.x)
	if local.z > 0.001:
		Input.action_press(&"move_back", local.z)
	elif local.z < -0.001:
		Input.action_press(&"move_forward", -local.z)

func _look_to_wall() -> void:
	for i in 110:
		Input.action_release(&"look_left")
		Input.action_release(&"look_right")
		var difference := angle_difference(world.camera_rig.yaw, PI)
		if absf(difference) < 0.035:
			break
		Input.action_press(&"look_left" if difference > 0.0 else &"look_right")
		await _post_ticks(1)
	Input.action_release(&"look_left")
	Input.action_release(&"look_right")
	_safety_check(absf(angle_difference(world.camera_rig.yaw, PI)) < 0.04, "real right-stick Input restores camera toward H3 wall")

func _tap_interact() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	await _post_ticks(2)
	event = InputEventAction.new()
	event.action = &"interact"
	event.pressed = false
	Input.parse_input_event(event)
	await _post_ticks(2)

func _focused_safety() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"look_left", &"look_right", &"interact"]:
		if not _safety_check(InputMap.has_action(action), "real InputMap has " + str(action)):
			return
	for spec in Layout.SOLIDS:
		if str(spec[0]) == WALL_ID:
			var xz: Vector2 = spec[2]
			var size: Vector3 = spec[3]
			_wall_x = xz.x
			_wall_z = xz.y + size.z * 0.5
	var wall := world.get_node("LevelGeometry").get_node_or_null(NodePath(WALL_ID)) as CollisionObject3D
	if not _safety_check(is_finite(_wall_z) and is_instance_valid(wall) and (wall.collision_layer & WORLD_MASK) != 0, "actual H3 World wall exists and its current Layout boundary is known"):
		return
	print("CAMERA_SAFETY_WALL ", JSON.stringify({"path": str(wall.get_path()), "south_z": _wall_z, "x": _wall_x}))
	_release_safety_input()
	world.stealth.grant_grace(120.0)
	world.player.place(Vector3(_wall_x, 0, _wall_z + 6.0), 0.0)
	world.camera_rig.yaw = PI # initial fixture only; all subsequent look uses Input.
	world.camera_rig.pitch = -0.25
	world.camera_rig.snap()
	_start_phase("H3-settle")
	await _post_ticks(20)
	_end_phase(18)
	_safety_check(world.control_mode == &"on_foot" and world.player.input_enabled and world.player.is_on_floor(), "H3 fixture is grounded real controllable player")
	var start := world.player.global_position
	_start_phase("H3-approach-contact")
	_press_world_direction(Vector3.FORWARD)
	await _post_ticks(150)
	_release_safety_input()
	_end_phase(145)
	var approach: Dictionary = _stats["H3-approach-contact"]
	_safety_check(start.z - world.player.global_position.z > 3.0, "Input actually moves player toward H3")
	_safety_check(int(approach["h3_contacts"]) >= 10, "approach reaches sustained actual H3 wall contact")
	_safety_check(int(approach["nominal_h3_blocked"]) >= 5 and float(approach["min_radius"]) < 3.8, "real H3 forces actual camera shortening during approach")
	_safety_check(world.player.global_position.z >= _wall_z + 0.30, "player remains on outside face of H3")
	_start_phase("H3-wall-look")
	await _post_ticks(24)
	await _look_to_wall()
	await _post_ticks(24)
	_end_phase(40)
	var compressed := world.camera_rig.camera.global_position.distance_to(world.camera_rig.arm.global_position)
	_safety_check(compressed < 2.0, "wall-facing camera is actually compressed before retreat")
	var wall_position := world.player.global_position
	_start_phase("H3-retreat-release")
	_press_world_direction(Vector3.BACK)
	await _post_ticks(105)
	_release_safety_input()
	await _post_ticks(90)
	_end_phase(190)
	_safety_check(world.player.global_position.z - wall_position.z > 3.0, "real Input walks away from H3")
	var released := world.camera_rig.camera.global_position.distance_to(world.camera_rig.arm.global_position)
	_safety_check(released > 4.0 and released > compressed + 1.0, "camera actually recovers its long radius after retreat")
	# New scenario: initial setup only; production E paths invoke follow(false) on both transitions.
	var car_position := Vector3(_wall_x, 0, _wall_z + Lada.SIZE.z * 0.5 + 0.8)
	world.car.reset_to(car_position, PI)
	world.player.place(world.car.global_transform * Vector3(-2.2, 0, 0), PI)
	world.camera_rig.yaw = PI
	world.camera_rig.pitch = -0.25
	world.camera_rig.snap()
	_start_phase("H3-car-setup")
	await _post_ticks(20)
	_end_phase(18)
	_start_phase("H3-enter-car-native")
	await _tap_interact()
	await _post_ticks(60)
	_end_phase(60)
	if not _safety_check(world.control_mode == &"in_car" and world.camera_rig.target == world.car and world.camera_rig.profile == &"in_car", "real E enters car and activates native car camera"):
		return
	var car_stats: Dictionary = _stats["H3-enter-car-native"]
	_safety_check(int(car_stats["nominal_h3_blocked"]) >= 10 and float(car_stats["min_radius"]) < 4.2, "car-to-foot boundary starts with actual H3-compressed native car arm")
	_start_phase("H3-exit-car-follow-false")
	await _tap_interact()
	await _post_ticks(100)
	_end_phase(100)
	_safety_check(world.control_mode == &"on_foot" and world.camera_rig.target == world.player and world.camera_rig.profile == &"on_foot" and world.player.input_enabled, "real E exit invokes normal follow(false) and restores foot control")
	var foot_stats: Dictionary = _stats["H3-exit-car-follow-false"]
	_safety_check(int(foot_stats["nominal_h3_blocked"]) >= 10 and float(foot_stats["min_radius"]) < 3.8, "follow(false) is exercised beside a real camera-blocking wall")
	_start_phase("H3-after-exit-retreat")
	var exit_position := world.player.global_position
	_press_world_direction(Vector3.BACK)
	await _post_ticks(75)
	_release_safety_input()
	await _post_ticks(60)
	_end_phase(130)
	_safety_check(world.player.global_position.z - exit_position.z > 2.0, "real player input moves away after car-to-foot transition")

func _safety_check(condition: bool, label: String) -> bool:
	safety_checks += 1
	print(("PASS: " if condition else "FAIL: ") + "CAMERA_SAFETY " + label)
	if not condition:
		safety_failures.append(label)
	return condition

func _finish() -> void:
	# Preserve original count/result independently; never rewrite original checks or jerk thresholds.
	print("POLISH03A: %d checks, %d failures" % [checks, failures.size()])
	print("CAMERA_SAFETY_ORIGINAL ", JSON.stringify({"checks": checks, "failures": failures}))
	await _focused_safety()
	_watch = false
	_release_safety_input()
	print("CAMERA_SAFETY: %d checks, %d failures; original POLISH03A failures %d" % [safety_checks, safety_failures.size(), failures.size()])
	print("CAMERA_SAFETY_FAILURES ", JSON.stringify(safety_failures))
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() and safety_failures.is_empty() else 1)
