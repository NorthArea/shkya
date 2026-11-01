extends RefCounted
## Local steering only. Resident owns routes, world transforms and activity state.

const HORIZON := 1.1
const ACCELERATION := 3.5
const BRAKING := 6.0
const DODGE_SPEED := 1.65
const DODGE_OFFSET := 0.86
const MAX_OFFSET := 1.6
const STOP_REACTION := 0.20
const SIDE_COMMITMENT := 0.55
const ARRIVAL := 0.045
const CLEARANCE := 0.08

# End velocity for the steering ramp; callers observe resolved root displacement.
var velocity := Vector3.ZERO
var mode: StringName = &"following"
var threat_id := -1
var reaction: StringName = &""

var _unit_id: int
var _radius: float
var _stopped_for := 0.0
var _commit_left := 0.0
var _dodge_goal := Vector3.INF
var _dodge_landed := false
var _segment_goal := Vector3.INF

func _init(unit_id: int = 0, radius: float = 0.35) -> void:
	_unit_id = unit_id
	_radius = radius

func suspend() -> void:
	velocity = Vector3.ZERO
	mode = &"following"
	threat_id = -1
	reaction = &""
	_stopped_for = 0.0
	_commit_left = 0.0
	_dodge_goal = Vector3.INF
	_dodge_landed = false

func reset() -> void:
	suspend()
	_segment_goal = Vector3.INF

## Obstacles: id/unit_id, kind(peer/player/car), position, velocity, radius.
## Cars additionally supply an orthonormal basis and XZ half_extents.
## can_step(from, to) checks canonical solids and permitted walking ground.
func step(here: Vector3, segment_start: Vector3, goal: Vector3, cruise_speed: float,
		footprint_offsets: Array[Vector3], obstacles: Array[Dictionary], delta: float,
		can_step: Callable, allow_avoidance: bool = true) -> Vector3:
	if delta <= 0.0:
		return Vector3.ZERO
	here = _flat(here)
	segment_start = _flat(segment_start)
	goal = _flat(goal)
	if _segment_goal != goal:
		_dodge_goal = Vector3.INF
		_dodge_landed = false
		_stopped_for = 0.0
		_commit_left = 0.0
		mode = &"following"
		_segment_goal = goal
	_commit_left = maxf(0.0, _commit_left - delta)
	reaction = &""
	var to_goal := goal - here
	var distance := to_goal.length()
	if distance <= 0.00001 or cruise_speed <= 0.0:
		suspend()
		return Vector3.ZERO
	var preferred := to_goal.normalized() * minf(cruise_speed, distance / delta)
	var threat := _first_threat(here, preferred, footprint_offsets, obstacles, HORIZON) if allow_avoidance else {}
	threat_id = int(threat.get("id", -1))
	var wanted := preferred
	if not allow_avoidance:
		_dodge_goal = Vector3.INF
		_dodge_landed = false
		_stopped_for = 0.0
		mode = &"following"
	elif _dodge_goal != Vector3.INF:
		var toward_dodge := _dodge_goal - here
		if not _dodge_landed and toward_dodge.length() > ARRIVAL:
			mode = &"dodge"
			reaction = &"dodge"
			wanted = toward_dodge.normalized() * minf(DODGE_SPEED, toward_dodge.length() / delta)
		elif not threat.is_empty():
			_dodge_landed = true
			# Keep the achieved side clearance until a diagonal return is safe.
			var along := (goal - segment_start).normalized()
			var remaining := maxf(0.0, (goal - here).dot(along))
			var bypass := along * minf(cruise_speed, remaining / delta)
			if _first_threat(here, bypass, footprint_offsets, obstacles, HORIZON).is_empty():
				mode = &"dodge"
				wanted = bypass
			else:
				mode = &"stopped"
				reaction = &"cringe" if threat.kind == &"car" else &""
				wanted = Vector3.ZERO
				if _commit_left <= 0.0:
					_dodge_goal = Vector3.INF
					_dodge_landed = false
		else:
			_dodge_goal = Vector3.INF
			_dodge_landed = false
			mode = &"return"
	elif not threat.is_empty() and _must_yield(here, preferred, threat):
		_stopped_for += delta
		mode = &"yield"
		wanted = Vector3.ZERO
		if _can_dodge(preferred, threat) and distance > DODGE_OFFSET * 1.5:
			mode = &"stopped"
			reaction = &"cringe" if threat.kind == &"car" else &""
			if _stopped_for >= STOP_REACTION:
				var candidate := _choose_dodge(here, segment_start, goal, preferred,
					footprint_offsets, obstacles, threat, can_step)
				if candidate != Vector3.INF:
					_dodge_goal = candidate
					_dodge_landed = false
					_commit_left = SIDE_COMMITMENT
					mode = &"dodge"
					reaction = &"dodge"
					var toward := candidate - here
					wanted = toward.normalized() * minf(DODGE_SPEED, toward.length() / delta)
	else:
		_stopped_for = 0.0
		mode = &"return" if _segment_distance(here, segment_start, goal) > ARRIVAL else &"following"
	var acceleration := BRAKING if wanted.length_squared() < velocity.length_squared() else ACCELERATION
	var next_velocity := velocity.move_toward(wanted, acceleration * delta)
	var displacement := (velocity + next_velocity) * (delta * 0.5)
	# A longitudinal step may reach the endpoint, but a sidestep must finish first.
	if mode in [&"following", &"return"] and displacement.length() > distance:
		displacement = to_goal
	var accepted := _admissible(here, here + displacement, segment_start, goal,
		footprint_offsets, can_step)
	if accepted and allow_avoidance:
		accepted = _safe_motion(here, displacement / delta, footprint_offsets, obstacles, delta)
	if not accepted:
		velocity = Vector3.ZERO
		mode = &"stopped"
		# A commitment stabilizes a side choice; it cannot retain a blocked path.
		if _dodge_goal != Vector3.INF and _commit_left <= 0.0:
			_dodge_goal = Vector3.INF
			_dodge_landed = false
			_stopped_for = 0.0
		return Vector3.ZERO
	velocity = next_velocity
	return displacement

func _must_yield(here: Vector3, preferred: Vector3, obstacle: Dictionary) -> bool:
	if obstacle.kind != &"peer":
		return true
	var other_velocity: Vector3 = _flat(obstacle.velocity)
	if other_velocity.length_squared() < 0.01:
		return true
	var direction := preferred.normalized()
	if direction.dot(other_velocity.normalized()) > 0.65:
		return direction.dot(_flat(obstacle.position) - here) > 0.0
	return _unit_id > int(obstacle.unit_id)

func _can_dodge(preferred: Vector3, obstacle: Dictionary) -> bool:
	if obstacle.kind == &"car":
		return _flat(obstacle.velocity).length() > 0.5
	if obstacle.kind != &"peer":
		return false
	var other_velocity: Vector3 = _flat(obstacle.velocity)
	return other_velocity.length() < 0.1 or preferred.normalized().dot(other_velocity.normalized()) < -0.35

func _choose_dodge(here: Vector3, segment_start: Vector3, goal: Vector3, preferred: Vector3,
		footprints: Array[Vector3], obstacles: Array[Dictionary], threat: Dictionary,
		can_step: Callable) -> Vector3:
	var direction := preferred.normalized()
	var right := Vector3(-direction.z, 0.0, direction.x)
	var side := 1.0
	if threat.kind == &"car":
		var away := here - _flat(threat.position)
		side = 1.0 if away.dot(right) >= 0.0 else -1.0
	for sign_value: float in [side, -side]:
		var amount := DODGE_OFFSET
		if threat.kind == &"car":
			var car_basis: Basis = threat.basis
			var local_side := car_basis.orthonormalized().inverse() * (right * sign_value)
			var half: Vector2 = threat.half_extents
			var car_width := absf(local_side.x) * half.x + absf(local_side.z) * half.y
			for offset: Vector3 in footprints:
				var current_side := (here + offset - Vector3(threat.position)).dot(right * sign_value)
				amount = maxf(amount, car_width + _radius + CLEARANCE * 2.0 - current_side)
		var candidate := here + right * amount * sign_value
		if not _admissible(here, candidate, segment_start, goal, footprints, can_step):
			continue
		var duration := here.distance_to(candidate) / DODGE_SPEED
		var movement := (candidate - here) / duration
		if _safe_motion(here, movement, footprints, obstacles, duration):
			return candidate
	return Vector3.INF

func _admissible(here: Vector3, candidate: Vector3, segment_start: Vector3, goal: Vector3,
		footprints: Array[Vector3], can_step: Callable) -> bool:
	var old_offset := _segment_distance(here, segment_start, goal)
	var new_offset := _segment_distance(candidate, segment_start, goal)
	if new_offset > MAX_OFFSET and new_offset > old_offset + 0.0001:
		return false
	for offset: Vector3 in footprints:
		if not bool(can_step.call(here + offset, candidate + offset)):
			return false
	return true

func _first_threat(here: Vector3, intended: Vector3, footprints: Array[Vector3],
		obstacles: Array[Dictionary], horizon: float) -> Dictionary:
	var result: Dictionary = {}
	var soonest := INF
	for obstacle: Dictionary in obstacles:
		if int(obstacle.unit_id) == _unit_id:
			continue
		for offset: Vector3 in footprints:
			var time := _collision_time(here + offset, intended, obstacle, horizon)
			if time < soonest or (is_equal_approx(time, soonest) and not result.is_empty() and int(obstacle.id) < int(result.id)):
				soonest = time
				result = obstacle
	return result

func _safe_motion(here: Vector3, intended: Vector3, footprints: Array[Vector3],
		obstacles: Array[Dictionary], duration: float) -> bool:
	for obstacle: Dictionary in obstacles:
		if int(obstacle.unit_id) == _unit_id:
			continue
		for offset: Vector3 in footprints:
			var at := here + offset
			var before := _separation(at, obstacle)
			var after := _separation(at + intended * duration, obstacle, duration)
			# Existing overlap may separate; it must never trap an actor in place.
			if before <= 0.0 and after > before + 0.00001:
				continue
			if _collision_time(at, intended, obstacle, duration) != INF:
				return false
	return true

func _collision_time(at: Vector3, intended: Vector3, obstacle: Dictionary, horizon: float) -> float:
	var relative := _flat(at - Vector3(obstacle.position))
	var movement := _flat(intended - Vector3(obstacle.velocity))
	if obstacle.kind == &"car":
		var basis: Basis = obstacle.basis
		var local := basis.orthonormalized().inverse() * relative
		var local_motion := basis.orthonormalized().inverse() * movement
		var half: Vector2 = obstacle.half_extents
		return _rounded_box_time(Vector2(local.x, local.z), Vector2(local_motion.x, local_motion.z),
			half, _radius + CLEARANCE, horizon)
	var combined := _radius + float(obstacle.radius) + CLEARANCE
	return _circle_time(Vector2(relative.x, relative.z), Vector2(movement.x, movement.z), combined, horizon)

static func _circle_time(relative: Vector2, movement: Vector2, radius: float, horizon: float) -> float:
	var c := relative.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var a := movement.length_squared()
	if a <= 0.000001:
		return INF
	var b := relative.dot(movement)
	if b >= 0.0:
		return INF
	var discriminant := b * b - a * c
	if discriminant < 0.0:
		return INF
	var hit := (-b - sqrt(discriminant)) / a
	return hit if hit <= horizon else INF

static func _rounded_box_time(at: Vector2, movement: Vector2, half: Vector2, radius: float, horizon: float) -> float:
	if _box_time(at, movement, half + Vector2.ONE * radius, horizon) == INF:
		return INF
	# The circle/box Minkowski sum has flat edge strips and circular corners.
	var first := minf(_box_time(at, movement, half + Vector2(radius, 0.0), horizon),
		_box_time(at, movement, half + Vector2(0.0, radius), horizon))
	for x: float in [-half.x, half.x]:
		for y: float in [-half.y, half.y]:
			first = minf(first, _circle_time(at - Vector2(x, y), movement, radius, horizon))
	return first

func _separation(at: Vector3, obstacle: Dictionary, after: float = 0.0) -> float:
	var relative := _flat(at - Vector3(obstacle.position) - Vector3(obstacle.velocity) * after)
	if obstacle.kind == &"car":
		var basis: Basis = obstacle.basis
		var local := basis.orthonormalized().inverse() * relative
		var half: Vector2 = obstacle.half_extents
		var outside := Vector2(absf(local.x), absf(local.z)) - half
		return outside.max(Vector2.ZERO).length() + minf(maxf(outside.x, outside.y), 0.0) - _radius - CLEARANCE
	return relative.length() - _radius - float(obstacle.radius) - CLEARANCE

static func _box_time(at: Vector2, movement: Vector2, half: Vector2, horizon: float) -> float:
	var first := 0.0
	var last := horizon
	for axis in 2:
		if absf(movement[axis]) < 0.000001:
			if absf(at[axis]) > half[axis]:
				return INF
			continue
		var a := (-half[axis] - at[axis]) / movement[axis]
		var b := (half[axis] - at[axis]) / movement[axis]
		first = maxf(first, minf(a, b))
		last = minf(last, maxf(a, b))
		if first > last:
			return INF
	return first

static func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var nearest := Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z),
		Vector2(a.x, a.z), Vector2(b.x, b.z))
	return Vector2(point.x, point.z).distance_to(nearest)

static func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)
