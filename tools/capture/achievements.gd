extends SceneTree
## ACHIEVE-01 visuals use an isolated collection, never the owner's user:// save.

const OUT := "res://builds/screenshots/ACHIEVE-01"
const SAVE := "res://builds/checks/ACHIEVE-01/capture.json"
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(SAVE + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE + suffix))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = SAVE
	root.add_child(main)
	await _frames(4)
	main.menu._open_settings()
	main.menu.settings._open_achievements()
	await _shot("01_locked_collection")
	main.menu.settings._close_achievements()
	main.menu._close_settings()
	main.start_game()
	await _frames(10)
	var world: DemoWorld = main.world
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	var residents: Node = world.get_node("LevelGeometry/Residents")
	var grannies: Array = residents.residents.filter(func(r): return r.voice == &"babka")
	world.car.velocity = Vector3(9, 0, 0)
	grannies[0].knock()
	grannies[1].knock()
	await _frames(3)
	await _shot("02_unlocked_notification")
	var breakables: Node = world.get_node("LevelGeometry/Breakables")
	for object in breakables.objects:
		if object.kind in [&"birch", &"poplar", &"rowan"]:
			object.smash(&"car", Vector3.RIGHT)
			break
	main.set_paused(true)
	main.pause_menu._open_settings()
	main.pause_menu.settings._open_achievements()
	await _shot("03_pause_collection")
	main.pause_menu.settings._close_achievements()
	main.pause_menu._close_settings()
	main.return_to_menu()
	await _frames(5)
	main.menu._open_settings()
	main.menu.settings._open_achievements()
	await _shot("04_persistent_collection")
	main.quit_game()

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _shot(stem: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUT.path_join(stem + ".png"))
	if error != OK:
		push_error("ACHIEVE-01 capture: " + error_string(error))
