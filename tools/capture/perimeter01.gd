extends SceneTree
## PERIMETER-01: production train gallery and eye-level views of both Lenin exits.
## tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/perimeter01.gd
const Train = preload("res://game/vehicles/er2k_train_visual.gd")
const Materials = preload("res://game/world/materials.gd")
var out := "res://builds/screenshots/PERIMETER-01/art"
var camera: Camera3D
var saved := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(out)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.29, 0.34, 0.40)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.78, 0.85, 0.95)
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	ground.material_override = Materials.snow(0.0)
	ground.position.y = -0.01
	stage.add_child(ground)
	stage.add_child(Train.build_car(true))
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.far = 4000.0
	stage.add_child(camera)
	await process_frame
	var shots := [
		["01_train_front", Vector3(0, 2.3, -19.5), Vector3(0, 2.45, -9.6)],
		["02_train_side", Vector3(-25, 2.9, 0), Vector3(0, 2.45, 0)],
		["03_train_quarter", Vector3(-12.5, 4.3, -22), Vector3(0, 2.4, -4)],
	]
	for shot in shots:
		await _shot(shot)
	stage.queue_free()
	await process_frame
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for frame in 12:
		await physics_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.far = 4000.0
	root.add_child(camera)
	# Eye-level views from playable approach; world geometry/materials unmodified.
	var world_shots := [
		["04_west_exit_approach", Vector3(-65, 1.65, 32), Vector3(-100, 1.65, 32)],
		["05_west_exit_close", Vector3(-86, 1.65, 33), Vector3(-100, 1.8, 33)],
		["06_east_exit_approach", Vector3(62, 1.65, 32), Vector3(99, 1.65, 32)],
		["07_east_exit_close", Vector3(83, 1.65, 32), Vector3(99, 1.8, 32)],
	]
	for shot in world_shots:
		var away: Vector3 = (shot[1] - shot[2]).normalized()
		main.world.player.place(Vector3(shot[1].x + away.x * 3.0, 0, shot[1].z + away.z * 3.0), 0.0)
		await _shot(shot)
	print("INDEPENDENT_ART_CAPTURE: saved=%d failures=%d" % [saved, failures])
	quit(0 if failures == 0 and saved == 7 else 1)

func _shot(shot: Array) -> void:
	camera.global_position = shot[1]
	camera.look_at(shot[2])
	camera.make_current()
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(shot[0] + ".png")
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Cannot save %s: %d" % [path, error])
		failures += 1
	else:
		saved += 1
		print("INDEPENDENT_ART_SHOT ", path)
