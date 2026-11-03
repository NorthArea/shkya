extends SceneTree

const OUTPUT := "res://builds/screenshots/PERF-HUD-01"
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PERF_HUD_INTEGRATION: " + message)

func frames(count: int) -> void:
	for i in count:
		await process_frame

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(label + ".png")))

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(2))
	AudioServer.set_bus_mute(0, true)
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var main: Node = load("res://game/main.tscn").instantiate()
	main.display_settings_path = "res://builds/checks/PERF-HUD-01/display.cfg"
	main.achievement_path = "res://builds/checks/PERF-HUD-01/achievements.json"
	root.add_child(main)
	await frames(10)
	var overlay: CanvasLayer = main.get_node("PerformanceOverlay")
	check(overlay.panel.is_visible_in_tree(), "real main menu includes visible performance panel")
	check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(overlay.panel.get_global_rect()), "performance panel fits the viewport")
	await shot("menu")
	main.start_game()
	await frames(15)
	var hud: Node = main.world.get_node("GameHUD")
	check(not overlay.panel.get_global_rect().intersects(hud.card.get_global_rect()), "performance panel does not cover the quest")
	check(not overlay.panel.get_global_rect().intersects(hud.suspicion_meter.plate.get_global_rect()), "performance panel does not cover suspicion")
	check(overlay.panel.is_visible_in_tree(), "panel survives world creation")
	await shot("game")
	main.set_paused(true)
	var before: int = overlay.refresh_count
	await create_timer(0.35, true, false, true).timeout
	check(overlay.refresh_count > before, "actual paused main still refreshes telemetry")
	await shot("pause")
	main.set_paused(false)
	await frames(2)
	var phone: Node = main.world.get_node("Phone")
	check(phone.open_phone(), "real phone opens")
	await frames(3)
	print("PERF_HUD_RECTS: panel=%s phone=%s" % [overlay.panel.get_global_rect(), phone.phone_panel.get_global_rect()])
	check(not overlay.panel.get_global_rect().intersects(phone.phone_panel.get_global_rect()), "panel does not cover the phone")
	await shot("phone")
	phone.close_phone()
	# Time only telemetry CPU work, including four-Hz text updates, on real rendered frames.
	overlay.set_process(false)
	var cost_usec := 0
	var max_cost_usec := 0
	for i in 120:
		await process_frame
		var started := Time.get_ticks_usec()
		overlay.sample_at(started)
		var elapsed := Time.get_ticks_usec() - started
		cost_usec += elapsed
		max_cost_usec = maxi(max_cost_usec, elapsed)
	print("PERF_HUD_CPU_SAMPLE: frames=120 mean_us=%.2f max_us=%d; excludes render cost, no global FPS acceptance" % [cost_usec / 120.0, max_cost_usec])
	main.return_to_menu()
	await frames(8)
	check(main.get_node("PerformanceOverlay") == overlay and overlay.panel.is_visible_in_tree(), "world teardown retains one panel")
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player: Node in main.find_children("*", kind, true, false):
			player.stop()
	main.queue_free()
	await frames(5)
	print("PERF_HUD_INTEGRATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
