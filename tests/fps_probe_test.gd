extends SceneTree
## MOTION-01: spikes must remain visible even when the average meets the target.

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var probe: Variant = load("res://tools/fps_probe.gd")
	if not check(probe.has_method("frame_stats"), "FPS runner exposes independently testable raw-frame statistics"):
		_finish()
		return
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
