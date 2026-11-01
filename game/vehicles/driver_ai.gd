extends RefCounted
## Explicit mission-driving controller. It observes and commands; the vehicle owns all movement and contacts.
const Route = preload("res://game/vehicles/driver_route.gd")
const Layout = preload("res://game/world/layout.gd")
const MAX_SPEED := 11.0
const ACCEL := 2.2
const DECEL := 3.2
const MAX_STEER := 0.52
const LATERAL_ACCEL := 1.8
const REVERSE_SPEED := 1.6
const MAX_REVERSE_ATTEMPTS := 3
const REVERSE_TIME := 1.8
const REVERSE_DISTANCE := 2.5
const SIGHT_RANGE := 65.0
const MEMORY_SECONDS := 4.0
const PREDICTION_SECONDS := 1.25
const FOLLOW_GAP := 4.0
const BODY_CLEAR := 0.35
const SENSOR_MASK := 1 | 2 | 4 | 32 | 64
const REPLAN_SECONDS := 0.5
const STUCK_SECONDS := 2.5
const WAYPOINT_REACH := 7.0
const OFF := &"off"
const RACE := &"race"
const PURSUE := &"pursue"
const EVADE := &"evade"

var route: Route = Route.new()
var mode: StringName = OFF
var state: StringName = &"off"
var reason: StringName = &"off"
var target_visible := false
var target_last_seen := Vector3.ZERO
var observation_age := INF
var route_s := 0.0
var reverse_attempts := 0
var obstacle_gap := INF
var blocked_by: Object = null
var _vehicle: PhysicsBody3D
var _target: Node3D
var _waypoints: Array[Vector3] = []
var _waypoint := 0
var _size := Vector3.ONE
var _wheelbase := 2.4
var _observed_velocity := Vector3.ZERO
var _last_goal := Vector3(INF, INF, INF)
var _plan_in := 0.0
var _stuck_time := 0.0
var _reverse_time := 0.0
var _reverse_start := Vector3.ZERO
var _progress_start := Vector3.ZERO
var _last_position := Vector3.ZERO
var _forward_progress := 0.0
var _query := PhysicsShapeQueryParameters3D.new()
var _rear_query := PhysicsShapeQueryParameters3D.new()
var _obstacle_position := Vector3.ZERO

func attach(vehicle: PhysicsBody3D) -> void:
	_vehicle = vehicle
	_size = vehicle.get("size")
	_wheelbase = float(vehicle.get("wheelbase"))
	route.configure(vehicle.get("path"), _size)
	var shape := BoxShape3D.new()
	shape.size = Vector3(_size.x + BODY_CLEAR * 2.0, minf(_size.y, 1.5), _size.z + BODY_CLEAR * 2.0)
	_query.shape = shape
	_query.collision_mask = SENSOR_MASK
	_query.exclude = [vehicle.get_rid()]
	var rear_shape := BoxShape3D.new()
	rear_shape.size = Vector3(_size.x + BODY_CLEAR * 2.0, minf(_size.y, 1.5), 0.5)
	_rear_query.shape = rear_shape
	_rear_query.collision_mask = SENSOR_MASK
	_rear_query.exclude = [vehicle.get_rid()]
	_progress_start = vehicle.global_position
	_last_position = vehicle.global_position

func set_mode(new_mode: StringName, target: Node3D = null, waypoints: Array[Vector3] = []) -> bool:
	clear()
	if new_mode == OFF:
		return true
	if not is_instance_valid(_vehicle) or not _vehicle.is_inside_tree():
		return false
	if new_mode != RACE and new_mode != PURSUE and new_mode != EVADE:
		return false
	if new_mode == RACE:
		if waypoints.is_empty():
			return false
		for point in waypoints:
			if not route.reachable(point):
				return false
	elif not is_instance_valid(target) or target == _vehicle:
		return false
	_target = target
	_waypoints = waypoints.duplicate()
	mode = new_mode
	state = &"planning"
	reason = &"requested"
	_progress_start = _vehicle.global_position
	_last_position = _vehicle.global_position
	return true

func clear() -> void:
	mode = OFF
	state = &"off"
	reason = &"off"
	_target = null
	_waypoints.clear()
	_waypoint = 0
	target_visible = false
	target_last_seen = Vector3.ZERO
	observation_age = INF
	_observed_velocity = Vector3.ZERO
	_last_goal = Vector3(INF, INF, INF)
	_plan_in = 0.0
	_stuck_time = 0.0
	_reverse_time = 0.0
	_forward_progress = 0.0
	reverse_attempts = 0
	blocked_by = null
	obstacle_gap = INF
	route.clear_blocks()

func is_active() -> bool:
	return mode != OFF

## The contact controller owns the body during impact. Observation time still passes.
func suspend(delta: float) -> void:
	if not is_active() or not is_instance_valid(_vehicle) or delta <= 0.0:
		return
	route.tick(delta)
	if mode == PURSUE or mode == EVADE:
		_observe(delta)
	_last_position = _vehicle.global_position
	_stuck_time = 0.0
	_forward_progress = 0.0
	if state == &"recovery_exhausted" and _vehicle.global_position.distance_to(_progress_start) >= 3.0:
		state = &"planning"
		reverse_attempts = 0

static func curvature_speed(curvature: float) -> float:
	return minf(MAX_SPEED, sqrt(LATERAL_ACCEL / maxf(absf(curvature), 0.0001)))

static func braking_speed(end_speed: float, distance: float) -> float:
	return sqrt(maxf(end_speed * end_speed + 2.0 * DECEL * maxf(distance, 0.0), 0.0))

func _command(speed := 0.0, steering := 0.0, reverse := false, aim := Vector3.ZERO) -> Dictionary:
	return {"target_speed": clampf(speed, 0.0, MAX_SPEED), "steering": clampf(steering, -1.0, 1.0),
		"reverse": reverse, "state": state, "reason": reason, "route_target": aim, "target_visible": target_visible}

func _stop(next_state: StringName, why: StringName) -> Dictionary:
	state = next_state
	reason = why
	return _command()

func tick(delta: float) -> Dictionary:
	if not is_active() or not is_instance_valid(_vehicle) or delta <= 0.0:
		return _command()
	route.tick(delta)
	_plan_in -= delta
	var position := _vehicle.global_position
	var displacement := position - _last_position
	_last_position = position
	var forward := -_vehicle.global_basis.z
	var speed := absf(float(_vehicle.get("speed")))
	if state == &"recovery_exhausted" and position.distance_to(_progress_start) < 3.0:
		return _stop(&"recovery_exhausted", &"stuck")
	var goal := Vector3.ZERO
	var desired := MAX_SPEED
	if mode == RACE:
		while _waypoint < _waypoints.size() and position.distance_to(_waypoints[_waypoint]) < WAYPOINT_REACH:
			_waypoint += 1
			_plan_in = 0.0
		if _waypoint >= _waypoints.size():
			return _stop(&"arrived", &"course_complete")
		goal = _waypoints[_waypoint]
	else:
		_observe(delta)
		if observation_age > MEMORY_SECONDS and mode != EVADE:
			return _stop(&"lost", &"target_unseen")
		if mode == EVADE:
			goal = _escape_goal(position, forward) if observation_age <= MEMORY_SECONDS else _cruise_goal(position, forward)
			if observation_age > MEMORY_SECONDS:
				desired = minf(desired, 9.0)
		else:
			var horizon := minf(PREDICTION_SECONDS, position.distance_to(target_last_seen) / maxf(speed, 4.0))
			var prediction := target_last_seen + _observed_velocity * minf(PREDICTION_SECONDS, horizon + observation_age)
			goal = prediction if route.reachable(prediction) else target_last_seen
			if not route.reachable(goal):
				return _stop(&"waiting", &"target_off_road")
			# Intercept a road position, with a following gap. Contact is never a driving objective.
			var distance := position.distance_to(target_last_seen)
			desired = minf(desired, braking_speed(0.0, distance - FOLLOW_GAP - _size.z))
			if distance < FOLLOW_GAP + _size.z:
				return _stop(&"following", &"target_gap")
	if _plan_in <= 0.0 and (_last_goal.distance_to(goal) > 5.0 or route.length <= 0.1):
		_plan_in = REPLAN_SECONDS
		if not route.plan(position, forward, goal):
			_last_goal = Vector3(INF, INF, INF)
			return _stop(&"waiting", &"no_road_route")
		_last_goal = goal
	route_s = route.offset_of(position)
	if route.length <= 0.1:
		return _stop(&"waiting", &"no_road_route")
	if _reverse_time > 0.0:
		return _reverse_step(delta, forward)
	var lookahead := clampf(3.5 + speed * 0.65, 3.5, 9.0)
	var aim: Vector3 = route.position_at(route_s + lookahead)
	var to_aim := aim - position
	var alpha := atan2(to_aim.dot(Route.right_of(forward)), to_aim.dot(forward))
	var steering := atan(2.0 * _wheelbase * sin(alpha) / maxf(to_aim.length(), 1.0)) / MAX_STEER
	# Curvature and braking are sampled ahead, so a snowy bend is anticipated on the straight.
	var horizon := maxf(24.0, speed * speed / (2.0 * DECEL) + 8.0)
	var at := 0.0
	while at <= horizon and route_s + at <= route.length:
		desired = minf(desired, braking_speed(curvature_speed(route.curvature_at(route_s + at)), at))
		at += 1.5
	desired = minf(desired, braking_speed(0.0, route.length - route_s - 1.5))
	if absf(alpha) > 0.7:
		desired = minf(desired, 2.5)
	if absf(alpha) > 1.3:
		desired = 0.0
	_scan(speed, steering)
	if obstacle_gap < INF:
		desired = minf(desired, braking_speed(0.0, obstacle_gap - FOLLOW_GAP))
		if absf(alpha) < 0.8 and _is_road_obstruction(blocked_by):
			# The obstruction was physically sensed on our corridor. Never inspect unseen mission state.
			route.block_edge_at(_obstacle_position)
			_last_goal = Vector3(INF, INF, INF)
			_plan_in = 0.0
	state = &"driving" if desired > 0.1 else &"waiting"
	reason = &"road" if obstacle_gap == INF else &"obstacle"
	if state == &"driving" and _reverse_time <= 0.0:
		_forward_progress += maxf(0.0, displacement.dot(route.direction_at(route_s)))
	if _forward_progress > 5.0:
		_progress_start = position
		_forward_progress = 0.0
		reverse_attempts = 0
	# Waiting behind a pedestrian or an aligned queue is intentional, not a stuck vehicle.
	var queue_wait := obstacle_gap < INF and (absf(alpha) < 0.8 or not blocked_by is StaticBody3D)
	if speed < 0.3 and not queue_wait and (desired > 1.0 or absf(alpha) > 0.8):
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time >= STUCK_SECONDS:
		_stuck_time = 0.0
		if reverse_attempts >= MAX_REVERSE_ATTEMPTS:
			return _stop(&"recovery_exhausted", &"stuck")
		if _rear_clear(forward, REVERSE_DISTANCE):
			reverse_attempts += 1
			_reverse_time = REVERSE_TIME
			_reverse_start = position
			return _reverse_step(delta, forward)
		return _stop(&"waiting", &"rear_blocked")
	return _command(desired, steering, false, aim)

func _is_road_obstruction(body: Object) -> bool:
	if body is StaticBody3D and not body is AnimatableBody3D:
		return true
	# A sensed fence belongs to the existing closure owner; never query its mission state.
	var node := body as Node
	return node != null and node.get_parent() != null and node.get_parent().has_method("is_blocking")

func _observe(delta: float) -> void:
	observation_age += delta
	target_visible = false
	if not is_instance_valid(_target) or not _target.is_inside_tree():
		return
	var eye := _vehicle.global_position + Vector3.UP
	var destination := _target.global_position + Vector3.UP
	if eye.distance_to(destination) > SIGHT_RANGE:
		return
	var ray := PhysicsRayQueryParameters3D.create(eye, destination, SENSOR_MASK, [_vehicle.get_rid()])
	var hit := _vehicle.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var collider := hit.collider as Node
		if collider != _target and not _target.is_ancestor_of(collider):
			return
	target_visible = true
	if _target.has_method("vehicle_velocity"):
		_observed_velocity = _target.call("vehicle_velocity")
	elif _target is CharacterBody3D:
		_observed_velocity = (_target as CharacterBody3D).velocity
	elif observation_age < MEMORY_SECONDS and observation_age > 0.0:
		_observed_velocity = (_target.global_position - target_last_seen) / observation_age
	else:
		_observed_velocity = Vector3.ZERO
	_observed_velocity.y = 0.0
	_observed_velocity = _observed_velocity.limit_length(MAX_SPEED * 1.5)
	target_last_seen = _target.global_position
	observation_age = 0.0

func _escape_goal(position: Vector3, forward: Vector3) -> Vector3:
	# Candidate junctions, not arbitrary off-road points. Each candidate still needs a legal graph route.
	var best := position
	var score := -INF
	for point in Layout.RING:
		var away: float = point.distance_to(target_last_seen) - point.distance_to(position) * 0.2
		if (point - position).dot(forward) < -5.0:
			away -= 30.0
		if away > score and point.distance_to(position) > 15.0:
			score = away
			best = point
	return best

func _cruise_goal(position: Vector3, forward: Vector3) -> Vector3:
	var best := position
	var distance := INF
	for point in Layout.RING:
		var offset: Vector3 = point - position
		if offset.dot(forward) > 12.0 and offset.length() < distance:
			distance = offset.length()
			best = point
	return best

func _query_at(position: Vector3, forward: Vector3) -> Array[Dictionary]:
	_query.transform = Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)), position + Vector3.UP * (_size.y * 0.5 + 0.1))
	return _vehicle.get_world_3d().direct_space_state.intersect_shape(_query, 8)

func _scan(speed: float, steering: float) -> void:
	obstacle_gap = INF
	blocked_by = null
	var horizon := maxf(10.0, speed * speed / (2.0 * DECEL) + FOLLOW_GAP + speed * 0.5)
	# Check the actual near-term turn as well as the road ahead: a displaced car cannot see through its own deviation.
	var position := _vehicle.global_position
	var forward := -_vehicle.global_basis.z
	# Sample future footprints: the current inflated rear margin can overlap a
	# roadside object that the displaced chassis is already moving away from.
	for step in range(1, 6):
		var distance := step * 0.6
		var yaw := -tan(steering * MAX_STEER) / _wheelbase * distance
		var direction := forward.rotated(Vector3.UP, yaw)
		var at := position + forward.lerp(direction, 0.5).normalized() * distance
		for hit in _query_at(at, direction):
			if not _visible_obstacle(at, hit.collider):
				continue
			blocked_by = hit.collider
			_obstacle_position = at
			obstacle_gap = maxf(0.0, distance - BODY_CLEAR)
			return
	var distance := 1.0
	while distance <= horizon:
		var at: Vector3 = route.position_at(route_s + distance)
		var direction: Vector3 = route.direction_at(route_s + distance)
		for hit in _query_at(at, direction):
			if not _visible_obstacle(at, hit.collider):
				continue
			blocked_by = hit.collider
			_obstacle_position = at
			obstacle_gap = maxf(0.0, distance - BODY_CLEAR)
			return
		distance += 1.0

func _visible_obstacle(position: Vector3, body: Object) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(_vehicle.global_position + Vector3.UP, position + Vector3.UP, SENSOR_MASK, [_vehicle.get_rid()])
	var hit := _vehicle.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == body

func _rear_clear(forward: Vector3, distance: float) -> bool:
	var at := 0.0
	while at <= distance:
		var position := _vehicle.global_position - forward * (_size.z * 0.5 + 0.25 + at)
		_rear_query.transform = Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)), position + Vector3.UP * (_size.y * 0.5 + 0.1))
		if not _vehicle.get_world_3d().direct_space_state.intersect_shape(_rear_query, 1).is_empty():
			return false
		at += 0.4
	return true

func _reverse_step(delta: float, forward: Vector3) -> Dictionary:
	_reverse_time -= delta
	if _reverse_time <= 0.0 or _vehicle.global_position.distance_to(_reverse_start) >= REVERSE_DISTANCE:
		_reverse_time = 0.0
		_last_goal = Vector3(INF, INF, INF)
		_plan_in = 0.0
		return _stop(&"planning", &"reverse_complete")
	if not _rear_clear(forward, REVERSE_SPEED * delta + BODY_CLEAR):
		_reverse_time = 0.0
		return _stop(&"waiting", &"rear_blocked")
	var aim: Vector3 = route.position_at(route_s + 5.0)
	var side: float = (aim - _vehicle.global_position).dot(Route.right_of(forward))
	state = &"reversing"
	reason = &"stuck"
	var direction := signf(side) if absf(side) > 0.05 else 1.0
	return _command(REVERSE_SPEED, -direction * 0.8, true, aim)
