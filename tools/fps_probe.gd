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
var _workload_invalid := false
var _removed_physical_events := 0

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
	root.gui_disable_input = true
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	var started := Time.get_ticks_usec()
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	_removed_physical_events = isolate_physical_input()
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
	var idle_control := _argument("--idle-control=", "")
	if not idle_control.is_empty():
		if idle_control not in ["restart", "wait"] or (idle_control == "wait" and int(_argument("--idle-gap-us=", "0")) <= 0):
			push_error("idle-control requires restart or wait; wait also requires the restart run's --idle-gap-us")
			quit(2)
			return
		await _run_idle_control(main, seconds, idle_control)
		await _finish_motion(main)
		return
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
	await _finish_motion(main)

func _finish_motion(main: Node) -> void:
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_write_report()
	main.queue_free()
	for i in 5:
		await process_frame
	quit(2 if _report_write_failed else (3 if _workload_invalid else 0))

func _run_idle_control(main: Node, seconds: float, mode: String) -> void:
	_report.coverage = "fixed spawn view: idle, then restart or elapsed-matched wait, then idle"
	_report["idle_control"] = {"mode": mode, "checkpoints": [],
		"physics_counter_scope": "native active objects/pairs/islands and scene collision nodes; active objects exclude static RID bodies, no native total-body counter is available"}
	await _motion_world_phase(main, "start_world")
	_report.idle_control.checkpoints.append(_world_checkpoint(main, "initial_world"))
	await _motion_scenario("spawn_idle", main.world, seconds, false, false, false)
	var before := _world_checkpoint(main, "after_first_idle")
	_report.idle_control.checkpoints.append(before)
	var first_samples: Array = _report.scenarios[0].samples
	var first_last_tick: int = first_samples[-1].sample_tick_us
	var requested_gap := int(_argument("--idle-gap-us=", "0"))
	if mode == "restart":
		await _motion_world_phase(main, "restart_world")
		_report.idle_control.checkpoints.append(_world_checkpoint(main, "restarted_world"))
		await _motion_scenario("after_restart_idle", main.world, seconds, false, false, false)
	else:
		# The reference gap includes report/checkpoint work, world building and the
		# restart warmup. Match its real wall time rather than just a sample count.
		var remaining_us := first_last_tick + requested_gap - Time.get_ticks_usec()
		var wait_started := Time.get_ticks_usec()
		var warmup := await _motion_frames(main.world, maxf(remaining_us / 1_000_000.0, 0.0), false)
		_report.phases.append({"name": "matched_idle_wait", "wall_us": Time.get_ticks_usec() - wait_started,
			"requested_remaining_us": remaining_us})
		var origin: Vector3 = main.world.player.global_position
		var samples := await _motion_frames(main.world, seconds, false)
		_append_scenario("after_wait_idle", warmup, samples,
			{"player_displacement_m": main.world.player.global_position.distance_to(origin),
			"camera_start_yaw": main.world.camera_rig.yaw, "camera_sweep_radians": 0.0})
	var after := _world_checkpoint(main, "after_second_idle")
	_report.idle_control.checkpoints.append(after)
	var second_samples: Array = _report.scenarios[1].samples
	var observed_gap: int = second_samples[0].sample_tick_us - first_last_tick
	var tolerance_us := ceili(2_000_000.0 / _report.target_fps)
	var validity := idle_control_validity(mode, before, after, observed_gap, requested_gap, tolerance_us)
	_report.idle_control.merge({"observed_gap_us": observed_gap, "requested_gap_us": requested_gap,
		"gap_tolerance_us": tolerance_us, "validity": validity})
	_workload_invalid = _workload_invalid or not validity.valid
	print("FPS_IDLE_CONTROL: ", JSON.stringify(_report.idle_control))

func _world_checkpoint(main: Node, label: String) -> Dictionary:
	var world: DemoWorld = main.world
	var position := world.player.global_position
	return {"name": label, "tick_us": Time.get_ticks_usec(), "world_id": world.get_instance_id(),
		"space_rid": world.get_world_3d().space.get_id(), "root_children": root.get_child_count(),
		"tree_node_count": get_node_count(), "object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"orphan_node_count": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"collision_node_count": world.find_children("*", "CollisionObject3D", true, false).size(),
		"collision_shape_node_count": world.find_children("*", "CollisionShape3D", true, false).size(),
		"physics_active_objects": PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS),
		"physics_collision_pairs": PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS),
		"physics_islands": PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ISLAND_COUNT),
		"player_position_xz": [position.x, position.z], "camera_yaw": world.camera_rig.yaw,
		"mission_state": String(world.mission.state), "workload_state": _workload_state(world),
		"residents": world.get_node("LevelGeometry/Residents").residents.size(),
		"traffic_vehicles": get_nodes_in_group(&"traffic_vehicles").size()}

static func idle_control_validity(mode: String, before: Dictionary, after: Dictionary, observed_gap: int, requested_gap: int, tolerance_us: int) -> Dictionary:
	var reasons: Array[String] = []
	if (before.world_id != after.world_id) != (mode == "restart"):
		reasons.append("unexpected_world_identity")
	if before.player_position_xz != after.player_position_xz or not is_equal_approx(before.camera_yaw, after.camera_yaw):
		reasons.append("view_changed")
	if mode == "wait" and (requested_gap <= 0 or absi(observed_gap - requested_gap) > tolerance_us):
		reasons.append("elapsed_gap_not_matched")
	return {"valid": reasons.is_empty(), "reasons": reasons, "gap_error_us": observed_gap - requested_gap if mode == "wait" else 0}

static func isolate_physical_input() -> int:
	# Native modifier events can update Input even for a no-focus macOS window.
	# Keep action names/deadzones and direct action_press(), remove device bindings.
	var removed := 0
	for action: StringName in InputMap.get_actions():
		removed += InputMap.action_get_events(action).size()
		Input.action_release(action)
		InputMap.action_erase_events(action)
	return removed

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
		"request_call_us": call_us, "samples": samples, "summary": frame_stats(intervals, _report.target_fps),
		"hero_inputs": hero_provenance(main.world.player.get_node_or_null("Visual/Look"))})

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
	var query_started := Time.get_ticks_usec()
	var pipelines := {
		"canvas": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS),
		"mesh": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
		"surface": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
		"draw": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
		"specialization": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)}
	var query_us := Time.get_ticks_usec() - query_started
	return {"sample_tick_us": Time.get_ticks_usec(), "frame_us": interval, "physics_steps": steps, "physics_tail_us": physics_tail,
		"pipeline_compilations": pipelines, "pipeline_monitor_query_us": query_us,
		"previous_draw_wall_us": _draw_wall_us, "previous_update_wall_us": _update_wall_us,
		"process_us": Performance.get_monitor(Performance.TIME_PROCESS) * 1_000_000.0,
		"physics_us": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0,
		"physics_active_objects": PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS),
		"physics_collision_pairs": PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS),
		"physics_islands": PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ISLAND_COUNT),
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"position_xz": [position.x, position.z], "workload_state": _workload_state(world)}

func _workload_state(world: DemoWorld) -> Dictionary:
	var movement := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var state := {"tree_paused": paused, "world_active": world != null and world.can_process(),
		"move_input": [movement.x, movement.y], "sprint_input": Input.is_action_pressed(&"sprint"),
		"gas_input": Input.get_action_strength(&"car_gas")}
	if world != null:
		state.merge({"control_mode": String(world.control_mode), "ui_blocking": world.ui_blocking,
			"stealth_state": String(world.stealth.state), "stealth_failing": world.is_stealth_failing(),
			"stealth_frozen": world.stealth.frozen, "suspicion": world.stealth.suspicion,
			"player_input_enabled": world.player.input_enabled,
			"player_horizontal_speed": Vector2(world.player.velocity.x, world.player.velocity.z).length()})
	return state

static func workload_validity(label: String, samples: Array) -> Dictionary:
	var reasons := {}
	var bad_frames := 0
	var moving := label in ["walk_turn", "run_turn"]
	var driving := label in ["driving_input", "scripted_drive_route"]
	for sample: Dictionary in samples:
		var state: Dictionary = sample.workload_state
		var issues: Array[String] = []
		if state.tree_paused:
			issues.append("tree_paused")
		if label != "menu":
			if not state.world_active:
				issues.append("world_inactive")
			if state.control_mode != ("in_car" if driving else "on_foot"):
				issues.append("unexpected_control_mode")
			if state.ui_blocking or state.stealth_failing:
				issues.append("blocking_ui_or_caught")
			if not driving and not state.player_input_enabled:
				issues.append("foot_input_disabled")
			if not driving:
				var movement := Vector2(state.move_input[0], state.move_input[1])
				if not movement.is_equal_approx(Vector2(0.0, -1.0) if moving else Vector2.ZERO) \
					or state.sprint_input != (label == "run_turn"):
					issues.append("unexpected_movement_input")
				if not moving and state.player_horizontal_speed > 0.05:
					issues.append("idle_player_moving")
		if not issues.is_empty():
			bad_frames += 1
		for issue: String in issues:
			reasons[issue] = int(reasons.get(issue, 0)) + 1
	return {"valid": not samples.is_empty() and bad_frames == 0, "invalid_frames": bad_frames,
		"reason_frame_counts": reasons, "frames": samples.size()}

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
	var validity := workload_validity(label, samples)
	_workload_invalid = _workload_invalid or not validity.valid
	var scenario := {"name": label, "warmup_samples": warmup, "samples": samples,
		"summary": summary, "extra": extra, "workload_validity": validity,
		"sampled_target_accepted": summary.target_met and validity.valid}
	_report.scenarios.append(scenario)
	print("FPS_MOTION: ", label, " ", JSON.stringify(summary), " ", JSON.stringify(extra))
	print("FPS_WORKLOAD: ", label, " ", JSON.stringify(validity))
	_write_report()

func _context() -> Dictionary:
	var render_size := Vector2(root.size) * root.scaling_3d_scale
	return {"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "window_size": [root.size.x, root.size.y],
		"render_scale": root.scaling_3d_scale, "render_size": [render_size.x, render_size.y],
		"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"cmdline_args": OS.get_cmdline_args(), "user_args": OS.get_cmdline_user_args(), "time_scale": Engine.time_scale,
		"fixed_fps_workload": OS.get_environment("GODOT_FIXED_FPS_WORKLOAD") == "1",
		"gui_input_disabled": root.gui_disable_input, "no_focus": root.get_flag(Window.FLAG_NO_FOCUS),
		"physical_input_events_removed": _removed_physical_events,
		"physics_hz": Engine.physics_ticks_per_second, "audio_driver": AudioServer.get_driver_name(),
		"engine_version": Engine.get_version_info(),
		"runner_sha256": FileAccess.get_sha256("res://tools/fps_probe.gd"),
		"project_sha256": FileAccess.get_sha256("res://project.godot"),
		"hero_inputs": hero_provenance()}

static func hero_provenance(look: Node = null) -> Dictionary:
	if not look is CharacterSprite:
		return {"backend": "unknown", "files_sha256": {}}
	var paths: Array = [look.get_script().resource_path, "res://game/characters/character_catalog.gd",
		"res://game/player/ilyusha.gd"]
	var result := {"backend": "unknown", "look_id": look.get_instance_id(),
		"drawing": look.resolved_character(), "files_sha256": {}}
	if look.sprite != null and look.uniform_visual == null:
		result.backend = "sprite_2d"
		for texture: Texture2D in look._idle.values():
			paths.append(texture.resource_path)
		for frames: Array in look._walk.values():
			for texture: Texture2D in frames:
				paths.append(texture.resource_path)
	elif look.uniform_visual != null and look.uniform_visual.imported_hero != null:
		var provider: Node = look.uniform_visual.imported_hero
		var model_path: String = provider.MODEL.resource_path
		var manifest_path := "res://addons/quaternius_ik_rigged/SOURCE_MANIFEST.json"
		var library_path := "res://assets/animations/quaternius/original_locomotion.res"
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		result.merge({"backend": "imported_3d", "model_path": model_path,
			"manifest_path": manifest_path, "animation_library_path": library_path}, true)
		paths.append_array([look.uniform_visual.get_script().resource_path, provider.get_script().resource_path,
			model_path, manifest_path, library_path])
		paths.append_array(manifest.dependencies.keys())
	else:
		return result
	var hashes := {}
	for path: String in paths:
		hashes[path] = FileAccess.get_sha256(path)
		if FileAccess.file_exists(path + ".import"):
			hashes[path + ".import"] = FileAccess.get_sha256(path + ".import")
	result.files_sha256 = hashes
	return result

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
