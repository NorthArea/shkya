extends SceneTree
## MOTION-01: spikes must remain visible even when the average meets the target.

var checks := 0
var failures := 0

class PacingOverwrite extends Node:
	var fake_vsync: Array
	func _ready() -> void:
		Engine.max_fps = 60
		fake_vsync[0] = DisplayServer.VSYNC_ENABLED

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var probe: Variant = load("res://tools/fps_probe.gd")
	if not check(probe.has_method("frame_stats"), "FPS runner exposes independently testable raw-frame statistics"):
		_finish()
		return
	if not check(probe.get_script_method_list().any(func(method: Dictionary): return method.name == "_configure_dispatch_trace"),
		"FPS probe exposes opt-in dispatch instrumentation"):
		_finish()
		return
	var dispatch_probe: SceneTree = probe.new()
	dispatch_probe._render_queries_enabled = false
	load("res://game/input_setup.gd").install()
	var child_count := dispatch_probe.root.get_child_count()
	check(dispatch_probe._configure_dispatch_trace("off").valid
		and dispatch_probe.root.get_child_count() == child_count,
		"dispatch off installs no sentinels")
	check(not dispatch_probe._frame_sample(12345, null, false).has("dispatch_trace"),
		"default/off sample retains its previous JSON shape")
	check(not dispatch_probe._configure_dispatch_trace("maybe").valid,
		"probe rejects unsupported dispatch trace modes")
	check(dispatch_probe._configure_dispatch_trace("on").valid, "probe can opt into dispatch trace")
	dispatch_probe._dispatch_trace.record(4)
	var traced: Dictionary = dispatch_probe._frame_sample(23456, null, false)
	check(traced.frame_us == 23456 and traced.dispatch_trace.events.size() == 1,
		"opt-in attaches bounded events without adjusting the raw wall interval")
	check(dispatch_probe._frame_sample(34567, null, false).dispatch_trace.events.is_empty(),
		"each probe sample drains events exactly once")
	dispatch_probe._dispatch_trace.free()
	dispatch_probe._dispatch_trace = null
	dispatch_probe.free()
	var spike: Dictionary = probe.call("frame_stats", [10000, 10000, 10000, 50000], 60)
	check(is_equal_approx(spike.average_fps, 50.0), "average derives from elapsed time, not averaged instantaneous FPS")
	check(is_equal_approx(spike.minimum_fps, 20.0), "one slow frame remains visible as the minimum")
	check(spike.over_budget_frames == 1, "one frame breaches the current target")
	check(spike.worst_frame_us == 50000 and spike.p99_frame_us == 50000, "short sample p99 includes its slowest frame")
	check(spike.target_met == false, "one breach prevents target acceptance")
	var hidden_spike: Dictionary = probe.call("frame_stats", [1000, 1000, 1000, 50000], 60)
	check(hidden_spike.average_fps > 60.0 and not hidden_spike.target_met, "good average cannot hide a serious hitch")
	var stable: Dictionary = probe.call("frame_stats", [10000, 10000, 10000, 10000], 80)
	check(stable.target_met and stable.over_budget_frames == 0, "every frame within the budget meets the sampled target")
	var boundary: Dictionary = probe.call("frame_stats", [12500, 12500], 80)
	check(boundary.target_met, "a frame exactly on the 80 FPS budget is allowed")
	var empty: Dictionary = probe.call("frame_stats", [], 60)
	check(not empty.target_met and empty.frames == 0, "no samples cannot accept a level")
	var invalid: Dictionary = probe.call("frame_stats", [10000, 0, -1], 60)
	check(not invalid.target_met and invalid.invalid_frames == 2, "invalid raw intervals cannot turn into passing evidence")
	if not check(probe.has_method("configure_vsync"), "FPS probe supports a runtime-only vsync override"):
		_finish()
		return
	var vsync_calls := []
	var effective := [DisplayServer.VSYNC_ADAPTIVE]
	var set_vsync := func(mode: int):
		vsync_calls.append(mode)
		effective[0] = mode
	var default_vsync: Dictionary = probe.call("configure_vsync", "project", set_vsync)
	check(default_vsync.valid and default_vsync.requested == "project" and not default_vsync.applied
		and vsync_calls.is_empty() and effective[0] == DisplayServer.VSYNC_ADAPTIVE,
		"default project mode leaves an existing nondefault vsync untouched and never calls the setter")
	var enabled: Dictionary = probe.call("configure_vsync", "enabled", set_vsync)
	check(enabled.valid and enabled.applied and enabled.requested == "enabled"
		and vsync_calls == [DisplayServer.VSYNC_ENABLED] and effective[0] == DisplayServer.VSYNC_ENABLED,
		"enabled applies the exact enabled enum once and preserves requested provenance")
	var disabled: Dictionary = probe.call("configure_vsync", "disabled", set_vsync)
	check(disabled.valid and disabled.applied and disabled.requested == "disabled"
		and vsync_calls == [DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_DISABLED]
		and effective[0] == DisplayServer.VSYNC_DISABLED, "disabled applies the exact disabled enum once")
	var bad_vsync: Dictionary = probe.call("configure_vsync", "adaptive", set_vsync)
	check(not bad_vsync.valid and not bad_vsync.applied and vsync_calls.size() == 2
		and effective[0] == DisplayServer.VSYNC_DISABLED, "unsupported values are rejected without changing effective vsync")
	var no_window: Dictionary = probe.call("configure_vsync", "enabled", Callable())
	check(no_window.valid and not no_window.applied and no_window.requested == "enabled",
		"headless validation can parse an override without activating or calling a window")
	if not check(probe.has_method("restore_measurement_pacing") and probe.has_method("configure_render_capture"),
		"FPS probe restores post-Main pacing and independently configures render capture"):
		_finish()
		return
	var original_cap := Engine.max_fps
	Engine.max_fps = 200
	var measurement_cap := Engine.max_fps
	var fake_main := PacingOverwrite.new()
	fake_main.fake_vsync = effective
	root.add_child(fake_main)
	check(Engine.max_fps == 60 and effective[0] == DisplayServer.VSYNC_ENABLED,
		"fake Main readiness really overwrites both initial pacing settings")
	var restored: Dictionary = probe.call("restore_measurement_pacing", measurement_cap, "disabled", Engine.set_max_fps, set_vsync)
	check(restored.valid and restored.applied and Engine.max_fps == 200 and effective[0] == DisplayServer.VSYNC_DISABLED,
		"post-ready restore recovers the captured CLI cap and reapplies explicit vsync")
	fake_main._ready()
	var calls_before_project := vsync_calls.size()
	var restored_project: Dictionary = probe.call("restore_measurement_pacing", 0, "project", Engine.set_max_fps, set_vsync)
	check(restored_project.valid and Engine.max_fps == 0 and vsync_calls.size() == calls_before_project
		and effective[0] == DisplayServer.VSYNC_ENABLED, "retry after Main overwrite preserves an uncapped run while project vsync keeps Main's choice")
	Engine.max_fps = original_cap
	fake_main.free()
	var capture_calls := []
	var set_capture := func(enabled_value: bool): capture_calls.append(enabled_value)
	var capture_on: Dictionary = probe.call("configure_render_capture", "on", set_capture)
	var capture_off: Dictionary = probe.call("configure_render_capture", "off", set_capture)
	check(capture_on.valid and capture_on.enabled and capture_on.applied and capture_on.requested == "on"
		and capture_off.valid and not capture_off.enabled and capture_off.applied and capture_off.requested == "off"
		and capture_calls == [true, false], "capture on/off passes exact booleans to the real configuration helper independently of query mode")
	var bad_capture: Dictionary = probe.call("configure_render_capture", "invalid", set_capture)
	check(not bad_capture.valid and not bad_capture.applied and capture_calls.size() == 2,
		"invalid render capture is rejected without changing the viewport")
	if not check(probe.has_method("render_query_sample"), "FPS probe measures and can disable renderer getter calls"):
		_finish()
		return
	load("res://game/input_setup.gd").install()
	var instrumented: SceneTree = probe.new()
	var calls := [0]
	instrumented._render_cpu_query = func():
		calls[0] += 1
		OS.delay_usec(8000)
		return 3.0
	instrumented._render_gpu_query = func():
		calls[0] += 1
		OS.delay_usec(4000)
		return 0.0
	var first_tick := Time.get_ticks_usec()
	var first: Dictionary = instrumented._frame_sample(1000, null, false)
	check(first.previous_sample_diagnostics.is_empty(), "first sample cannot attribute its new getter pause to its preceding interval")
	instrumented._render_queries_enabled = false
	var second_tick := Time.get_ticks_usec()
	var second: Dictionary = instrumented._frame_sample(second_tick - first_tick, null, false)
	var previous: Dictionary = second.previous_sample_diagnostics
	check(previous.sample_sequence == first.sample_sequence and previous.sample_sequence != second.sample_sequence,
		"completed instrumentation costs identify the preceding sample, never the current sample")
	check(previous.render_queries.cpu.wall_us >= 8000 and previous.render_queries.gpu.wall_us >= 4000,
		"separate getter timers retain injected blocking CPU and GPU costs")
	check(previous.started_tick_us <= previous.render_queries.cpu.started_tick_us
		and previous.render_queries.cpu.ended_tick_us <= previous.render_queries.gpu.started_tick_us
		and previous.render_queries.gpu.ended_tick_us <= previous.ended_tick_us
		and previous.ended_tick_us <= second.sample_tick_us, "absolute timestamps place the query waits inside the previous collection and next interval")
	check(previous.wall_us >= previous.render_queries.cpu.wall_us + previous.render_queries.gpu.wall_us,
		"sample wall cost includes both getter waits and the remaining telemetry")
	check(calls[0] == 2 and second.render_cpu_ms == null and second.render_gpu_ms == null,
		"queries off calls neither getter and records unavailable timings, not free render work")
	check(second.frame_us == second_tick - first_tick and not probe.call("frame_stats", [second.frame_us], 200).target_met,
		"raw frame statistics retain the query-induced stall instead of subtracting instrumentation")
	var third: Dictionary = instrumented._frame_sample(1000, null, false)
	check(third.previous_sample_diagnostics.render_queries.mode == "off"
		and third.previous_sample_diagnostics.render_queries.cpu == null
		and third.previous_sample_diagnostics.render_queries.gpu == null and calls[0] == 2,
		"next sample preserves off-mode provenance with absent per-query measurements")
	instrumented._render_capture_configuration = capture_off
	instrumented._render_queries_enabled = true
	var fourth: Dictionary = instrumented._frame_sample(30000, null, false)
	check(calls[0] == 4 and fourth.render_cpu_ms == null and fourth.render_gpu_ms == null,
		"capture off leaves queries independently enabled for their cost, but cannot claim valid render timings")
	instrumented._render_queries_enabled = false
	var fifth: Dictionary = instrumented._frame_sample(40000, null, false)
	check(fifth.previous_sample_diagnostics.render_queries.mode == "on"
		and not fifth.previous_sample_diagnostics.render_queries.capture_enabled,
		"next-sample provenance distinguishes disabled capture from enabled getters")
	check(calls[0] == 4 and fifth.render_cpu_ms == null and fifth.render_gpu_ms == null
		and fifth.frame_us == 40000 and not probe.call("frame_stats", [fifth.frame_us], 60).target_met,
		"capture off plus queries off keeps timings unavailable and preserves raw-frame breaches")
	instrumented.free()
	var unknown: Dictionary = probe.call("hero_provenance")
	if not check(unknown.get("backend", "") == "unknown" and unknown.get("files_sha256", {}).is_empty(), "menu cannot identify a hero that has not been instantiated"):
		_finish()
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var sprite_script: Variant = load("res://game/characters/character_sprite.gd")
	var unready: Node3D = sprite_script.new()
	check(probe.call("hero_provenance", unready).backend == "unknown", "configured but uninstantiated backend remains unknown")
	unready.free()
	var player: Node3D = load("res://game/player/ilyusha.tscn").instantiate()
	holder.add_child(player)
	var look: Node3D = player.get_node("Visual/Look")
	var sprite_provenance: Dictionary = probe.call("hero_provenance", look)
	check(sprite_provenance.get("backend", "") == "sprite_2d", "actual Player visual is identified as 2D")
	var hashes: Dictionary = sprite_provenance.get("files_sha256", {})
	var complete := hashes.has("res://game/characters/character_sprite.gd") and hashes.has("res://game/characters/character_catalog.gd")
	for view in ["front", "back", "side"]:
		for frame in ["idle", "walk0", "walk1", "walk2", "walk3"]:
			var path := "res://assets/art/characters/ilyusha_%s_%s.svg" % [view, frame]
			complete = complete and hashes.has(path) and hashes.has(path + ".import")
	check(complete, "all three actual SVG views, four walk frames and import settings plus adapter/Catalog are hashed")
	check(not hashes.has("res://game/characters/imported_hero_visual.gd"), "inactive imported provider is absent from active 2D inputs")
	var current := true
	for path: String in hashes:
		current = current and not String(hashes[path]).is_empty() and hashes[path] == FileAccess.get_sha256(path)
	check(current, "2D snapshot hashes actual loaded dependencies")
	var model_look: Node3D = sprite_script.new()
	holder.add_child(model_look)
	var model_provenance: Dictionary = probe.call("hero_provenance", model_look)
	check(model_provenance.get("backend", "") == "imported_3d", "an actual instantiated 3D actor is distinguished from forced 2D")
	check(model_provenance.get("model_path", "") == model_look.uniform_visual.imported_hero.MODEL.resource_path,
		"3D provenance follows the live provider's model instead of the 2D default")
	check(model_provenance.get("files_sha256", {}).has("res://addons/quaternius_ik_rigged/SOURCE_MANIFEST.json"), "only active imported 3D includes its manifest inventory")
	holder.free()
	if check(probe.has_method("workload_validity"), "FPS acceptance validates the workload as well as frame timing"):
		var state := {"tree_paused": false, "world_active": true, "control_mode": "on_foot",
			"ui_blocking": false, "stealth_failing": false, "player_input_enabled": true,
			"player_horizontal_speed": 0.0, "move_input": [0.0, 0.0], "sprint_input": false}
		var sample := {"workload_state": state}
		check(probe.call("workload_validity", "spawn_idle", [sample]).valid, "active stationary idle is a valid workload")
		state.tree_paused = true
		check(not probe.call("workload_validity", "spawn_idle", [sample]).valid, "paused frames invalidate an apparently fast workload")
		state.tree_paused = false
		state.move_input = [0.0, -1.0]
		state.player_horizontal_speed = 2.0
		check(not probe.call("workload_validity", "spawn_idle", [sample]).valid, "external movement cannot pass as idle")
		check(probe.call("workload_validity", "walk_turn", [sample]).valid, "programmatic walking input remains valid")
		state.ui_blocking = true
		state.stealth_failing = true
		state.player_input_enabled = false
		check(not probe.call("workload_validity", "walk_turn", [sample]).valid, "caught UI cannot pass as an active walking workload")
		state.ui_blocking = false
		state.stealth_failing = false
		state.player_input_enabled = true
		state.sprint_input = true
		check(probe.call("workload_validity", "run_turn", [sample]).valid, "programmatic sprint input remains valid")
		state.control_mode = "in_car"
		check(not probe.call("workload_validity", "run_turn", [sample]).valid, "changed control mode invalidates a foot workload")
		check(not probe.call("workload_validity", "spawn_idle", []).valid, "missing workload samples cannot pass")
	if check(probe.has_method("idle_control_validity"), "paired idle diagnostic checks real lifecycle and elapsed time"):
		var before := {"world_id": 1, "player_position_xz": [0.0, 0.0], "camera_yaw": 2.5}
		var after: Dictionary = before.duplicate(true)
		check(not probe.call("idle_control_validity", "restart", before, after, 7000000, 0, 33334).valid,
			"restart diagnostic cannot pass when the old world survives")
		after.world_id = 2
		check(probe.call("idle_control_validity", "restart", before, after, 7000000, 0, 33334).valid,
			"fresh world and the same view validate the restart control")
		check(not probe.call("idle_control_validity", "wait", before, after, 7000000, 7000000, 33334).valid,
			"wait control must preserve its original world")
		after.world_id = 1
		check(probe.call("idle_control_validity", "wait", before, after, 7010000, 7000000, 33334).valid,
			"matched wait includes the complete observed gap, not just sample durations")
		check(not probe.call("idle_control_validity", "wait", before, after, 2000000, 7000000, 33334).valid,
			"omitting world-build time invalidates the paired comparison")
		after.camera_yaw = 3.0
		check(not probe.call("idle_control_validity", "wait", before, after, 7000000, 7000000, 33334).valid,
			"a changed view invalidates the idle control")
	if check(probe.has_method("isolate_physical_input"), "scripted FPS probes isolate physical events from action state"):
		load("res://game/input_setup.gd").install()
		var shift := InputEventKey.new()
		shift.physical_keycode = KEY_SHIFT
		shift.pressed = true
		Input.parse_input_event(shift.duplicate())
		Input.flush_buffered_events()
		check(Input.is_action_pressed(&"sprint"), "fixture first reproduces Shift affecting the installed sprint action")
		probe.call("isolate_physical_input")
		Input.parse_input_event(shift.duplicate())
		Input.flush_buffered_events()
		check(not Input.is_action_pressed(&"sprint"), "physical Shift cannot contaminate idle after isolation")
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
		check(Input.is_action_pressed(&"move_forward") and Input.is_action_pressed(&"sprint"),
			"programmatic motion and sprint still reach the normal gameplay actions")
		Input.action_release(&"move_forward")
		Input.action_release(&"sprint")
	_finish()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok

func _finish() -> void:
	print("FPS_PROBE_TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
