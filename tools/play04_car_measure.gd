extends SceneTree
## PLAY-04 independent real Input -> main/DemoWorld -> Lada measurement.
## tools/godot.sh --headless --path . --script tools/play04_car_measure.gd -- --skip-intro
## Optional --trace prints every post-physics sample. This is NOT an original numeric tune oracle.
## Source: 3UR/Simpsons-Hit-Run@c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6:
## humanvehiclecontroller.cpp:105-119: independent analog Gas/Brake;
## vehicle.cpp:1461/1489: separate pedals, speed-dependent brake restriction;
## vehicle.cpp:1764-1828: bounded steering input change per dt, finite arrival.
## Our limited contract may preserve current full braking instead of importing that restriction.
## No source/asset vehicle tune is known; no dynamics model is reproduced here.

const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const ACTIONS := [&"move_left", &"move_right", &"car_gas", &"car_brake", &"handbrake"]
const SETTLE_SECONDS := 0.2
const RUNUP_SECONDS := 2.0
const PEDAL_SECONDS := 1.0
const TRANSITION_SECONDS := 2.0
const REVERSE_RUNUP_SECONDS := 1.1
const REVERSE_SECONDS := 1.5
const STEER_SECONDS := 0.65
const MOVING_RUNUP_SECONDS := 0.7
const MOVING_STEER_SECONDS := 0.3
const SPEED_EPSILON := 0.01 # measurement resolution, not loaded H&R tune
const FIXTURE_LIFT_M := 1000.0 # traffic/residents relocation, not game geometry

class PostPhysics:
	extends Node
	signal stepped
	func _physics_process(_delta: float) -> void:
		stepped.emit()

var main: Node
var world: DemoWorld
var car: Lada
var observer: PostPhysics
var invalid: Array[String] = []
var measurements: Dictionary = {}
var trace_enabled := false
var dt := 0.0
var origin := Vector3.ZERO
var road := Rect2()
var fixture_nodes: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	trace_enabled = "--trace" in OS.get_cmdline_user_args()
	dt = 1.0 / Engine.physics_ticks_per_second
	create_timer(90.0, true, false, true).timeout.connect(func():
		push_error("PLAY04_CAR_MEASURE: watchdog exceeded 90 simulated seconds")
		quit(2))
	observer = PostPhysics.new()
	observer.process_physics_priority = 1000
	root.add_child(observer)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _ticks(2)
	main.start_game()
	await _ticks(10)
	world = main.world
	car = world.car
	_require(car.get_script().resource_path == "res://game/vehicles/lada.gd", "default Lada, no raycar")
	for surface: Array in Layout.SURFACES:
		if surface[0] == "Street_B":
			road = Rect2(surface[2] - surface[3] * 0.5, surface[3])
	_require(road.has_area(), "Street B exists in canonical Layout")
	# Midpoint of the straight between south street end and south edge of C7 square.
	origin = Vector3(road.get_center().x, 0.0, (road.end.y + Layout.KIOSK_SQUARE.end.y) * 0.5)
	for path in ["LevelGeometry/Traffic", "LevelGeometry/Residents"]:
		var participant := world.get_node_or_null(path) as Node3D
		_require(participant != null, "fixture participant exists: " + path)
		if participant:
			participant.process_mode = Node.PROCESS_MODE_DISABLED
			participant.position.y += FIXTURE_LIFT_M
			fixture_nodes.append(path)
	world.enter_car()
	await _ticks(3)
	var deadzones := {}
	for action in ACTIONS:
		deadzones[action] = InputMap.action_get_deadzone(action)
	_emit("profile", {
		"source": "3UR/Simpsons-Hit-Run@c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6",
		"original_loaded_tune": "unknown; no original numeric oracle or feel acceptance",
		"engine": Engine.get_version_info(), "physics_hz": Engine.physics_ticks_per_second,
		"units": "m; m/s; simulation s; yaw rad; steer normalized input units",
		"sample_order": "observer priority 1000 after real Lada physics",
		"fixture": "street B south of kiosk; traffic/residents disabled and lifted; remaining world active",
		"fixture_nodes": fixture_nodes, "fixture_lift_m": FIXTURE_LIFT_M,
		"origin": _v3(origin), "setup": "reset_to only before scenarios; acceleration via real Input only",
		"car_sha256": FileAccess.get_sha256("res://game/vehicles/lada.gd"),
		"project_sha256": FileAccess.get_sha256("res://project.godot"),
		"layout_sha256": FileAccess.get_sha256("res://game/world/layout.gd"),
		"measurement_sha256": FileAccess.get_sha256("res://tools/play04_car_measure.gd"),
		"limits": {"forward_mps": car.MAX_SPEED, "reverse_mps": car.MAX_REVERSE,
			"full_accel_mps2": car.ACCELERATION, "full_brake_mps2": car.BRAKE},
		"preserved_handling": {"roll_drag": car.ROLL_DRAG, "air_drag": car.AIR_DRAG,
			"handbrake": car.HANDBRAKE, "handbrake_turn": car.HANDBRAKE_TURN,
			"grip": car.GRIP, "handbrake_grip": car.HANDBRAKE_GRIP,
			"turn_low": car.TURN_RATE_LOW, "turn_high": car.TURN_RATE_HIGH,
			"turn_full_at": car.TURN_FULL_AT},
		"action_deadzones": deadzones,
		"windows_s": {"settle": SETTLE_SECONDS, "runup": RUNUP_SECONDS, "pedal": PEDAL_SECONDS,
			"transition": TRANSITION_SECONDS, "steer": STEER_SECONDS,
			"moving_runup": MOVING_RUNUP_SECONDS, "moving_steer": MOVING_STEER_SECONDS}})
	for strength in [1.0, 0.5, 0.75]:
		await _reset()
		_pedals(strength, 0.0)
		await _record("gas_%.2f" % strength, RUNUP_SECONDS)
	for mode in ["coast", "brake_full", "brake_half", "brake_quarter", "brake_tenth", "both_full", "gas_half_brake_full"]:
		await _reset()
		_pedals(1.0, 0.0)
		await _record(mode + "_runup", RUNUP_SECONDS)
		match mode:
			"coast": _pedals(0.0, 0.0)
			"brake_full": _pedals(0.0, 1.0)
			"brake_half": _pedals(0.0, 0.5)
			"brake_quarter": _pedals(0.0, 0.25)
			"brake_tenth": _pedals(0.0, 0.1)
			"both_full": _pedals(1.0, 1.0)
			"gas_half_brake_full": _pedals(0.5, 1.0)
		await _record(mode, PEDAL_SECONDS)
	await _reset()
	_pedals(1.0, 0.0)
	await _record("forward_to_reverse_runup", RUNUP_SECONDS)
	_pedals(0.0, 1.0)
	await _record("forward_to_reverse", TRANSITION_SECONDS)
	await _reset()
	_pedals(0.0, 1.0)
	await _record("reverse_full", REVERSE_SECONDS)
	await _reset()
	_pedals(0.0, 1.0)
	await _record("reverse_to_forward_runup", REVERSE_RUNUP_SECONDS)
	_pedals(1.0, 0.0)
	await _record("reverse_to_forward", TRANSITION_SECONDS)
	await _reset()
	_pedals(0.0, 1.0)
	await _record("reverse_both_runup", REVERSE_RUNUP_SECONDS)
	_pedals(1.0, 1.0)
	await _record("reverse_both", PEDAL_SECONDS)
	# Stationary wheel response isolates the input limiter from yaw/slip/snow dynamics.
	for sign_value in [1.0, -1.0]:
		await _reset()
		_steering(sign_value)
		var prefix := "stationary_left" if sign_value > 0.0 else "stationary_right"
		await _record(prefix, STEER_SECONDS)
		_steering(-sign_value)
		await _record(prefix + "_reverse", STEER_SECONDS)
		_steering(0.0)
		await _record(prefix + "_release", STEER_SECONDS)
	for reverse in [false, true]:
		await _reset()
		_pedals(0.0 if reverse else 1.0, 1.0 if reverse else 0.0)
		var prefix := "moving_reverse" if reverse else "moving_forward"
		await _record(prefix + "_runup", MOVING_RUNUP_SECONDS)
		_steering(1.0)
		await _record(prefix + "_left", MOVING_STEER_SECONDS)
		_steering(-1.0)
		await _record(prefix + "_right", MOVING_STEER_SECONDS)
	_release()
	_emit("summary", {"invalid_measurements": invalid,
		"status": "MEASURED" if invalid.is_empty() else "INVALID",
		"scope": "isolated input/pedal/steering response only; full-speed cap not reached; no traffic, snow, collisions, C4 exit, visual or manual feel acceptance"})
	var failures := _assess()
	await _finish(0 if invalid.is_empty() and failures == 0 else 1)

## Measurement provider has no behavioural oracle. Independent test overrides this hook.
func _assess() -> int:
	return 0

func _reset() -> void:
	_release()
	car.reset_to(origin, 0.0)
	world.camera_rig.yaw = 0.0
	world.camera_rig.follow(car, &"in_car")
	await _ticks(_count(SETTLE_SECONDS))
	_validate("reset")
	_require(_sample().speed <= SPEED_EPSILON, "reset: at rest")

func _record(label: String, seconds: float) -> Dictionary:
	var entry := _sample()
	var samples: Array[Dictionary] = []
	var maximum_rate := 0.0
	var previous_steer: float = entry.steer
	var minimum_speed: float = entry.forward_speed
	var maximum_speed: float = entry.forward_speed
	var stopped_at: Variant = null
	var crossed_at: Variant = null
	var settled_at: Variant = null
	var previous_position := _position(entry)
	var path_length := 0.0
	for i in _count(seconds):
		await observer.stepped
		var sample := _sample()
		samples.append(sample)
		_validate(label)
		maximum_rate = maxf(maximum_rate, absf(sample.steer - previous_steer) / dt)
		previous_steer = sample.steer
		minimum_speed = minf(minimum_speed, sample.forward_speed)
		maximum_speed = maxf(maximum_speed, sample.forward_speed)
		var position_now := _position(sample)
		path_length += position_now.distance_to(previous_position)
		previous_position = position_now
		if stopped_at == null and sample.speed <= SPEED_EPSILON:
			stopped_at = (i + 1) * dt
		if crossed_at == null and absf(entry.forward_speed) > SPEED_EPSILON and sample.forward_speed * entry.forward_speed < 0.0:
			crossed_at = (i + 1) * dt
		if settled_at == null and is_equal_approx(float(sample.steer), float(sample.steer_input)):
			settled_at = (i + 1) * dt
		if trace_enabled:
			print("PLAY04_CAR_MEASURE trace ", JSON.stringify({"scenario": label, "t_s": (i + 1) * dt, "sample": sample}))
	var result := {"entry": entry, "first": samples[0], "final": samples.back(),
		"duration_s": samples.size() * dt, "min_forward_mps": minimum_speed,
		"max_forward_mps": maximum_speed, "maximum_steer_rate_units_s": maximum_rate,
		"first_steer_step": samples[0].steer - entry.steer, "stop_s": stopped_at,
		"first_deceleration_mps2": (entry.forward_speed - samples[0].forward_speed) / dt,
		"steer_settle_s": settled_at,
		"direction_cross_s": crossed_at,
		"displacement_m": _position(samples.back()).distance_to(_position(entry)),
		"path_length_m": path_length,
		"yaw_change_rad": angle_difference(entry.yaw, samples.back().yaw)}
	_emit(label, result)
	# Retain actual samples for properties; concise output above, full output under --trace.
	measurements[label]["samples"] = samples
	return result

func _sample() -> Dictionary:
	var planar := Vector3(car.velocity.x, 0.0, car.velocity.z)
	return {"position": _v3(car.global_position), "velocity": _v3(car.velocity),
		"speed": planar.length(), "forward_speed": planar.dot(-car.global_basis.z),
		"lateral_speed": car.lateral_speed, "yaw": car.global_rotation.y,
		"steer": car.get("_steer_now"), "braking": car.braking,
		"floor": car.is_on_floor(), "snow_depth": car.snow_depth, "airborne": car.airborne,
		"gas_input": Input.get_action_strength(&"car_gas"),
		"brake_input": Input.get_action_strength(&"car_brake"),
		"steer_input": Input.get_axis(&"move_right", &"move_left")}

func _validate(label: String) -> void:
	_require(world.control_mode == &"in_car" and car.driver == world.player,
		label + ": real C4 car mode/driver retained")
	_require(not world.player.input_enabled and not world.player.visible,
		label + ": on-foot input inactive")
	_require(not world.ui_blocking and not world.is_stealth_failing() and not car.exit_requested,
		label + ": no UI/stealth/exit override")
	_require(world.stealth.suspicion == 0.0, label + ": no C7 detection interference")
	_require(car.is_on_floor() and not car.airborne, label + ": grounded")
	_require(car.snow_depth == 0.0 and car.snow_lift == 0.0, label + ": snow-free road")
	_require(car.impacts == 0, label + ": no impact bounce")
	var p := Vector2(car.global_position.x, car.global_position.z)
	_require(road.has_point(p) and p.y > Layout.KIOSK_SQUARE.end.y,
		label + ": retained street B south of kiosk fixture")
	for i in car.get_slide_collision_count():
		_require(car.get_slide_collision(i).get_normal().y > 0.9,
			label + ": non-floor physical contact contaminates measurement")

func _pedals(gas: float, brake: float) -> void:
	Input.action_release(&"car_gas")
	Input.action_release(&"car_brake")
	if gas > 0.0:
		Input.action_press(&"car_gas", gas)
	if brake > 0.0:
		Input.action_press(&"car_brake", brake)

func _steering(value: float) -> void:
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	if value > 0.0:
		Input.action_press(&"move_left", value)
	elif value < 0.0:
		Input.action_press(&"move_right", -value)

func _release() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func _ticks(count: int) -> void:
	for i in count:
		await observer.stepped

func _count(seconds: float) -> int:
	return maxi(1, ceili(seconds / dt))

func _position(sample: Dictionary) -> Vector3:
	return Vector3(sample.position[0], sample.position[1], sample.position[2])

func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _require(condition: bool, label: String) -> void:
	if not condition and label not in invalid:
		invalid.append(label)
		push_error("PLAY04_CAR_MEASURE INVALID: " + label)

func _emit(kind: String, value: Dictionary) -> void:
	measurements[kind] = value
	print("PLAY04_CAR_MEASURE ", kind, " ", JSON.stringify(value))

func _finish(exit_code: int) -> void:
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	main.queue_free()
	await _ticks(5)
	car = null
	world = null
	main = null
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	OS.delay_msec(100)
	await process_frame
	quit(exit_code)
