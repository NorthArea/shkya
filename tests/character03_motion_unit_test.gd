extends SceneTree
## Developer checks for local steering. Real Residents/Life acceptance is separate.
const Motion = preload("res://game/npc/pedestrian_motion.gd")
var checks := 0
var failures: Array[String] = []
var footprints: Array[Vector3] = [Vector3.ZERO]

func _initialize() -> void:
	_acceleration_and_rates()
	_wait_and_release()
	_predictive_geometry()
	_head_on_passage()
	_stationary_peer_bypass()
	_blocked_dodge_replans()
	_rounded_car_corners()
	_footprint_and_cancellation()
	print("CHARACTER03_MOTION_UNIT: %d checks, %d failures; real Residents/Life/LOD/gameplay NOT_RUN" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)

func _clear(_from: Vector3, to: Vector3) -> bool:
	return absf(to.z) <= 2.0

func _narrow(_from: Vector3, to: Vector3) -> bool:
	return absf(to.z) <= 0.05

func _changed_ground(_from: Vector3, to: Vector3) -> bool:
	return to.z <= 0.1

func _open(_from: Vector3, _to: Vector3) -> bool:
	return true

func _obstacle(id: int, at: Vector3, movement: Vector3, kind: StringName = &"peer") -> Dictionary:
	return {"id": id, "unit_id": id, "kind": kind,
		"position": at, "velocity": movement, "radius": 0.35}

func _acceleration_and_rates() -> void:
	var positions: Array[Vector3] = []
	for hz: int in [15, 30, 60, 120]:
		var motion := Motion.new(0)
		var here := Vector3.ZERO
		var obstacles: Array[Dictionary] = []
		var dt := 1.0 / hz
		var speed_ok := true
		for index in hz * 2:
			var before := here
			here += motion.step(here, Vector3.ZERO, Vector3(20, 0, 0), 1.4,
				footprints, obstacles, dt, _clear)
			speed_ok = speed_ok and here.distance_to(before) <= 1.4 * dt + 0.0001
		check(speed_ok, "%dHz and sparse-step cadence never increase cruise speed" % hz)
		check(absf(here.x - 2.52) < 0.012 and absf(here.z) < 0.0001,
			"%dHz integrates the bounded 0.4-second acceleration, then cruise" % hz)
		positions.append(here)
	for at: Vector3 in positions:
		check(at.distance_to(positions[0]) < 0.012, "rate changes preserve elapsed-distance ramp")
	var motion := Motion.new(0)
	var empty: Array[Dictionary] = []
	var here := Vector3.ZERO
	for index in 600:
		here += motion.step(here, Vector3.ZERO, Vector3(1, 0, 0), 1.4,
			footprints, empty, 1.0 / 60.0, _clear)
	check(here.distance_to(Vector3(1, 0, 0)) < 0.001, "arrival reaches the same canonical endpoint without overshoot")

func _wait_and_release() -> void:
	var motion := Motion.new(0)
	var here := Vector3.ZERO
	var obstacles: Array[Dictionary] = [_obstacle(-1, Vector3(1.2, 0, 0), Vector3.ZERO, &"player")]
	var no_dodge := true
	for index in 240:
		here += motion.step(here, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
			footprints, obstacles, 1.0 / 60.0, _clear)
		no_dodge = no_dodge and motion.mode != &"dodge"
	check(here.x < 0.42 and absf(here.z) < 0.001 and no_dodge,
		"a stationary player blocks the path without side-stepping or contact")
	obstacles.clear()
	for index in 120:
		here += motion.step(here, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
			footprints, obstacles, 1.0 / 60.0, _clear)
	check(here.x > 1.8 and motion.mode == &"following", "removing the blocker resumes the same route without a timer deadlock")
	var blocked := Motion.new(2)
	var peers: Array[Dictionary] = [_obstacle(1, Vector3(1.2, 0, 0), Vector3.ZERO)]
	here = Vector3.ZERO
	for index in 480:
		here += blocked.step(here, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
			footprints, peers, 1.0 / 60.0, _narrow)
	check(here.x < 0.42 and absf(here.z) <= 0.05,
		"expired commitments never force a dodge through forbidden side ground")

func _predictive_geometry() -> void:
	var motion := Motion.new(5)
	var car := {"id": -2, "unit_id": -2, "kind": &"car", "position": Vector3(0, 0, -9),
		"velocity": Vector3(0, 0, 8), "radius": 2.0, "basis": Basis.IDENTITY, "half_extents": Vector2(0.8, 1.8)}
	var obstacles: Array[Dictionary] = [car]
	motion.step(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -20), 1.2,
		footprints, obstacles, 1.0 / 60.0, _clear)
	check(motion.threat_id == -2 and motion.mode == &"stopped",
		"an approaching oriented car is anticipated before actual contact")
	car.velocity = Vector3(0, 0, -8)
	motion.reset()
	motion.step(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -20), 1.2,
		footprints, obstacles, 1.0 / 60.0, _clear)
	check(motion.threat_id == -1 and motion.mode == &"following", "a receding car does not trigger a false reaction")
	car.position = Vector3(2, 0, -2)
	car.velocity = Vector3.ZERO
	motion.reset()
	motion.step(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -20), 1.2,
		footprints, obstacles, 1.0 / 60.0, _clear)
	check(motion.threat_id == -1, "actual narrow box width does not become a large circular car blocker")
	var a := _obstacle(20, Vector3(1.2, 0, 0), Vector3.ZERO)
	var b := _obstacle(10, Vector3(1.2, 0, 0), Vector3.ZERO)
	var forward: Array[Dictionary] = [a, b]
	var reversed: Array[Dictionary] = [b, a]
	motion.reset()
	motion.step(Vector3.ZERO, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
		footprints, forward, 1.0 / 60.0, _clear)
	var first := motion.threat_id
	motion.reset()
	motion.step(Vector3.ZERO, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
		footprints, reversed, 1.0 / 60.0, _clear)
	check(first == 10 and motion.threat_id == first, "snapshot iteration order does not change a simultaneous threat tie")

func _head_on_passage() -> void:
	var low := Motion.new(1)
	var high := Motion.new(2)
	var a := Vector3(-3, 0, 0)
	var b := Vector3(3, 0, 0)
	var va := Vector3.ZERO
	var vb := Vector3.ZERO
	var minimum := INF
	var bounded := true
	var dodged := false
	var dt := 1.0 / 60.0
	for index in 720:
		# Both decisions observe the same preceding physical frame.
		var a_obstacles: Array[Dictionary] = [_obstacle(2, b, vb)]
		var b_obstacles: Array[Dictionary] = [_obstacle(1, a, va)]
		var da := low.step(a, Vector3(-3, 0, 0), Vector3(3, 0, 0), 1.2,
			footprints, a_obstacles, dt, _clear)
		var db := high.step(b, Vector3(3, 0, 0), Vector3(-3, 0, 0), 1.2,
			footprints, b_obstacles, dt, _clear)
		a += da
		b += db
		va = da / dt
		vb = db / dt
		minimum = minf(minimum, a.distance_to(b))
		bounded = bounded and absf(a.z) <= Motion.MAX_OFFSET + 0.001 and absf(b.z) <= Motion.MAX_OFFSET + 0.001
		dodged = dodged or high.mode == &"dodge"
	check(dodged, "head-on yielding produces a committed physical side step")
	check(minimum >= 0.69 and bounded, "opposing peers preserve body separation and bounded route offset")
	check(a.distance_to(Vector3(3, 0, 0)) < 0.12 and b.distance_to(Vector3(-3, 0, 0)) < 0.12,
		"a passable head-on corridor makes finite progress for both stable priorities")

func _stationary_peer_bypass() -> void:
	var motion := Motion.new(2)
	var here := Vector3.ZERO
	var obstacles: Array[Dictionary] = [_obstacle(1, Vector3(1.6, 0, 0), Vector3.ZERO)]
	var minimum := INF
	var offset := 0.0
	for index in 600:
		here += motion.step(here, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
			footprints, obstacles, 1.0 / 60.0, _clear)
		minimum = minf(minimum, here.distance_to(Vector3(1.6, 0, 0)))
		offset = maxf(offset, absf(here.z))
	check(offset > 0.6 and offset <= Motion.MAX_OFFSET + 0.001, "a standing peer receives a bounded bypass instead of overlap")
	check(minimum >= 0.69 and here.distance_to(Vector3(6, 0, 0)) < 0.1,
		"bypass keeps its side clearance until it can rejoin the unchanged goal")

func _blocked_dodge_replans() -> void:
	for geometry_changes: bool in [true, false]:
		var motion := Motion.new(2)
		var here := Vector3.ZERO
		var obstacles: Array[Dictionary] = [_obstacle(1, Vector3(1.6, 0, 0), Vector3.ZERO)]
		var started := false
		for index in 120:
			here += motion.step(here, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
				footprints, obstacles, 1.0 / 60.0, _clear)
			if motion.mode == &"dodge":
				started = true
				break
		check(started and here.z > 0.0 and here.z < 0.1,
			"dynamic obstruction fixture first reaches the real positive-side dodge")
		if not started:
			continue
		var start_x := here.x
		obstacles.clear()
		if not geometry_changes:
			obstacles.append(_obstacle(-1, Vector3(here.x, 0, 0.86), Vector3.ZERO, &"player"))
		var callback: Callable = _changed_ground if geometry_changes else _clear
		var safe := true
		for index in 90:
			here += motion.step(here, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
				footprints, obstacles, 1.0 / 60.0, callback)
			if geometry_changes:
				safe = safe and here.z <= 0.1
			else:
				safe = safe and here.distance_to(Vector3(obstacles[0].position)) >= 0.70
		check(safe, "blocked commitments never override changed ground or a new body")
		check(here.x - start_x > 0.6 and motion.mode in [&"following", &"return"],
			"an expired blocked dodge releases its stale target and resumes the now-clear canonical path")

func _rounded_car_corners() -> void:
	var motion := Motion.new(5)
	var corner := Vector3(1.15, 0, 2.15)
	var car := {"id": -2, "unit_id": -2, "kind": &"car", "position": Vector3.ZERO,
		"velocity": Vector3(0, 0, -1), "radius": 2.0, "basis": Basis.IDENTITY, "half_extents": Vector2(0.8, 1.8)}
	var obstacles: Array[Dictionary] = [car]
	var movement := motion.step(corner, corner, corner + Vector3(6, 0, 0), 1.2,
		footprints, obstacles, 1.0 / 60.0, _open)
	check(motion._separation(corner, car) > 0.06 and motion.threat_id == -1,
		"a genuinely separated rounded car corner does not inherit the expanded-box false overlap")
	check(movement.x > 0.0 and motion.mode == &"following",
		"a receding car corner permits movement that increases the true separation")
	car.velocity = Vector3.ZERO
	var toward := Vector3(-1, 0, -1)
	var hit: float = motion._collision_time(corner, toward, car, 1.0)
	var expected := 0.35 - (0.35 + Motion.CLEARANCE) / sqrt(2.0)
	check(is_finite(hit) and absf(hit - expected) < 0.001,
		"an incoming diagonal still hits the real circular corner at the geometric boundary")
	check(absf(motion._separation(corner + toward * hit, car)) < 0.001,
		"corner sweep and static clearance agree on the same actual contact surface")

func _footprint_and_cancellation() -> void:
	var motion := Motion.new(2)
	var pair: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, 1.2)]
	var obstacles: Array[Dictionary] = [_obstacle(-1, Vector3(1, 0, 1.2), Vector3.ZERO, &"player")]
	motion.step(Vector3.ZERO, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
		pair, obstacles, 1.0 / 60.0, _clear)
	check(motion.threat_id == -1 and motion.mode == &"yield", "a pair leader anticipates a hazard to its follower footprint")
	motion.suspend()
	check(motion.velocity == Vector3.ZERO and motion.mode == &"following" and motion.reaction == &"",
		"activity/knock cancellation immediately relinquishes local steering")
	var own: Array[Dictionary] = [_obstacle(2, Vector3(1, 0, 0), Vector3.ZERO)]
	motion.step(Vector3.ZERO, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
		pair, own, 1.0 / 60.0, _clear)
	check(motion.mode == &"following", "same-unit snapshots never make a pair yield to itself")
	motion.reset()
	motion.step(Vector3.ZERO, Vector3.ZERO, Vector3(6, 0, 0), 1.2,
		pair, obstacles, 1.0 / 60.0, _clear, false)
	check(motion.mode == &"following" and motion.velocity.x > 0.0,
		"an already authorized road crossing retains its no-new-stops policy")
