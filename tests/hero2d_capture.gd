extends SceneTree
const Player = preload("res://game/player/ilyusha.gd")
const Car = preload("res://game/vehicles/lada_visual.gd")
const OUTPUT := "res://builds/screenshots/HERO-2D-01"
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280, 900)
	var fixture := Node3D.new()
	root.add_child(fixture)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("9aaeb9")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	fixture.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	fixture.add_child(sun)
	var floor := MeshInstance3D.new()
	floor.mesh = PlaneMesh.new()
	floor.mesh.size = Vector2(30, 30)
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color("d9e4e8")
	floor.mesh.material = snow
	fixture.add_child(floor)
	var player := Player.new()
	fixture.add_child(player)
	player.set_physics_process(false)
	var camera := Camera3D.new()
	fixture.add_child(camera)
	camera.current = true
	camera.fov = 45
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	camera.position = Vector3(0, 1.45, -4.3)
	camera.look_at(Vector3(0, 0.8, 0))
	await _save("01_front")
	camera.position = Vector3(4.3, 1.45, 0)
	camera.look_at(Vector3(0, 0.8, 0))
	await _save("02_side")
	player.visible = false
	var car := Car.build()
	fixture.add_child(car)
	Car.set_driver_visible(car, true)
	camera.position = Vector3(-2.4, 1.5, -2.6)
	camera.look_at(Vector3(-0.2, 0.9, -0.2))
	await _save("03_driver")
	fixture.free()
	print("HERO2D_CAPTURE: 3 frames; isolated diagnostic light; FPS NOT_MEASURED")
	quit()
func _save(label: String) -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(label + ".png")))
	assert(error == OK)
