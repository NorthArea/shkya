extends SceneTree
## Замер FPS: машина проезжает ROUTE_DRIVE со скоростью ~50 км/ч, камера преследования, полный рендер.
## make fps → среднее, медиана, 1% худших кадров. Результат печатается строкой FPS:.

const Layout = preload("res://game/world/layout.gd")
const SPEED := 14.0
const WARMUP_FRAMES := 90

var _env_fixture: Array = []
var _original_fixture: Array = []
var _report := {}
var _last_sample_tick := 0
var _report_write_failed := false
var _physics_phase_start_tick := 0
var _physics_phase_steps := 0
var _draw_started_tick := 0
var _draw_wall_us := 0
var _process_started_tick := 0
var _update_wall_us := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if Engine.time_scale != 1.0 or OS.get_environment("GODOT_FIXED_FPS_WORKLOAD") == "1":
		push_error("FPS workload requires real time (no fixed-fps or altered time_scale)")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN: native renderer required; visible checks need explicit owner authorization")
		quit(2)
		return
	var started := Time.get_ticks_usec()
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if "--motion" in OS.get_cmdline_user_args():
		await _run_motion(main, started)
		return
	main.start_game()
	for i in 5:
		await process_frame
	var world: DemoWorld = main.world
	world.enter_car()
	var car: Lada = world.car
	var break_env := "--break-env" in OS.get_cmdline_user_args()
	if break_env and not await _prepare_break_env(world):
		await _abort_setup(main)
		return
	var times: Array[float] = []
	var route := Layout.ROUTE_DRIVE
	var segment := 1
	var position := route[0]
	var frame := 0
	var last := Time.get_ticks_usec()
	while segment < route.size():
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1_000_000.0
		last = now
		frame += 1
		if frame > WARMUP_FRAMES:
			times.append(dt)
		var target := route[segment]
		var step := SPEED * minf(dt, 0.05)
		var to_target := target - position
		if to_target.length() <= step:
			position = target
			segment += 1
		else:
			position += to_target.normalized() * step
		var yaw := atan2(-to_target.x, -to_target.z)
		car.reset_to(position, yaw)
		world.camera_rig.yaw = yaw
	if break_env and not _verify_break_env(world):
		await _abort_setup(main)
		return
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	var count := times.size()
	var average := count / total
	var median := 1.0 / times[count / 2]
	var worst := times.slice(int(count * 0.99))
	var worst_total := 0.0
	for t in worst:
		worst_total += t
	var low := worst.size() / worst_total
	var size := root.get_visible_rect().size
	print("FPS: average %.1f, median %.1f, 1%% low %.1f, frames %d, viewport %dx%d, %s, %s" % [average, median, low, count, size.x, size.y, RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()])
	main.queue_free()
	for i in 5:
		await process_frame
	quit(0)

## Raw wall intervals, never an average of instantaneous FPS. A single hitch fails
## this sampled target; passing a short scenario does not accept the whole game.
static func frame_stats(intervals_us: Array, target_fps: int) -> Dictionary:
	var values: Array[float] = []
	var invalid := 0
	var over := 0
	var total := 0.0
	var budget := 1_000_000.0 / maxi(target_fps, 1)
	for interval: Variant in intervals_us:
		var value := float(interval)
		if value <= 0.0 or not is_finite(value):
			invalid += 1
			continue
		values.append(value)
		total += value
		if value > budget:
			over += 1
	values.sort()
	var n := values.size()
	if n == 0:
		return {"frames": 0, "invalid_frames": invalid, "target_met": false}
	return {"frames": n, "invalid_frames": invalid, "target_fps": target_fps,
		"budget_us": budget, "average_fps": n * 1_000_000.0 / total,
		"minimum_fps": 1_000_000.0 / values[-1], "worst_frame_us": values[-1],
		"p50_frame_us": values[ceili(n * 0.5) - 1],
		"p95_frame_us": values[ceili(n * 0.95) - 1],
		"p99_frame_us": values[ceili(n * 0.99) - 1],
		"over_budget_frames": over, "target_met": over == 0 and invalid == 0}

func _run_motion(main: Node, started: int) -> void:
	var target := int(_argument("--target-fps=", "60"))
	var seconds := maxf(float(_argument("--seconds=", "6")), 1.0)
	if target not in [60, 80, 100, 120, 140, 160, 180, 200]:
		push_error("target-fps must be a level from the owner's FPS ladder")
		quit(2)
		return
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	physics_frame.connect(_physics_started)
	process_frame.connect(_process_started)
	RenderingServer.frame_pre_draw.connect(_draw_started)
	RenderingServer.frame_post_draw.connect(_draw_finished)
	_report = {"schema_version": 1, "target_fps": target, "seconds_per_scenario": seconds,
		"limiting_reason": "Engine.max_fps is below the target" if Engine.max_fps > 0 and Engine.max_fps < target else "",
		"context": _context(), "phases": [], "scenarios": [],
		"coverage": "executed scenarios listed below; setup/load in phases",
		"requested_scenarios": _argument("--only=", "all"),
		"not_covered": ["complete mission", "every location/action combination", "simultaneous destruction", "long thermal soak"],
		"whole_game_target_accepted": false, "report_io_us": [],
		"report_io_scope": "preceding writes; each write including final is also printed as FPS_REPORT_IO",
		"monitor_scope": "Performance counters refresh periodically; physics_tail_us covers this frame's physics steps, previous_update_wall_us is process_frame to pre_draw and previous_draw_wall_us is pre/post_draw CPU wall; GPU 0 on Metal means unavailable, not free GPU work"}
	_last_sample_tick = Time.get_ticks_usec()
	var initial := _frame_sample(_last_sample_tick - started, null, false)
	_report.phases.append({"name": "main_initialization", "samples": [initial],
		"summary": frame_stats([initial.frame_us], target)})
	if _selected("menu"):
		await _motion_scenario("menu", null, seconds, false, false, false)
	await _motion_world_phase(main, "start_world")
	var world: DemoWorld = main.world
	for scenario in ["spawn_idle", "spawn_turn", "walk_turn", "run_turn", "busy_street_turn", "kiosk_turn"]:
		if not _selected(scenario):
			continue
		var point := Layout.SPAWN
		if scenario == "busy_street_turn":
			point = Layout.ROUTE_WALK[5]
		elif scenario == "kiosk_turn":
			point = Layout.KIOSK_STAGING
		world.player.place(point, Layout.SPAWN_YAW)
		world.camera_rig.yaw = Layout.SPAWN_YAW
		world.camera_rig.follow(world.player, &"on_foot")
		await _motion_scenario(scenario, world, seconds, scenario in ["walk_turn", "run_turn"],
			scenario == "run_turn", scenario.ends_with("turn"))
	if _selected("driving_input"):
		world.enter_car()
		world.car.reset_to(Layout.ROUTE_DRIVE[3], -PI * 0.5)
		var drive_warmup := await _motion_frames(world, 2.0, false, true)
		var drive_origin := world.car.global_position
		Input.action_press("car_gas")
		var drive_samples := await _motion_frames(world, seconds, false, true)
		Input.action_release("car_gas")
		_append_scenario("driving_input", drive_warmup, drive_samples,
			{"car_displacement_m": world.car.global_position.distance_to(drive_origin), "speed_kmh": world.car.speed_kmh()})
	if _selected("scripted_drive_route"):
		world.enter_car()
		await _motion_drive(world)
	if _selected("after_restart_idle"):
		await _motion_world_phase(main, "restart_world")
		await _motion_scenario("after_restart_idle", main.world, seconds, false, false, false)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_write_report()
	main.queue_free()
	for i in 5:
		await process_frame
	quit(2 if _report_write_failed else 0)

func _motion_world_phase(main: Node, label: String) -> void:
	var started := Time.get_ticks_usec()
	main.start_game()
	var call_us := Time.get_ticks_usec() - started
	var samples: Array = []
	for i in 5:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(_frame_sample(now - _last_sample_tick, main.world, false))
		_last_sample_tick = now
	var intervals: Array = samples.map(func(sample: Dictionary): return sample.frame_us)
	_report.phases.append({"name": label, "wall_us": Time.get_ticks_usec() - started,
		"request_call_us": call_us, "samples": samples, "summary": frame_stats(intervals, _report.target_fps)})

func _motion_scenario(label: String, world: DemoWorld, seconds: float, moving: bool, running: bool, turning: bool) -> void:
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var warmup := await _motion_frames(world, 2.0, false)
	if moving:
		Input.action_press("move_forward")
	if running:
		Input.action_press("sprint")
	var origin := world.player.global_position if world != null else Vector3.ZERO
	var yaw := world.camera_rig.yaw if world != null else 0.0
	var samples := await _motion_frames(world, seconds, turning)
	if turning:
		await process_frame
		var closing_tick := Time.get_ticks_usec()
		samples.append(_frame_sample(closing_tick - _last_sample_tick, world, false))
		_last_sample_tick = closing_tick
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var displacement := world.player.global_position.distance_to(origin) if world != null else 0.0
	_append_scenario(label, warmup, samples, {"player_displacement_m": displacement,
		"camera_start_yaw": yaw, "camera_sweep_radians": TAU if turning else 0.0,
		"control_mode": String(world.control_mode) if world != null else "menu",
		"ui_blocking": world.ui_blocking if world != null else false})

func _motion_frames(world: DemoWorld, seconds: float, turning: bool, driving := false) -> Array:
	var samples: Array = []
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < seconds * 1_000_000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var interval := now - _last_sample_tick
		_last_sample_tick = now
		if turning and world != null:
			world.camera_rig.apply_mouse(Vector2(float(interval) / 1_000_000.0 * TAU / seconds / world.camera_rig.mouse_sensitivity, 0.0))
		samples.append(_frame_sample(interval, world, driving))
	return samples

func _motion_drive(world: DemoWorld) -> void:
	var warmup := await _motion_frames(world, 2.0, false, true)
	var samples: Array = []
	var route := Layout.ROUTE_DRIVE
	var segment := 1
	var position := route[0]
	world.car.reset_to(position, Layout.SPAWN_YAW)
	while segment < route.size():
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(_frame_sample(now - _last_sample_tick, world, true))
		var dt := (now - _last_sample_tick) / 1_000_000.0
		_last_sample_tick = now
		var target: Vector3 = route[segment]
		var to_target: Vector3 = target - position
		var step := SPEED * minf(dt, 0.05)
		if to_target.length() <= step:
			position = target
			segment += 1
		else:
			position += to_target.normalized() * step
		var yaw := atan2(-to_target.x, -to_target.z)
		world.car.reset_to(position, yaw)
		world.camera_rig.yaw = yaw
	await process_frame
	var closing_tick := Time.get_ticks_usec()
	samples.append(_frame_sample(closing_tick - _last_sample_tick, world, true))
	_last_sample_tick = closing_tick
	_append_scenario("scripted_drive_route", warmup, samples,
		{"scope": "same reset_to Layout.ROUTE_DRIVE as make fps; not real driving input"})

func _frame_sample(interval: int, world: DemoWorld, driving: bool) -> Dictionary:
	var position := Vector3.ZERO
	if world != null:
		position = world.car.global_position if driving else world.player.global_position
	var physics_tail := Time.get_ticks_usec() - _physics_phase_start_tick if _physics_phase_steps > 0 else 0
	var steps := _physics_phase_steps
	_physics_phase_steps = 0
	return {"frame_us": interval, "physics_steps": steps, "physics_tail_us": physics_tail,
		"previous_draw_wall_us": _draw_wall_us, "previous_update_wall_us": _update_wall_us,
		"process_us": Performance.get_monitor(Performance.TIME_PROCESS) * 1_000_000.0,
		"physics_us": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0,
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"position_xz": [position.x, position.z]}

func _physics_started() -> void:
	if _physics_phase_steps == 0:
		_physics_phase_start_tick = Time.get_ticks_usec()
	_physics_phase_steps += 1

func _draw_started() -> void:
	_draw_started_tick = Time.get_ticks_usec()
	_update_wall_us = _draw_started_tick - _process_started_tick

func _draw_finished() -> void:
	_draw_wall_us = Time.get_ticks_usec() - _draw_started_tick

func _process_started() -> void:
	_process_started_tick = Time.get_ticks_usec()

func _append_scenario(label: String, warmup: Array, samples: Array, extra: Dictionary) -> void:
	var intervals: Array = samples.map(func(sample: Dictionary): return sample.frame_us)
	var summary := frame_stats(intervals, _report.target_fps)
	var scenario := {"name": label, "warmup_samples": warmup, "samples": samples,
		"summary": summary, "extra": extra}
	_report.scenarios.append(scenario)
	print("FPS_MOTION: ", label, " ", JSON.stringify(summary), " ", JSON.stringify(extra))
	_write_report()

func _context() -> Dictionary:
	var render_size := Vector2(root.size) * root.scaling_3d_scale
	return {"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "window_size": [root.size.x, root.size.y],
		"render_scale": root.scaling_3d_scale, "render_size": [render_size.x, render_size.y],
		"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"cmdline_args": OS.get_cmdline_args(), "user_args": OS.get_cmdline_user_args(), "time_scale": Engine.time_scale,
		"fixed_fps_workload": OS.get_environment("GODOT_FIXED_FPS_WORKLOAD") == "1",
		"physics_hz": Engine.physics_ticks_per_second, "audio_driver": AudioServer.get_driver_name(),
		"engine_version": Engine.get_version_info(),
		"runner_sha256": FileAccess.get_sha256("res://tools/fps_probe.gd"),
		"project_sha256": FileAccess.get_sha256("res://project.godot"),
		"imported_backend_sha256": FileAccess.get_sha256("res://game/characters/imported_hero_visual.gd"),
		"hero_glb_sha256": FileAccess.get_sha256("res://assets/models/characters/ilyusha/ilyusha.glb")}

func _argument(prefix: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return fallback

func _selected(scenario: String) -> bool:
	var selection := _argument("--only=", "")
	return selection.is_empty() or scenario in selection.split(",")

func _write_report() -> void:
	var started := Time.get_ticks_usec()
	var path := _argument("--output=", "res://builds/checks/MOTION-01/fps-motion.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_report_write_failed = true
		push_error("cannot save raw FPS report: " + path)
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	var elapsed := Time.get_ticks_usec() - started
	_report.report_io_us.append(elapsed)
	print("FPS_REPORT_IO: ", elapsed)

## Optional controlled scene composition; the ordinary route/warmup/measurement remain unchanged.
## Destruction transients finish before measurement; restore_left pins this fixture during the route.
func _prepare_break_env(world: DemoWorld) -> bool:
	var owner: Node = world.get_node_or_null("LevelGeometry/Breakables")
	if owner == null or not owner.has_method("env_at_index"):
		return _setup_failed("BREAK-03 runtime is not present")
	var catalogue: Array = Layout.env_breakables()
	var objects: Array = owner.get("env_objects")
	if catalogue.is_empty() or objects.size() != catalogue.size():
		return _setup_failed("ENV catalogue/runtime count mismatch or empty ENV")
	var solids := Layout.all_solids()
	var constants: Dictionary = owner.get_script().get_script_constant_map()
	var modes: Dictionary = constants["ENV_MODE"]
	var seen := {}
	for spec: Array in catalogue:
		var source: Array = solids[spec[6]]
		if source[1] in ["panel", "panel_low", "garage", "kiosk", "snow", "snow_bank"] \
			or source[0] in ["DogHouse", "KioskPavilion", "KioskBins"]:
			return _setup_failed("protected solid was included in ENV: " + String(spec[0]))
		var object: Variant = owner.get_by_id(spec[0])
		if object == null or seen.has(spec[0]) or not objects.has(object) or object.env_index != spec[6] \
			or object.kind != spec[1] or object.mode != modes.get(spec[1], &"shatter") \
			or object.mode not in [&"topple", &"shatter", &"dent"]:
			return _setup_failed("invalid ENV owner/mode: " + String(spec[0]))
		seen[spec[0]] = true
		_env_fixture.append(object)
	for spec: Array in Layout.BREAKABLES:
		var object: Variant = owner.get_by_id(spec[0])
		if object == null or _env_fixture.has(object):
			return _setup_failed("original breakable missing or incorrectly included in ENV")
		_original_fixture.append([object, object.state, object.blocks(), object.body.collision_layer])
	var coins_before: int = owner.coins_dropped
	for object: Variant in _env_fixture:
		object.smash(&"fps_setup", Vector3.RIGHT)
		object.restore_left = 1.0e9
	if owner.coins_dropped != coins_before:
		return _setup_failed("controlled setup unexpectedly awarded coins")
	# Fall/sink and car alarms finish on real physics time; no world/NPC/physics processing is disabled.
	var settle_seconds: float = maxf(float(constants["FALL_SECONDS"]) + float(constants["LIE_SECONDS"]) \
		+ float(constants["SINK_SECONDS"]), float(constants["ALARM_SECONDS"])) + 1.0
	var ready_frame := Engine.get_physics_frames() + ceili(settle_seconds * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < ready_frame:
		await process_frame
	if owner.debris_count() != 0 or not _verify_break_env(world):
		return _setup_failed("ENV did not reach a steady broken/dent composition")
	var counts := {"topple": 0, "shatter": 0, "dent": 0}
	for object: Variant in _env_fixture:
		counts[String(object.mode)] += 1
	var people: Node = world.get_node("LevelGeometry/Residents")
	print("FPS_BREAK_ENV_SETUP: ", JSON.stringify({"status": "READY", "broken_env": _env_fixture.size(),
		"catalogue_env": catalogue.size(), "modes": counts, "original_breakables_preserved": _original_fixture.size(),
		"residents": people.residents.size(), "traffic_vehicles": get_nodes_in_group(&"traffic_vehicles").size(),
		"settle_physics_seconds_min": settle_seconds, "restore_pin_seconds": 1.0e9,
		"scope": "steady already-broken scene; excludes simultaneous destruction performance and manual feel acceptance",
		"route": "unchanged Layout.ROUTE_DRIVE scripted reset_to", "warmup_frames": WARMUP_FRAMES,
		"rendering_method": RenderingServer.get_current_rendering_method(), "physics_hz": Engine.physics_ticks_per_second}))
	return true

func _verify_break_env(world: DemoWorld) -> bool:
	if paused or not world.can_process():
		return _setup_failed("world was paused or disabled")
	var owner: Node = world.get_node("LevelGeometry/Breakables")
	if not owner.is_physics_processing() or not owner.can_process():
		return _setup_failed("Breakables physics processing was disabled")
	var vehicles: Array = get_nodes_in_group(&"traffic_vehicles")
	if vehicles.size() != Layout.TRAFFIC_CARS + 1:
		return _setup_failed("ring traffic composition changed")
	vehicles.append(world.get_node("LevelGeometry/Patrols/CityVan"))
	for vehicle: Node in vehicles:
		if not vehicle.is_physics_processing() or not vehicle.can_process():
			return _setup_failed("transport processing was disabled")
	var people: Node = world.get_node("LevelGeometry/Residents")
	if people.residents.size() < 64 or not people.is_physics_processing():
		return _setup_failed("64 active residents are required")
	for resident: Node in people.residents:
		if not resident.is_physics_processing() or not resident.can_process():
			return _setup_failed("resident processing was disabled")
	for object: Variant in _env_fixture:
		if not is_instance_valid(object) or not is_instance_valid(object.body):
			return _setup_failed("ENV owner/body disappeared")
		var dent: bool = object.mode == &"dent"
		var shape: CollisionShape3D = object.body.get_child(0)
		if object.state != &"broken" or object.is_intact() or object.blocks() != dent or object.restore_left <= 0.0 \
			or object.body.collision_layer != (33 if dent else 0) or shape.disabled != (not dent) \
			or object.env_hidden() != (not dent):
			return _setup_failed("ENV actual state/mode/collision differs from fixture: " + String(object.id))
	for original: Array in _original_fixture:
		var object: Variant = original[0]
		if object.state != original[1] or object.blocks() != original[2] or object.body.collision_layer != original[3]:
			return _setup_failed("original breakable changed: " + String(object.id))
	return true

func _setup_failed(reason: String) -> bool:
	push_error("FPS_BREAK_ENV_SETUP FAILED: " + reason)
	return false

func _abort_setup(main: Node) -> void:
	main.queue_free()
	for i in 5:
		await process_frame
	quit(2)
