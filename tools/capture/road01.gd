extends SceneTree

const Layout = preload("res://game/world/layout.gd")
var main: Node
var world: DemoWorld

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "res://builds/screenshots/ROAD-01/after"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(15)
	world = main.world
	world.stealth.grant_grace(120.0)
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.far = 4000.0
	root.add_child(cam)
	var center := Vector3.ZERO
	for point in Layout.RING: center += point
	center /= float(Layout.RING.size())
	var traffic: Node = world.get_node("LevelGeometry/Traffic")
	for vehicle in traffic.vehicles: vehicle.set_physics_process(false)
	var labels := ["01_A_B", "02_A_D", "03_D_C", "04_C_B"]
	for i in Layout.RING.size():
		var at: Vector3 = Layout.RING[i]
		var side := Vector3(signf(at.x - center.x), 0, signf(at.z - center.z))
		world.player.place(at - side * 10.0, 0.0)
		traffic.trolleybus.setup(traffic.path, traffic.path.offset_of(at))
		traffic.cars[0].setup(traffic.car_path, traffic.car_path.offset_of(at))
		cam.global_position = at - Vector3(side.x * 13.0, -8.0, side.z * 14.0)
		cam.look_at(at - side * 3.5)
		cam.make_current()
		await _frames(12)
		await _view_pair(out, labels[i], traffic)
	cam.global_position = Layout.ROUTE_DRIVE[3] + Vector3(-8, 4.5, 13)
	cam.look_at(Layout.ROUTE_DRIVE[3] + Vector3(10, 0, 0))
	world.player.place(Layout.ROUTE_DRIVE[3] + Vector3(-3, 0, 9), 0.0)
	await _frames(12)
	await _view_pair(out, "05_yard_entry", traffic)
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	cam.queue_free()
	main.queue_free()
	for i in 8: await process_frame
	OS.delay_msec(100)
	await process_frame
	print("ROAD01_CAPTURE: PASS")
	quit(0)

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _view_pair(out: String, label: String, traffic: Node) -> void:
	await _photo(out, label)
	var visibility: Array[bool] = []
	for vehicle in traffic.vehicles:
		visibility.append(vehicle.visible)
		vehicle.hide()
	await _frames(2)
	await _photo(out, label + "_surface")
	for i in traffic.vehicles.size():
		traffic.vehicles[i].visible = visibility[i]

func _photo(out: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var error := frame.save_png(ProjectSettings.globalize_path(out.path_join(label + ".png")))
	if error != OK:
		push_error("ROAD01_CAPTURE cannot save " + label)
		quit(1)
	print("ROAD01 SHOT ", label, " ", frame.get_size())
