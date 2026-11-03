extends SceneTree
## Real Main lifecycle, existing environment and CameraRig profiles; no FPS claim.
const OUTPUT := "res://builds/screenshots/HERO-2D-01/main"
var main: Node
var world: DemoWorld
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	create_timer(50.0).timeout.connect(func(): quit(2))
	AudioServer.set_bus_mute(0, true)
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for frame in 30:
		await physics_frame
	world = main.world
	world.stealth.grant_grace(120.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	assert(world.player.visual.get_node("Look").sprite != null)
	await _save("01_spawn_game_camera")
	world.enter_car()
	for frame in 20:
		await physics_frame
	assert(world.control_mode == &"in_car" and not world.player.visible)
	assert(world.car.visual.get_node("Body/Driver").visible)
	assert(world.car.visual.get_node("Body/Driver").sprite != null)
	await _save("02_enter_car_game_camera")
	assert(world.exit_car())
	for frame in 20:
		await physics_frame
	assert(world.player.visible and not world.car.visual.get_node("Body/Driver").visible)
	await _save("03_exit_car_game_camera")
	print("HERO2D_MAIN_CAPTURE: real spawn/enter/exit PASS; 3 frames; FPS NOT_MEASURED")
	main.free()
	quit()
func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(label + ".png")))
	assert(error == OK)
