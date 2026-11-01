extends SceneTree
## PLAY-04: independent on-foot baseline on main -> DemoWorld -> real Input/controller/camera.
## Run: tools/godot.sh --headless --path . --script tools/play04_measure.gd -- --skip-intro
## Optional --trace emits every post-physics sample as JSON. No original numeric tune is assumed.
## C++ principles: 3UR c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6,
## character.cpp:1679/1830 UpdateDesiredDirAndSpeed: squared input;
## action.cpp:183/220/258 WalkerLocomotionAction:
## scalar desired speed / facing; JumpAction::DoSimulation: additive air control,
## no release braking (action.cpp:1744); walkercam.cpp:614/935: jump camera stabilization.

const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump"]
const SETTLE_SECONDS := 0.2
const RUNUP_SECONDS := 0.45
const STEADY_SECONDS := 0.6
const STOP_SECONDS := 0.8
const TURN_SECONDS := 0.6
const AIR_SWITCH_SECONDS := 0.12
const AIR_PROBE_SECONDS := 0.2
const FLIGHT_BUDGET_SECONDS := 3.0
const SPEED_EPSILON := 0.01 # m/s; measurement resolution, not original tuning

class PostPhysics:
	extends Node
	signal stepped
	func _physics_process(_delta: float) -> void:
		stepped.emit()

var main: Node
var world: DemoWorld
var player: Ilyusha
var rig: CameraRig
var observer: PostPhysics
var invalid: Array[String] = []
var trace_enabled := false
var dt := 0.0
var measurements: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	trace_enabled = "--trace" in OS.get_cmdline_user_args()
	dt = 1.0 / Engine.physics_ticks_per_second
	create_timer(90.0, true, false, true).timeout.connect(func():
		push_error("PLAY04_MEASURE: watchdog exceeded 90 simulated seconds")
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
	player = world.player
	rig = world.camera_rig
	_emit("profile", {
		"source": "3UR/Simpsons-Hit-Run@c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6",
		"original_loaded_tune": "unknown; no numeric original oracle",
		"engine": Engine.get_version_info(), "physics_hz": Engine.physics_ticks_per_second,
		"units": "position m; velocity m/s; time simulation s; angles rad; FOV deg",
		"sample_order": "observer priority 1000, after real player/camera physics",
		"location": "Layout.SPAWN, north-facing; same real world, no disabled participants",
		"setup": "place() and camera follow/snap only before scenario; no velocity assignment",
		"player_sha256": FileAccess.get_sha256("res://game/player/ilyusha.gd"),
		"camera_sha256": FileAccess.get_sha256("res://game/camera/camera_rig.gd"),
		"project_sha256": FileAccess.get_sha256("res://project.godot"),
		"measurement_sha256": FileAccess.get_sha256("res://tools/play04_measure.gd"),
		"walk_limit": player.speed_limit(), "engine_gravity": player.get_gravity().length(),
		"air_motion_sha256": FileAccess.get_sha256("res://game/player/character_air_motion.gd"),
		"camera_profile": rig.PROFILES[&"on_foot"], "keep_aspect": rig.camera.keep_aspect,
		"viewport": _v2(root.get_visible_rect().size),
		"windows_s": {"settle": SETTLE_SECONDS, "runup": RUNUP_SECONDS,
			"steady": STEADY_SECONDS, "turn": TURN_SECONDS, "stop": STOP_SECONDS,
			"air_switch": AIR_SWITCH_SECONDS, "air_probe": AIR_PROBE_SECONDS},
		"action_deadzones": _deadzones(),
	})
	await _ground_speed()
	await _turn(&"move_right", "turn90")
	await _turn(&"move_back", "turn180")
	for mode in ["hold", "release", "reverse", "standing"]:
		await _jump(mode)
	_release()
	_emit("summary", {"invalid_measurements": invalid, "status": "MEASURED" if invalid.is_empty() else "INVALID",
		"scope": "on-foot baseline only; no original feel, visual acceptance, roof/stealth/mission acceptance"})
	var property_failures := _assess()
	await _finish(0 if invalid.is_empty() and property_failures == 0 else 1)

## Baseline provider has no behavioural acceptance oracle. Independent test overrides this hook.
func _assess() -> int:
	return 0

func _finish(exit_code: int) -> void:
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	main.queue_free()
	await _ticks(5)
	player = null
	rig = null
	world = null
	main = null
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	OS.delay_msec(100)
	await process_frame
	quit(exit_code)

func _reset() -> void:
	_release()
	player.place(Layout.SPAWN, 0.0)
	rig.yaw = 0.0
	rig.follow(player, &"on_foot")
	rig.apply_mouse(Vector2.ZERO)
	await _ticks(_count(SETTLE_SECONDS))
	_require(player.is_on_floor(), "reset: on floor")
	_require(world.control_mode == &"on_foot" and player.input_enabled, "reset: real on-foot input enabled")
	_require(not world.ui_blocking and not world.is_stealth_failing(), "reset: UI/stealth do not block input")

func _ground_speed() -> void:
	var full := 0.0
	for strength in [1.0, 0.5, 0.75]:
		await _reset()
		Input.action_press(&"move_forward", strength)
		var effective := _input().length()
		var run := await _record("ground_%.2f" % strength, STEADY_SECONDS)
		var steady := _mean_speed(run, run.size() - mini(6, run.size()))
		if strength == 1.0:
			full = steady
		var reach90: Variant = _first_speed_time(run, steady * 0.9, true)
		var release_position := player.global_position
		Input.action_release(&"move_forward")
		var stopped := await _record("stop_%.2f" % strength, STOP_SECONDS)
		_emit("ground", {"strength_raw": strength, "strength_effective": effective,
			"steady_mps": steady, "fraction_of_full": steady / maxf(full, SPEED_EPSILON),
			"nonlinear_below_linear": steady / maxf(full, SPEED_EPSILON) < effective - SPEED_EPSILON if strength < 1.0 else null,
			"t90_s": reach90, "stop_s": _first_speed_time(stopped, SPEED_EPSILON, false),
			"stop_distance_m": _planar(player.global_position - release_position).length()})

func _turn(action: StringName, label: String) -> void:
	await _reset()
	Input.action_press(&"move_forward")
	await _record(label + "_runup", RUNUP_SECONDS)
	var before := _sample()
	Input.action_release(&"move_forward")
	Input.action_press(action)
	var samples := await _record(label, TURN_SECONDS)
	var minimum := INF
	var maximum := 0.0
	var maximum_facing_motion := 0.0
	for s: Dictionary in samples:
		minimum = minf(minimum, s.speed)
		maximum = maxf(maximum, s.speed)
		if s.speed > SPEED_EPSILON:
			maximum_facing_motion = maxf(maximum_facing_motion, absf(angle_difference(s.facing, s.motion)))
	_emit(label, {"entry_speed_mps": before.speed, "entry_facing_rad": before.facing,
		"min_speed_mps": minimum, "max_speed_mps": maximum,
		"min_speed_ratio": minimum / maxf(before.speed, SPEED_EPSILON),
		"first_speed_mps": samples[0].speed, "first_facing_rad": samples[0].facing,
		"first_motion_rad": samples[0].motion, "max_facing_motion_gap_rad": maximum_facing_motion,
		"final": samples.back(), "input_direction_uses_actual_camera_yaw": true})

func _jump(mode: String) -> void:
	await _reset()
	if mode != "standing":
		Input.action_press(&"move_forward")
		await _record(mode + "_runup", RUNUP_SECONDS)
	var origin := player.global_position
	var camera_y := rig.camera.global_position.y
	var pivot_y := rig.global_position.y
	var before := _sample()
	Input.action_press(&"jump")
	await observer.stepped
	Input.action_release(&"jump")
	_require(not player.is_on_floor() and player.velocity.y > 0.0, mode + ": actual jump took off")
	var samples: Array[Dictionary] = [_sample()]
	var switch_at := maxi(1, _count(AIR_SWITCH_SECONDS))
	var probe_at := switch_at + _count(AIR_PROBE_SECONDS)
	var switch_sample: Dictionary = {}
	var probe_sample: Dictionary = {}
	var first_after_switch: Dictionary = {}
	var landed := false
	for i in range(1, _count(FLIGHT_BUDGET_SECONDS)):
		if i == switch_at:
			switch_sample = _sample()
			if mode in ["release", "reverse"]:
				Input.action_release(&"move_forward")
			if mode == "reverse":
				Input.action_press(&"move_back")
		await observer.stepped
		var sample := _sample()
		samples.append(sample)
		_validate_contacts("jump_" + mode)
		if i == switch_at:
			first_after_switch = sample
		if i == probe_at:
			probe_sample = sample
		if player.is_on_floor():
			landed = true
			break
	_require(landed, mode + ": landed within budget")
	_require(not switch_sample.is_empty() and not probe_sample.is_empty(), mode + ": jump lasted through configured air probe")
	var apex := 0.0
	var apex_t := 0.0
	var camera_rise := 0.0
	var pivot_rise := 0.0
	var maximum_speed := 0.0
	for i in samples.size():
		var s := samples[i]
		if s.position[1] - origin.y > apex:
			apex = s.position[1] - origin.y
			apex_t = (i + 1) * dt
		camera_rise = maxf(camera_rise, absf(s.camera_y - camera_y))
		pivot_rise = maxf(pivot_rise, absf(s.pivot_y - pivot_y))
		maximum_speed = maxf(maximum_speed, s.speed)
	_emit("jump_" + mode, {"entry": before, "apex_m": apex, "apex_s": apex_t,
		"flight_s": samples.size() * dt, "range_m": _planar(player.global_position - origin).length(),
		"camera_vertical_excursion_m": camera_rise, "pivot_vertical_excursion_m": pivot_rise,
		"camera_to_jump_excursion_ratio": camera_rise / maxf(apex, SPEED_EPSILON),
		"switch": switch_sample, "probe": probe_sample, "first_after_switch": first_after_switch,
		"probe_elapsed_s": (probe_at - switch_at + 1) * dt,
		"max_speed_mps": maximum_speed,
		"probe_airborne": not probe_sample.get("floor", true),
		"release_speed_ratio": float(probe_sample.get("speed", 0.0)) / maxf(float(switch_sample.get("speed", 0.0)), SPEED_EPSILON) if mode == "release" else null,
		"landing": samples.back()})
	if trace_enabled:
		for i in samples.size():
			_emit("trace", {"scenario": "jump_" + mode, "t_s": (i + 1) * dt, "sample": samples[i]})

func _record(label: String, seconds: float) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for i in _count(seconds):
		await observer.stepped
		var s := _sample()
		samples.append(s)
		_validate_contacts(label)
		if trace_enabled:
			_emit("trace", {"scenario": label, "t_s": (i + 1) * dt, "sample": s})
	return samples

func _sample() -> Dictionary:
	var v := _planar(player.velocity)
	return {"position": _v3(player.global_position), "velocity": _v3(player.velocity),
		"speed": v.length(), "facing": atan2(-player.facing_dir().x, -player.facing_dir().z),
		"motion": atan2(-v.x, -v.z) if v.length() > SPEED_EPSILON else 0.0,
		"floor": player.is_on_floor(), "input": _v2(_input()), "input_yaw": rig.input_yaw,
		"camera_y": rig.camera.global_position.y, "pivot_y": rig.global_position.y,
		"camera_yaw": rig.yaw, "fov": rig.camera.fov}

func _mean_speed(samples: Array[Dictionary], start: int) -> float:
	var total := 0.0
	for i in range(start, samples.size()):
		total += float(samples[i].speed)
	return total / maxi(1, samples.size() - start)

func _first_speed_time(samples: Array[Dictionary], threshold: float, above: bool) -> Variant:
	for i in samples.size():
		if ((samples[i].speed >= threshold) if above else (samples[i].speed <= threshold)):
			return (i + 1) * dt
	return null

func _validate_contacts(label: String) -> void:
	for c in player.get_slide_collision_count():
		_require(player.get_slide_collision(c).get_normal().y > 0.9, label + ": non-floor contact contaminates measurement")

func _input() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")

func _deadzones() -> Dictionary:
	var result := {}
	for action in ACTIONS:
		result[action] = InputMap.action_get_deadzone(action)
	return result

func _count(seconds: float) -> int:
	return maxi(1, ceili(seconds / dt))

func _ticks(count: int) -> void:
	for i in count:
		await observer.stepped

func _release() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func _require(condition: bool, label: String) -> void:
	if not condition and label not in invalid:
		invalid.append(label)
		push_error("PLAY04_MEASURE INVALID: " + label)

func _emit(kind: String, value: Dictionary) -> void:
	if kind == "ground":
		if not measurements.has(kind):
			measurements[kind] = []
		measurements[kind].append(value)
	elif kind != "trace":
		measurements[kind] = value
	print("PLAY04_MEASURE ", kind, " ", JSON.stringify(value))

func _planar(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _v2(v: Vector2) -> Array:
	return [v.x, v.y]
