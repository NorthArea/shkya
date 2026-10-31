extends SceneTree
## PLAY-04: independent route-response oracle using real main and the unchanged canonical Driver.
## Initial checkpoint placement/yaw, Residents removal as STEALTH, and grace isolate movement.
## No route, Driver, controller, mask, shape, margin or camera-follow policy overrides.
## The ±0.75m lane bound is our control-quality requirement, not reconstructed original tuning or C7 acceptance.
const Materials = preload("res://game/world/materials.gd")
const EnvDress = preload("res://game/world/environment_dress.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const LANE_X := 59.5
const LANE_HALF_WIDTH := 0.75
const Driver = preload("res://tests/playthrough_driver.gd")
const Layout = preload("res://game/world/layout.gd")
const ROUTE := [Vector3(62, 0, -46), Vector3(59.5, 0, -40), Vector3(59.5, 0, 30)]

class Observer:
	extends Node
	signal stepped
	func _physics_process(_delta: float) -> void:
		stepped.emit()

var main: Node
var world: DemoWorld
var drv
var observer: Observer
var _active := false
var _variant := ""
var _leg := -1
var _target := Vector3.ZERO
var _previous := Vector3.ZERO
var _sample_count := 0
var _max_yaw_gap := 0.0
var _max_course_error := 0.0
var _min_x := INF
var _max_x := -INF
var _max_zero_run := 0
var _zero_run := 0
var _previous_colliders := ""
var _finished := false
var failures := 0
var checks := 0
var _lane_violations := 0
var _max_lane_deviation := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(150.0, true, false, true).timeout.connect(func():
		if not _finished:
			print("FAIL: PLAY04_ROUTE_RESPONSE watchdog")
			quit(2))
	observer = Observer.new()
	observer.process_physics_priority = 1000
	observer.stepped.connect(_sample)
	root.add_child(observer)
	print("PLAY04_ROUTE_RESPONSE_PROFILE ", JSON.stringify({"engine": Engine.get_version_info(),
		"physics_hz": Engine.physics_ticks_per_second, "args": OS.get_cmdline_args(),
		"player_sha256": FileAccess.get_sha256("res://game/player/ilyusha.gd"),
		"driver_sha256": FileAccess.get_sha256("res://tests/playthrough_driver.gd"),
		"wrapper_sha256": FileAccess.get_sha256(get_script().resource_path),
		"lane_x": LANE_X, "lane_half_width_m": LANE_HALF_WIDTH,
		"bound_kind": "our straight-route control quality; not original tuning or full C7 replacement",
		"scope": "real main; original first three complete-path points and 0.6 intermediate tolerance; Residents removed exactly as STEALTH; initial checkpoint/yaw only; grace isolates movement"}))
	check(Engine.physics_ticks_per_second == 60, "canonical 60 Hz profile")
	for starting_yaw in [0.0, PI]:
		await _variant_run(starting_yaw)
	_finished = true
	observer.stepped.disconnect(_sample)
	observer.queue_free()
	observer = null
	drv = null
	main = null
	world = null
	await process_frame
	await process_frame
	Materials.clear_cache()
	EnvDress.clear_cache()
	VehicleMesh.cache().clear()
	await process_frame
	print("PLAY04_ROUTE_RESPONSE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _variant_run(starting_yaw: float) -> void:
	_variant = "yaw_" + str(starting_yaw)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	await drv.frames(3)
	main.start_game()
	await drv.frames(10)
	world = main.world
	var residents := world.get_node_or_null("LevelGeometry/Residents")
	if residents:
		residents.free()
	world.stealth.grant_grace(120.0)
	world.player.place(Layout.STEALTH_CHECKPOINT, starting_yaw)
	world.camera_rig.yaw = starting_yaw
	world.camera_rig.snap()
	await drv.frames(2)
	for leg in ROUTE.size():
		_leg = leg
		_target = ROUTE[leg]
		_previous = world.player.global_position
		_sample_count = 0
		_max_yaw_gap = 0.0
		_max_course_error = 0.0
		_min_x = INF
		_max_x = -INF
		_max_zero_run = 0
		_zero_run = 0
		_previous_colliders = ""
		_lane_violations = 0
		_max_lane_deviation = 0.0
		if leg == 2:
			_record_lane(world.player.global_position.x)
		_active = true
		var reached: bool = await drv.walk_to(_target, 0.6)
		await drv.frames(1)
		_active = false
		print("PLAY04_ROUTE_RESPONSE_LEG ", JSON.stringify({"variant": _variant, "leg": _leg, "target": str(_target),
			"reached": reached, "error": drv.last_error, "position": str(world.player.global_position),
			"samples": _sample_count, "max_yaw_gap": _max_yaw_gap, "max_course_error": _max_course_error,
			"min_x": _min_x, "max_x": _max_x, "max_zero_run": _max_zero_run,
			"lane_violations": _lane_violations, "max_lane_deviation_m": _max_lane_deviation}))
		check(reached, _variant + " leg " + str(leg) + ": canonical Driver reaches unchanged intermediate target: " + drv.last_error)
		if leg == 2:
			check(_sample_count > 0 and _lane_violations == 0,
				_variant + ": every sampled position on the 70m straight leg stays within x59.5 ±0.75m; maximum deviation %.4fm" % _max_lane_deviation)
		if not reached:
			break
	drv.release_all()
	for type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player in main.find_children("*", type, true, false):
			player.stop()
	main.queue_free()
	drv = null
	main = null
	world = null
	await process_frame
	await process_frame
	Materials.clear_cache()
	EnvDress.clear_cache()
	await process_frame

func _sample() -> void:
	if not _active or not is_instance_valid(world):
		return
	_sample_count += 1
	var player := world.player
	var rig := world.camera_rig
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var actual_want := Vector3(input.x, 0, input.y).rotated(Vector3.UP, rig.input_yaw)
	var live_want := Vector3(input.x, 0, input.y).rotated(Vector3.UP, rig.yaw)
	var to := (_target - player.global_position).slide(Vector3.UP)
	var gap := wrapf(rig.input_yaw-rig.yaw, -PI, PI)
	var course_error := actual_want.signed_angle_to(to, Vector3.UP) if not actual_want.is_zero_approx() and not to.is_zero_approx() else 0.0
	_max_yaw_gap = maxf(_max_yaw_gap, absf(gap))
	_max_course_error = maxf(_max_course_error, absf(course_error))
	_min_x = minf(_min_x, player.global_position.x)
	_max_x = maxf(_max_x, player.global_position.x)
	if _leg == 2:
		_record_lane(player.global_position.x)
	var travel := (player.global_position-_previous).slide(Vector3.UP).length()
	_zero_run = _zero_run+1 if input.length() > 0.1 and travel < 0.0001 else 0
	_max_zero_run = maxi(_max_zero_run, _zero_run)
	_previous = player.global_position
	var contacts := []
	var collider_names := []
	for i in player.get_slide_collision_count():
		var hit := player.get_slide_collision(i)
		var collider := hit.get_collider()
		var path := str(collider.get_path()) if collider is Node else str(collider)
		if not path.ends_with("/Ground"):
			collider_names.append(path)
		contacts.append({"collider": path, "normal": str(hit.get_normal()), "point": str(hit.get_position())})
	var names := str(collider_names)
	if _sample_count % 120 == 1 or names != _previous_colliders or _zero_run == 3 or _zero_run == 100:
		print("PLAY04_ROUTE_RESPONSE_TRACE ", JSON.stringify({"variant": _variant, "leg": _leg,
			"frame": Engine.get_physics_frames(), "position": str(player.global_position), "velocity": str(player.velocity),
			"target": str(_target), "distance": to.length(), "input": str(input),
			"basis_input": str(player.get("_basis_input")), "yaw": rig.yaw, "input_yaw": rig.input_yaw,
			"yaw_gap": gap, "actual_want": str(actual_want), "live_want": str(live_want), "course_error": course_error,
			"travel": travel, "zero_run": _zero_run, "floor": player.is_on_floor(), "wall": player.is_on_wall(),
			"enabled": player.input_enabled, "hide": str(player.hide_mode), "contacts": contacts}))
	_previous_colliders = names

func _record_lane(x: float) -> void:
	var deviation := absf(x-LANE_X)
	_max_lane_deviation = maxf(_max_lane_deviation, deviation)
	if deviation > LANE_HALF_WIDTH:
		_lane_violations += 1

func check(ok: bool, label: String) -> bool:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + "PLAY04_ROUTE_RESPONSE " + label)
	if not ok:
		failures += 1
	return ok
