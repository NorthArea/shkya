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
	var entry_path: String = ProjectSettings.get_setting("application/run/main_scene")
	check(entry_path == "res://game/main.tscn", "project opens the existing menu before the loading screen")
	if entry_path != "res://game/main.tscn":
		print("STARTUP01_ACCEPTANCE: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var main: Node = load(entry_path).instantiate()
	root.add_child(main)
	current_scene = main
	check(main.menu.visible and main.world == null, "menu is visible before any gameplay world")
	check(main.get("startup_screen") == null, "loading screen is absent before menu Start")
	check(not ResourceLoader.has_cached("res://game/world/demo_world.tscn"), "menu does not preload gameplay PackedScene")
	main.menu.start_requested.emit()
	main.menu.start_requested.emit()
	await process_frame
	await process_frame
	var boot: Control = main.get("startup_screen")
	check(boot != null, "menu Start opens embedded loading screen")
	if boot == null:
		main.free()
		quit(1)
		return
	check(not main.menu.visible and main.menu.backdrop == null, "loading replaces menu and releases its backdrop")
	check(main.world == null, "menu Start does not create world before ready confirmation")
	check(boot.scene_path == "res://game/world/demo_world.tscn", "threaded loader targets the actual gameplay scene")
	check(main.find_children("StartupScreen", "", true, false).size() == 1, "duplicate menu Start creates one loader")
	if boot.loaded_scene == null:
		boot.start_button.pressed.emit()
		check(main.world == null, "early ready activation cannot create gameplay")
	for frame in range(1800):
		await process_frame
		if boot.loaded_scene != null:
			break
	check(boot.loaded_scene != null and boot.loaded_scene.resource_path == "res://game/world/demo_world.tscn", "real gameplay scene completes threaded loading")
	check(boot.progress_bar.value == 100 and not boot.start_button.disabled, "actual completed load enables ready button at 100 percent")
	check(main.world == null and boot.start_button.has_focus(), "loaded world waits for focused ready confirmation")
	var old_boot: WeakRef = weakref(boot)
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	root.push_input(accept)
	var release := InputEventJoypadButton.new()
	release.button_index = JOY_BUTTON_A
	release.pressed = false
	root.push_input(release)
	check(boot._activated, "actual gamepad A activates ready button")
	boot.start_button.pressed.emit()
	for frame in range(4):
		await process_frame
	check(main_count == 1 and current_scene == main, "ready keeps the existing Main instead of replacing it")
	check(old_boot.get_ref() == null and main.get("startup_screen") == null, "ready fully frees embedded loader")
	check(main.world != null and main.world.get_parent() == main, "ready creates gameplay world under existing Main")
	check(root.find_children("DemoWorld", "", true, false).size() == 1, "double ready creates exactly one world")
	check(main.get("achievement_path").begins_with("res://builds/checks/STARTUP-01/"), "owner achievement profile isolated")
	main.pause_menu.restart_requested.emit()
	await process_frame
	await process_frame
	check(main.world == null and main.get("startup_screen") != null, "restart also waits at the loading screen")
	main.return_to_menu()
	await process_frame
	await process_frame
	check(main.menu.visible and main.get("startup_screen") == null and main.world == null, "return to menu cancels pending loading handoff")
	main.start_game()
	await process_frame
	await process_frame
	check(main.world != null and main.get("startup_screen") == null, "direct start_game remains available to existing headless checks")
	for player in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	current_scene.free()
	current_scene = null
	for frame in range(4):
		await process_frame
	print("STARTUP01_ACCEPTANCE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
