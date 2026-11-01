extends SceneTree
## Actual menu and pause share one saved rendering preference.
const OUTPUT := "res://builds/screenshots/RESOLUTION-01"
var main: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("RESOLUTION01_UI: " + message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func selected(panel: Node) -> int:
	return int(panel.resolution_option.get_item_metadata(panel.resolution_option.selected))

func choose(panel: Node, width: int) -> void:
	for index in panel.resolution_option.item_count:
		if int(panel.resolution_option.get_item_metadata(index)) == width:
			panel.resolution_option.select(index)
			panel.resolution_option.item_selected.emit(index)
			return
	check(false, "requested resolution exists: %d" % width)

func button(code: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		Input.parse_input_event(event)
		await frames(2)

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(label + ".png")))

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(2))
	AudioServer.set_bus_mute(0, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/checks/RESOLUTION-01"))
	root.size = Vector2i(1920, 1080)
	main = load("res://game/main.tscn").instantiate()
	main.display_settings_path = "res://builds/checks/RESOLUTION-01/ui-%d.cfg" % OS.get_process_id()
	main.achievement_path = "res://builds/checks/RESOLUTION-01/ui-achievements-%d.json" % OS.get_process_id()
	root.add_child(main)
	await frames(5)
	main.menu._open_settings()
	await frames(20)
	var menu: Node = main.menu.settings
	var pause_panel: Node = main.pause_menu.settings
	check(not menu.resolution_option.disabled and menu.resolution_option.item_count >= 3, "actual settings expose valid choices")
	check(root.gui_get_focus_owner() == menu.back_button, "existing settings entry focus is preserved")
	check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(menu.get_global_rect()), "menu settings fit 16:9")
	if DisplayServer.get_name() != "headless":
		await button(JOY_BUTTON_DPAD_DOWN)
		check(root.gui_get_focus_owner() == menu.resolution_option, "controller reaches resolution from Back")
		await button(JOY_BUTTON_A)
		check(menu.resolution_option.get_popup().visible, "A opens the resolution list")
		await button(JOY_BUTTON_B)
		check(menu.visible and not menu.resolution_option.get_popup().visible, "B closes only the list")
	choose(menu, 1280)
	await frames(3)
	check(main.display_settings.render_width == 1280 and is_equal_approx(root.scaling_3d_scale, 1280.0 / 1920.0), "menu selection changes actual rendering resolution")
	check(selected(menu) == 1280 and selected(pause_panel) == 1280, "menu and pause selections agree")
	var config := ConfigFile.new()
	check(config.load(main.display_settings_path) == OK and config.get_value("display", "render_width") == 1280, "menu selection is saved")
	menu._refresh_resolution()
	check(main.display_settings.render_width == 1280, "refresh keeps the saved preference")
	await shot("menu-16x9")
	main.menu._close_settings()
	main.start_game()
	await frames(8)
	root.size = Vector2i(1920, 1200)
	await frames(4)
	main.set_paused(true)
	main.pause_menu._open_settings()
	await frames(20)
	check(paused and pause_panel.visible and selected(pause_panel) == 1280, "same resolution is available in pause")
	check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(pause_panel.get_global_rect()), "pause settings fit 16:10")
	choose(pause_panel, 0)
	await frames(3)
	check(paused and main.display_settings.render_width == 0 and is_equal_approx(root.scaling_3d_scale, 1.0), "native resolution applies without unpausing the game")
	check(selected(menu) == 0 and selected(pause_panel) == 0, "both panels update after paused selection")
	check(config.load(main.display_settings_path) == OK and config.get_value("display", "render_width") == 0, "paused selection is saved")
	await shot("pause-16x10")
	main.set_paused(false)
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player: Node in main.find_children("*", kind, true, false):
			player.stop()
	main.queue_free()
	main = null
	await frames(4)
	OS.delay_msec(100)
	await process_frame
	print("RESOLUTION01_UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
