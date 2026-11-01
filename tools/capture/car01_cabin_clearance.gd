extends SceneTree
const Lada = preload("res://game/vehicles/lada_visual.gd")
var output := "res://builds/screenshots/CAR-01/cabin-before"
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920, 1080)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.29, 0.34)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.4
	stage.add_child(sun)
	var car := Lada.build(Lada.BEIGE, Lada.PLATE, true, 0.1, 0.0)
	stage.add_child(car)
	Lada.set_driver_visible(car, true)
	var camera := Camera3D.new()
	camera.fov = 45
	stage.add_child(camera)
	camera.current = true
	for view in [["exterior_left", Vector3(-3.1, 1.55, -2.9), Vector3(-0.2, 0.95, 0)], ["underbody", Vector3(-2.7, 0.10, -1.8), Vector3(-0.3, 0.40, -0.2)], ["cabin_front", Vector3(0, 1.3, -2.7), Vector3(0, 1.0, -0.15)], ["cabin_inside", Vector3(0.32, 1.24, 0.55), Vector3(-0.3, 0.75, -0.2)], ["roof_above", Vector3(-2.3, 3.1, -2.4), Vector3(0, 1.05, 0)]]:
		camera.position = view[1]
		camera.look_at(view[2])
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(view[0] + ".png"))
	print("CAR01_CAPTURE ", output)
	quit()
