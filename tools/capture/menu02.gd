extends SceneTree
## MENU-02: реальный фон меню, естественное движение камеры/пакета и настройки.
## tools/run.command --resolution 1920x1080 --fixed-fps 60 --script tools/capture/menu02.gd
const OUT := "res://builds/screenshots/MENU-02"
const TIMES := [0.05, 3.0, 6.0, 8.0, 9.5, 13.0, 16.0, 20.0, 24.0, 28.0, 32.0]
var main: Node
var saved := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	var menu: Node = main.menu
	for t in TIMES:
		while menu._orbit_time < t:
			await process_frame
		await _shot("menu_%05.1f" % menu._orbit_time)
	menu.settings_button.pressed.emit()
	for i in 8:
		await process_frame
	await _shot("settings")
	menu.settings.back_requested.emit()
	for i in 8:
		await process_frame
	await _shot("menu_return")
	main.queue_free()
	for i in 3:
		await process_frame
	OS.delay_msec(100)
	await process_frame
	print("MENU02_CAPTURE: %d frames, %d failures" % [saved, failures])
	quit(0 if failures == 0 and saved == TIMES.size() + 2 else 1)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var path := OUT.path_join(label + ".png")
	if frame.save_png(path) != OK:
		failures += 1
		push_error("Cannot save menu capture: " + path)
	else:
		saved += 1
		print("MENU02_SHOT: " + path)
