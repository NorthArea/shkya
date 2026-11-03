extends SceneTree

var failures := 0
var checks := 0
var main_count := 0

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	node_added.connect(_isolate_main)
	_run.call_deferred()

func _isolate_main(node: Node) -> void:
	if node.name == "Main" and node.get_script() != null and node.get_script().resource_path == "res://game/main.gd":
		main_count += 1
		node.set("achievement_path", "res://builds/checks/STARTUP-01/qa-achievements.json")
		node.set("display_settings_path", "res://builds/checks/STARTUP-01/qa-display.cfg")
		node.set("audio_settings_path", "res://builds/checks/STARTUP-01/qa-audio.cfg")

func check(condition: bool, message: String) -> void:
	checks += 1
	print("%s: %s" % ["PASS" if condition else "FAIL", message])
	if not condition:
		failures += 1

func _run() -> void:
	var retry: Control = load("res://game/ui/startup_screen.gd").new()
	retry.scene_path = "res://tests/fixtures/absent_startup_acceptance.tscn"
	root.add_child(retry)
	check(retry.retry_button.visible and retry.retry_button.has_focus(), "failure offers focused retry for keyboard/gamepad navigation")
	check(retry.start_button.disabled and not retry._loading, "failure keeps start disabled and stops polling")
	retry.scene_path = "res://tests/fixtures/startup_target.tscn"
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter)
	var enter_release := InputEventKey.new()
	enter_release.keycode = KEY_ENTER
	enter_release.pressed = false
	root.push_input(enter_release)
	check(retry._loading, "actual Enter press/release activates focused retry button")
	for frame in range(600):
		await process_frame
		if retry.loaded_scene != null:
			break
	check(retry.loaded_scene != null and not retry.retry_button.visible and retry.start_button.has_focus(), "retry performs threaded loading and restores start focus")
	retry.free()
	var boot: Control = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(boot)
	current_scene = boot
	check(boot.scene_path == "res://game/main.tscn", "project boot targets real main scene")
	check(boot.loaded_scene == null and boot.start_button.disabled, "no loaded Main or enabled start before actual threaded request finishes")
	check(root.find_children("MainMenu", "", true, false).is_empty(), "no menu instantiated during loading")
	for frame in range(1800):
		await process_frame
		if boot.loaded_scene != null:
			break
	check(boot.loaded_scene != null and boot.loaded_scene.resource_path == "res://game/main.tscn", "real Main completes threaded loading")
	check(boot.progress_bar.value == 100 and not boot.start_button.disabled, "completed load reaches 100 and enables start")
	check(boot.start_button.has_focus(), "ready start has default keyboard/gamepad focus")
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	check(InputMap.action_has_event("ui_accept", accept), "gamepad A mapped to ui_accept before Main installation")
	var old_boot: WeakRef = weakref(boot)
	accept.pressed = true
	root.push_input(accept)
	var release := InputEventJoypadButton.new()
	release.button_index = JOY_BUTTON_A
	release.pressed = false
	root.push_input(release)
	check(boot._activated, "actual gamepad A press/release activates focused startup button")
	boot.start_button.pressed.emit()
	for frame in range(10):
		await process_frame
	check(main_count == 1, "double activation instantiates Main once")
	check(old_boot.get_ref() == null, "startup fully freed after real handoff")
	check(current_scene != null and current_scene.name == "Main", "real Main is current scene")
	check(current_scene.get("world") == null, "handoff does not start a gameplay World")
	check(root.find_children("MainMenu", "", true, false).size() == 1, "exactly one previous MainMenu exists")
	check(root.find_children("MenuBackdrop", "", true, false).size() == 1, "exactly one menu backdrop exists")
	check(current_scene.get("menu").visible, "previous menu is visible")
	check(current_scene.get("achievement_path").begins_with("res://builds/checks/STARTUP-01/"), "owner achievement profile isolated before Main ready")
	check(current_scene.get("display_settings").get("config_path").begins_with("res://builds/checks/STARTUP-01/"), "owner display profile isolated before Main ready")
	check(current_scene.get("audio_settings").get("config_path").begins_with("res://builds/checks/STARTUP-01/"), "owner audio profile isolated before Main ready")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://builds/checks/STARTUP-01/independent-menu-handoff.png") == OK, "native real menu handoff captured")
	current_scene.free()
	current_scene = null
	await process_frame
	print("STARTUP01_ACCEPTANCE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
