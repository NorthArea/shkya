extends SceneTree
## PUNCH-02: естественные подлёты и движение с игровой камерой; затем отдельная явно поставленная
## витрина силуэта с 5/10/20 м (размер/облик настоящие, камера с игровым FOV, полёт в витрине заморожен).
## tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/punch02_view.gd -- <output>

var main: Node
var world: DemoWorld
var drones: Node3D
var output := "res://builds/screenshots/PUNCH-02/view"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(12)
	world = main.world
	drones = world.get_node("LevelGeometry/Drones")
	world.stealth.grant_grace(900.0)
	for view in [
		["yard", Vector3(-16, 0, 85), 0.0],
		["street_b", Vector3(59.5, 0, -15), 0.0],
		["kiosk", Vector3(60, 0, -51), PI * 0.5],
	]:
		world.player.place(view[1], view[2])
		world.camera_rig.follow(world.player, &"on_foot")
		world.camera_rig.yaw = view[2]
		world.camera_rig.snap()
		var watching := false
		for frame in 1200:
			await physics_frame
			for drone: Node3D in drones.drones:
				if drone.state == &"hover":
					watching = true
			if watching:
				break
		print("PUNCH02_VIEW natural ", view[0], " hover=", watching)
		await _save(String(view[0]) + "_rear")
		# Четыре поворота за одну естественную фазу осмотра; состояния/таймеры дрона не меняются.
		for yaw in [PI * 0.5, PI, -PI * 0.5, 0.0]:
			world.camera_rig.yaw = float(view[2]) + yaw
			world.camera_rig.snap()
			await _frames(30)
			await _save("%s_orbit_%03d" % [view[0], int(rad_to_deg(yaw)) + 180])
		# Настоящий ввод ходьбы, дрон следует с обычным FOLLOW_SPEED.
		Input.action_press(&"move_forward")
		await _frames(45)
		await _save(String(view[0]) + "_walking")
		Input.action_release(&"move_forward")
		await _frames(90)
	# Машина пересекает те же петли: дроны не подлетают к скрытому водителю.
	world.car.reset_to(Vector3(-6, 0, 42), -PI * 0.5)
	world.player.place(world.car.global_position + Vector3(1.5, 0, 0), 0.0)
	await _frames(3)
	world.enter_car()
	Input.action_press(&"move_forward")
	await _frames(60)
	await _save("street_a_driving")
	Input.action_release(&"move_forward")
	world.exit_car()
	await _frames(3)
	# Отдельная постановочная витрина: один дрон над петлёй улицы Б, городской фон/свет настоящие.
	drones.set_physics_process(false)
	world.camera_rig.set_physics_process(false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = CameraRig.PROFILES[&"on_foot"]["fov"]
	camera.make_current()
	var model: Node3D = drones.drones[2]
	model.global_position = Vector3(59.4, 2.1, -20)
	model.rotation.y = PI
	model.state = &"patrol"
	for distance: float in [5.0, 10.0, 20.0]:
		camera.global_position = model.global_position + Vector3(0, 0.4, distance).normalized() * distance
		camera.look_at(model.global_position)
		for phase in [0.03, 0.33]:
			model.timer = phase - model.phase
			model.animate(0.0, 2.8)
			model.aim(1.0, true, Vector3.INF)
			await _frames(3)
			await _save("staged_%02dm_%s" % [int(distance), "red" if phase < 0.1 else "blue"])
	main.queue_free()
	await _frames(6)
	print("PUNCH02_VIEW capture complete; visual acceptance is separate")
	quit(0)

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output.path_join(label + ".png")
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("PUNCH02_VIEW cannot save " + path)
		quit(1)
		return
	var states: Array = []
	for drone: Node3D in drones.drones:
		if drone.global_position.distance_to(world.player.global_position) < 12.0:
			states.append([String(drone.name), String(drone.state), drone.global_position])
	print("PUNCH02_VIEW ", label, " camera=", world.get_viewport().get_camera_3d().global_position, " near=", states)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
