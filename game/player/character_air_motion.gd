extends RefCounted
## CharacterBody3D owns velocity and collisions. This object proposes one motion
## step and reports action transitions; it never moves a node or selects a target.
## begin_step returns mean motion velocity; resolve_contacts supplies the one-shot
## vertical_correction that restores endpoint velocity after the resolved move.

const GRAVITY := 25.0
const FIRST_HEIGHT := 1.9
const SECOND_HEIGHT := 1.0
const SECOND_UP_SPEED := 2.0
const SECOND_DOWN_SPEED := 12.0
const AIR_STEER_RATE := 4.5
const STOMP_GRAVITY_FACTOR := 3.22
const LAUNCH_SECONDS := 0.08
const LAND_SECONDS := 0.18
const KICK_HIT_SECONDS := 0.12
const KICK_SECONDS := 0.40
const STOMP_ANTIC_SECONDS := 0.12

var phase: StringName = &"ground"
var action: StringName = &""
var jump_count := 0
var natural_fall := false
var _phase_seconds := 0.0
var _action_seconds := 0.0
var _air_attack_used := false
var _kick_hit_sent := false
var _was_airborne := false
var _awaiting_departure := false
var _takeoff_pending := false
var _hit_pending := false
var _vertical_correction := 0.0

func begin_step(delta: float, velocity: Vector3, grounded: bool, direction: Vector3, speed_limit: float, jump_pressed: bool, controls_allowed: bool = true) -> Vector3:
	if delta <= 0.0:
		return velocity
	_vertical_correction = 0.0
	if not controls_allowed:
		cancel()
		if not grounded:
			_begin_natural_fall()
			return _gravity_step(velocity, GRAVITY, delta)
		else:
			velocity.y = 0.0
		return velocity
	_phase_seconds += delta
	if grounded:
		if jump_pressed:
			_launch(1)
			velocity.y = sqrt(2.0 * GRAVITY * FIRST_HEIGHT)
			return _gravity_step(velocity, GRAVITY, delta)
		else:
			velocity.y = 0.0
			var moving_exit := action != &"stomp_land" and direction.length_squared() > 0.0001
			if phase == &"land" and (_phase_seconds >= LAND_SECONDS or moving_exit):
				phase = &"ground"
				action = &""
		return velocity
	_was_airborne = true
	_awaiting_departure = false
	if phase in [&"ground", &"land"]:
		_begin_natural_fall()
	if phase == &"launch" and _phase_seconds >= LAUNCH_SECONDS:
		phase = &"air"
	if jump_pressed and _can_jump_again(velocity.y):
		_launch(2)
		velocity.y = sqrt(2.0 * GRAVITY * SECOND_HEIGHT)
	if action == &"stomp_antic":
		_action_seconds += delta
		if _action_seconds < STOMP_ANTIC_SECONDS:
			return Vector3.ZERO
		var falling_delta := _action_seconds - STOMP_ANTIC_SECONDS
		action = &"stomp_air"
		_action_seconds = 0.0
		var acceleration := GRAVITY * STOMP_GRAVITY_FACTOR
		var mean_y := -0.5 * acceleration * falling_delta * falling_delta / delta
		_vertical_correction = -acceleration * falling_delta - mean_y
		return Vector3(0, mean_y, 0)
	if action == &"stomp_air":
		_action_seconds += delta
		return _gravity_step(Vector3(0, velocity.y, 0), GRAVITY * STOMP_GRAVITY_FACTOR, delta)
	if action == &"jump_kick":
		_action_seconds += delta
		if not _kick_hit_sent and _action_seconds >= KICK_HIT_SECONDS:
			_kick_hit_sent = true
			_hit_pending = true
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var input := Vector3(direction.x, 0, direction.z).limit_length(1.0)
	horizontal = (horizontal + input * input.length() * maxf(0.0, speed_limit) * AIR_STEER_RATE * delta).limit_length(maxf(0.0, speed_limit))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	return _gravity_step(velocity, GRAVITY, delta)

func request_air_attack(grounded: bool) -> StringName:
	if grounded or natural_fall or jump_count == 0 or _air_attack_used or phase not in [&"launch", &"air"]:
		return &""
	_air_attack_used = true
	_action_seconds = 0.0
	_kick_hit_sent = false
	action = &"stomp_antic" if jump_count == 2 else &"jump_kick"
	return action

func resolve_contacts(grounded: bool, ceiling: bool = false) -> Dictionary:
	var events := {"took_off": _takeoff_pending and not grounded, "air_hit": _hit_pending and not grounded,
		"landed": false, "stomp_landed": false, "ceiling": ceiling,
		"vertical_correction": 0.0 if grounded or ceiling else _vertical_correction}
	_takeoff_pending = false
	_hit_pending = false
	_vertical_correction = 0.0
	if grounded:
		if _was_airborne:
			var stomp := action in [&"stomp_antic", &"stomp_air"]
			events.landed = true
			events.stomp_landed = stomp
			phase = &"land"
			action = &"stomp_land" if stomp else &""
			_phase_seconds = 0.0
			_action_seconds = 0.0
			_clear_flight()
		elif _awaiting_departure:
			# A low ceiling or an obstructed launch may prevent leaving the floor.
			# It grants neither a midair jump nor a landing attack.
			phase = &"ground"
			action = &""
			_clear_flight()
	else:
		if phase in [&"ground", &"land"]:
			_begin_natural_fall()
		_was_airborne = true
		_awaiting_departure = false
	return events

func cancel() -> void:
	phase = &"ground"
	action = &""
	_phase_seconds = 0.0
	_action_seconds = 0.0
	_takeoff_pending = false
	_hit_pending = false
	_vertical_correction = 0.0
	_clear_flight()

func snapshot() -> Dictionary:
	var duration := LAND_SECONDS if phase == &"land" else KICK_SECONDS
	if action == &"stomp_antic":
		duration = STOMP_ANTIC_SECONDS
	var elapsed := _phase_seconds if phase == &"land" else _action_seconds
	return {"phase": phase, "action": action, "action_phase": clampf(elapsed / duration, 0.0, 1.0),
		"jump_count": jump_count, "natural_fall": natural_fall, "airborne": _was_airborne,
		"blocks_ground_motion": blocks_ground_motion()}

## The controller gates its ground acceleration/XZ velocity with this flag.
## A fresh jump is still admitted by begin_step during stomp recovery.
func blocks_ground_motion() -> bool:
	return phase == &"land" and action == &"stomp_land" and _phase_seconds < LAND_SECONDS

func _gravity_step(velocity: Vector3, acceleration: float, delta: float) -> Vector3:
	_vertical_correction = -0.5 * acceleration * delta
	velocity.y += _vertical_correction
	return velocity

func _launch(count: int) -> void:
	phase = &"launch"
	_phase_seconds = 0.0
	jump_count = count
	natural_fall = false
	_awaiting_departure = true
	_takeoff_pending = true
	if count == 1:
		action = &""
		_action_seconds = 0.0
		_air_attack_used = false
		_kick_hit_sent = false

func _can_jump_again(vertical_speed: float) -> bool:
	if natural_fall or jump_count != 1 or _air_attack_used:
		return false
	return vertical_speed <= SECOND_UP_SPEED if vertical_speed > 0.0 else absf(vertical_speed) <= SECOND_DOWN_SPEED

func _begin_natural_fall() -> void:
	phase = &"air"
	_was_airborne = true
	_phase_seconds = 0.0
	jump_count = 0
	natural_fall = true
	action = &""
	_action_seconds = 0.0
	_air_attack_used = false
	_kick_hit_sent = false

func _clear_flight() -> void:
	jump_count = 0
	natural_fall = false
	_air_attack_used = false
	_kick_hit_sent = false
	_was_airborne = false
	_awaiting_departure = false
