extends SceneTree
## TROLLEY-01: кадры троллейбуса с водителем и пассажирами — сбоку на ходу, сзади-сбоку на остановке A с открытыми
## дверями, вплотную к окнам салона, из-за спины Илюши. Каталог вывода — первый аргумент после -- (по умолчанию
## builds/screenshots/TROLLEY-01/). Окно открывать фоном (open -g), рендер настоящий.
var main
var cam: Camera3D
var out := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://builds/screenshots/TROLLEY-01/")
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await physics_frame
	main.menu.start_button.pressed.emit()
	for i in 30: await physics_frame
	var world = main.world
	var traffic = world.get_node("LevelGeometry/Traffic")
	var bus: Trolleybus = traffic.trolleybus
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 4000.0
	root.add_child(cam)
	# Город живёт: жители успевают дойти до остановки и сесть.
	for i in 60 * 40: await physics_frame
	# 1. Сбоку на ходу — со стороны дверей (тротуар), 9 м.
	var stop_a: float = bus.stop_offsets[0]
	bus.setup(traffic.path, fposmod(stop_a - 40.0, traffic.path.length))
	bus.next_stop = 0
	for i in 60 * 3: await physics_frame
	await _follow("01_side_moving", bus, Vector3(9.0, 2.6, 0.0), Vector3(0, 2.1, 0))
	await _follow("02_side_left", bus, Vector3(-8.0, 3.0, -1.0), Vector3(0, 2.1, -1.0))
	# 2. На остановке A: сзади-сбоку, двери открыты.
	var guard := 0
	while bus.dwell_left <= 0.0 and guard < 60 * 30:
		await physics_frame
		guard += 1
	print("TROLLEY01 at stop %d: riders %d, shown %d" % [bus.next_stop, bus.people.riders.size(), bus.people.shown().size()])
	# Игровая камера: Илюша на тротуаре сзади-справа (со стороны дверей), камера за спиной смотрит на троллейбус.
	var stand: Vector3 = bus.global_transform * Vector3(4.0, 0, 11.0)
	var to: Vector3 = bus.global_position - stand
	var yaw := atan2(-to.x, -to.z)
	world.player.place(stand, yaw)
	world.camera_rig.yaw = yaw
	world.camera_rig.pitch = -0.2
	world.camera_rig.snap()
	world.camera_rig.camera.make_current()
	for i in 10: await physics_frame
	await _save("06_game_camera")
	await _follow("03_stop_rear_side", bus, Vector3(7.5, 3.2, 12.0), Vector3(0, 1.8, 0))
	await _follow("04_cabin_close", bus, Vector3(4.0, 2.4, -1.5), Vector3(0, 2.3, -1.0))
	await _follow("05_driver_front", bus, Vector3(2.5, 2.6, -11.0), Vector3(-0.4, 2.3, -5.0))
	main.queue_free()
	for i in 5: await process_frame
	quit(0)

## Камера в осях троллейбуса: offset — точка камеры, look — куда смотрит.
func _follow(name: String, bus: Node3D, offset: Vector3, look: Vector3) -> void:
	cam.make_current()
	cam.global_position = bus.global_transform * offset
	cam.look_at(bus.global_transform * look)
	await _save(name)

func _save(name: String) -> void:
	for i in 2: await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("TROLLEY01 frame ", name)
