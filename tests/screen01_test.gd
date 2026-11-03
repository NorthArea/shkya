extends SceneTree
## Native aspect/resize regression; launch through run.command or with --windowed.
const OUTPUT := "res://builds/screenshots/SCREEN-01"
var main: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("SCREEN01: " + message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("SCREEN01 needs a native renderer; headless cannot establish letterboxing")
		quit(2)
		return
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(2))
	AudioServer.set_bus_mute(0, true)
	check(ProjectSettings.get_setting("display/window/stretch/aspect", "keep") == "expand", "viewport expands without aspect bars")
	if "--fullscreen-probe" in OS.get_cmdline_user_args():
		var screen_size := DisplayServer.screen_get_size(root.current_screen)
		var deadline := Time.get_ticks_msec() + 3000
		while root.size.x != screen_size.x and Time.get_ticks_msec() < deadline:
			await frames(1)
		check(root.mode == Window.MODE_FULLSCREEN and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "the Mac really entered fullscreen")
		check(root.size.x == screen_size.x and root.size.y >= screen_size.y * 0.9, "fullscreen reached display width and macOS usable height")
		var fullscreen_scale := root.get_stretch_transform().get_scale()
		# Expand rounds the logical canvas to whole pixels on Retina displays.
		var canvas := root.get_visible_rect().size
		check(absf(fullscreen_scale.x - fullscreen_scale.y) * maxf(canvas.x, canvas.y) <= 1.0, "fullscreen retains proportions within one output pixel")
		check(root.get_stretch_transform().origin.length() < 1.0, "fullscreen has no letterbox offset")
		check((root.get_visible_rect().size * fullscreen_scale).distance_to(Vector2(root.size)) < 2.0, "fullscreen canvas covers the available display")
		print("SCREEN01_FULLSCREEN: window=", root.size, " canvas=", root.get_visible_rect().size)
		print("SCREEN01: %d checks, %d failures" % [checks, failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/SCREEN-01/profile.json"
	root.add_child(main)
	await frames(3)
	check(root.mode == Window.MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "native QA deliberately stays windowed after the OS mode notification")
	main.start_game()
	await frames(8)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var world: Node = main.world
	var hud: Node = world.get_node("GameHUD")
	var phone: Node = world.get_node("Phone")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for requested: Vector2i in [Vector2i(960, 540), Vector2i(960, 600), Vector2i(1260, 540)]:
		root.size = requested
		await frames(8)
		var canvas := root.get_visible_rect().size
		var stretch := root.get_stretch_transform()
		var scale := stretch.get_scale()
		var label := "%dx%d" % [requested.x, requested.y]
		check(root.size == requested, label + " OS window has the requested aspect")
		check(absf(scale.x - scale.y) < 0.00001, label + " circles/fonts/world retain proportions")
		check(stretch.origin.length() < 1.0, label + " no letterbox offset")
		check((canvas * scale).distance_to(Vector2(root.size)) < 1.0, label + " canvas covers every window pixel")
		check(hud._canvas_size().distance_to(canvas) < 0.01, label + " target projection uses the expanded canvas")
		check(hud.minimap.position.distance_to(Vector2(34, canvas.y - 292)) < 0.1, label + " minimap stays bottom-left")
		check(hud.speed_gauge.position.distance_to(canvas - Vector2(280, 280)) < 0.1, label + " speed gauge stays bottom-right")
		check(hud.speed_gauge.size.distance_to(Vector2(240, 240)) < 0.1, label + " speed gauge keeps a square shape")
		check(hud.suspicion_meter.plate.position.distance_to(Vector2(canvas.x - 276, 112)) < 0.1, label + " suspicion follows the right edge below performance")
		check(not main.get_node("PerformanceOverlay").panel.get_global_rect().intersects(hud.suspicion_meter.plate.get_global_rect()), label + " performance does not cover suspicion")
		var map_point: Vector2 = hud.minimap.position + hud.minimap.size * 0.5
		check(hud._avoid_hud(map_point).y < hud.minimap.position.y, label + " marker avoids the relocated minimap")
		var speed_point: Vector2 = hud.speed_gauge.position + hud.speed_gauge.size * 0.5
		check(hud._avoid_hud(speed_point).y < hud.speed_gauge.position.y, label + " marker avoids the relocated gauge")
		check(phone.open_phone(), label + " actual phone opens")
		await frames(2)
		check(Rect2(Vector2.ZERO, canvas).encloses(phone.phone_panel.get_global_rect()), label + " phone fits the expanded screen")
		phone.close_phone()
		await frames(2)
		print("SCREEN01_VIEW: ", label, " canvas=", canvas, " scale=", scale, " offset=", stretch.origin)
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(label + ".png")))
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player: Node in main.find_children("*", kind, true, false):
			player.stop()
	main.queue_free()
	main = null
	await frames(4)
	OS.delay_msec(100)
	await process_frame
	print("SCREEN01: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
