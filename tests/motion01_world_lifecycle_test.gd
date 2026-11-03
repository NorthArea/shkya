extends SceneTree
## Real Main transitions with the production city/light composition. Native log
## must also be inspected: renderer ERR_PRINT does not make Godot exit nonzero.

const MAIN := preload("res://game/main.tscn")
const IntroScript := preload("res://game/ui/intro.gd")
var _main: Node
var _started := 0
var _intro_number := 0
var _checks := 0
var _failures := 0
var _world_ids: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("MOTION_LIFECYCLE_NOT_RUN: requires native renderer")
		quit(2)
		return
	# The owner keeps working during visible diagnostics. The sequence is driven
	# by Main's real methods, not by keyboard/gamepad events delivered to the UI.
	root.gui_disable_input = true
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	IntroScript.force_enabled = "--intro" in OS.get_cmdline_user_args()
	_started = Time.get_ticks_usec()
	print("MOTION_LIFECYCLE_CONTEXT ", JSON.stringify({"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(), "display": DisplayServer.get_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "main_sha256": FileAccess.get_sha256("res://game/main.gd"),
		"menu_sha256": FileAccess.get_sha256("res://game/ui/main_menu.gd"),
		"provider_sha256": FileAccess.get_sha256("res://game/characters/imported_hero_visual.gd")}))
	_main = MAIN.instantiate()
	root.add_child(_main)
	await _settle(1.0)
	_trace("menu_ready")
	if not _expect(_main.world == null, "initial menu has no game world"):
		quit(3)
		return
	_trace("start_1_request")
	_main.start_game()
	await _settle(1.0)
	_trace("world_1_ready")
	if not _world_ready():
		quit(3)
		return
	await _finish_intro()
	_trace("restart_request")
	_main.start_game()
	await _settle(1.0)
	_trace("world_2_ready")
	if not _world_ready():
		quit(3)
		return
	await _finish_intro()
	_trace("return_menu_request")
	_main.return_to_menu()
	await _settle(1.0)
	_trace("menu_returned")
	if not _expect(_main.world == null, "return-to-menu removes the game world"):
		quit(3)
		return
	_trace("start_3_request")
	_main.start_game()
	await _settle(1.0)
	_trace("world_3_ready")
	if not _world_ready():
		quit(3)
		return
	await _finish_intro()
	_trace("main_free_request")
	_main.queue_free()
	for i in 8:
		await process_frame
	_expect(not is_instance_valid(_main), "Main is freed after its queued teardown")
	_expect(not IntroScript.force_enabled or _intro_number == 3, "forced intro ran for every production world")
	print("MOTION_LIFECYCLE_DONE: transitions complete; native error log is the renderer oracle")
	print("MOTION01_WORLD_LIFECYCLE: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _world_ready() -> bool:
	if not _expect(is_instance_valid(_main.world), "new production world exists"):
		return false
	var identity: int = _main.world.get_instance_id()
	_expect(identity not in _world_ids, "restart instantiates a fresh world")
	_world_ids.append(identity)
	var soft_shadow_lights := 0
	for node in _main.world.find_children("*", "Light3D", true, false):
		if node is not DirectionalLight3D and node.shadow_enabled and node.light_size > 0.0:
			soft_shadow_lights += 1
	_expect(soft_shadow_lights > 0, "production soft shadows are active")
	return true

func _expect(ok: bool, label: String) -> bool:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("MOTION_LIFECYCLE_FAIL: " + label)
	return ok

func _finish_intro() -> void:
	var intro: Node = _main.world.get_node_or_null("Intro")
	if intro == null:
		_expect(not IntroScript.force_enabled, "a forced intro cannot be silently skipped")
		return
	_intro_number += 1
	_trace("intro_before_skip")
	if _intro_number == 1 and "--capture-marker" in OS.get_cmdline_user_args():
		await _capture_marker("intro-hidden")
	if "--mixed" in OS.get_cmdline_user_args() and _intro_number == 2:
		_trace("intro_active_at_cancel")
		return
	if "--mixed" in OS.get_cmdline_user_args() and _intro_number == 1:
		# The complete timeline is covered by INTRO. Here the original terminal
		# natural-finish branch is rendered before the same native teardown.
		intro.elapsed = intro.duration - 0.2
	else:
		intro.skip()
	await _settle(0.8)
	_trace("intro_after_skip")
	if _intro_number == 1 and "--capture-marker" in OS.get_cmdline_user_args():
		await _capture_marker("intro-restored")

func _capture_marker(label: String) -> void:
	var marker: Label3D = _main.world.quest_flow.marker
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = 45.0
	root.add_child(camera)
	camera.global_position = marker.global_position + Vector3(0, 0, 5)
	camera.look_at(marker.global_position)
	camera.make_current()
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://builds/screenshots/MOTION-01/softshadow"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join(label + ".png")
	var error := root.get_texture().get_image().save_png(path)
	print("MOTION_LIFECYCLE_MARKER ", JSON.stringify({"image": path, "save_error": error,
		"text": marker.text, "visible": marker.visible, "layers": marker.layers,
		"transparency": marker.transparency, "projected": str(camera.unproject_position(marker.global_position))}))
	_main.world.camera_rig.camera.make_current()
	camera.queue_free()

func _settle(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds * 1_000_000.0)
	while Time.get_ticks_usec() < deadline:
		await process_frame
	# Deferred world creation may itself exceed the requested time. Always give
	# its first complete render a chance before the next lifecycle operation.
	for i in 4:
		await process_frame

func _trace(stage: String) -> void:
	var lights := 0
	var soft := 0
	var geometry := 0
	for node in _main.find_children("*", "Node3D", true, false):
		if node is Light3D:
			lights += 1
			if node is not DirectionalLight3D and node.light_size > 0.0:
				soft += 1
		elif node is GeometryInstance3D:
			geometry += 1
	print("MOTION_LIFECYCLE_STAGE ", JSON.stringify({"stage": stage,
		"elapsed_us": Time.get_ticks_usec() - _started, "world_exists": is_instance_valid(_main.world),
		"world_id": _main.world.get_instance_id() if is_instance_valid(_main.world) else 0,
		"lights": lights, "soft_lights": soft, "geometry": geometry, "paused": paused,
		"marker_layers": _main.world.quest_flow.marker.layers if is_instance_valid(_main.world) else -1,
		"marker_transparency": _main.world.quest_flow.marker.transparency if is_instance_valid(_main.world) else -1}))
