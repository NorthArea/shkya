extends SceneTree

const BOOT := "res://game/ui/startup_screen.gd"
const FIXTURE := "res://tests/fixtures/startup_target.tscn"
var failures := 0
var checks := 0

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	print("%s: %s" % ["PASS" if value else "FAIL", message])
	if not value:
		failures += 1

func _run() -> void:
	check(ResourceLoader.exists(BOOT), "startup implementation exists")
	if not ResourceLoader.exists(BOOT):
		print("STARTUP01: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var boot: Control = load(BOOT).new()
	boot.scene_path = FIXTURE
	root.add_child(boot)
	current_scene = boot
	check(boot.start_button.disabled, "start is disabled before threaded load completes")
	boot.start_button.pressed.emit()
	check(current_scene == boot, "early activation cannot leave loading")
	for frame in range(600):
		await process_frame
		if boot.loaded_scene != null:
			break
	check(boot.loaded_scene is PackedScene, "actual threaded fixture loading completes")
	check(not boot.start_button.disabled, "loaded fixture enables start")
	check(boot.start_button.has_focus(), "ready button takes keyboard/gamepad focus")
	for dimensions in [Vector2i(1920, 1080), Vector2i(1920, 1200)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var box: Control = boot.start_button.get_parent()
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(box.get_global_rect()), "content fits %s" % dimensions)
		check(boot.start_button.size.x >= boot.start_button.get_minimum_size().x, "button text fits %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var capture := root.get_texture().get_image()
			DirAccess.make_dir_recursive_absolute("res://builds/screenshots/STARTUP-01")
			check(capture.save_png("res://builds/screenshots/STARTUP-01/startup-%dx%d.png" % [dimensions.x, dimensions.y]) == OK, "native startup frame saved")
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	check(InputMap.action_has_event("ui_accept", accept), "boot installs gamepad A before Main exists")
	var old_boot: WeakRef = weakref(boot)
	root.push_input(accept)
	accept = accept.duplicate()
	accept.pressed = false
	root.push_input(accept)
	check(boot._activated, "real gamepad A reaches focused Control and activates start")
	var bindings_before := {}
	for action in InputMap.get_actions():
		bindings_before[action] = InputMap.action_get_events(action).size()
	load("res://game/input_setup.gd").install()
	var unchanged := true
	for action in InputMap.get_actions():
		unchanged = unchanged and bindings_before.has(action) and bindings_before[action] == InputMap.action_get_events(action).size()
	check(unchanged, "repeated Main-style input install preserves every action binding")
	boot.start_button.pressed.emit()
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.name == "StartupTarget", "one activation hands off to loaded scene")
	check(old_boot.get_ref() == null, "handoff removes boot and its processing")
	current_scene.free()
	current_scene = null
	var retry: Control = load(BOOT).new()
	retry.scene_path = "res://tests/fixtures/absent_startup.tscn"
	root.add_child(retry)
	current_scene = retry
	check(retry.start_button.disabled, "failed resource cannot start")
	check(retry.retry_button.visible, "load failure offers retry")
	retry.scene_path = FIXTURE
	retry.retry_button.pressed.emit()
	for frame in range(600):
		await process_frame
		if retry.loaded_scene != null:
			break
	check(retry.loaded_scene is PackedScene and not retry.start_button.disabled, "retry uses a real loader request and recovers")
	check(not retry.retry_button.visible, "retry action disappears after recovery")
	retry.free()
	print("STARTUP01: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
