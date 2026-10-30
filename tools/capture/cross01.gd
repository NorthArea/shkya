extends SceneTree
## CROSS-01: все переходы в обе стороны штатной камерой пешком и за рулём.

const Layout = preload("res://game/world/layout.gd")

var main: Node
var world: DemoWorld
var out := "res://builds/screenshots/CROSS-01/after"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	create_timer(240.0, true, false, true).timeout.connect(func(): quit(3))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(20)
	world = main.world
	world.stealth.grant_grace(240.0)
	world.player.set_physics_process(false)
	world.car.set_physics_process(false)
	# Транспорт сохраняется в мире, но не успевает сменить место между парными кадрами.
	for vehicle in world.get_node("LevelGeometry/Traffic").vehicles:
		vehicle.set_physics_process(false)
	var plans: Array = world.get_node("LevelGeometry/Crosswalks").crossings()
	for i in plans.size():
		var plan: Dictionary = plans[i]
		var direction: Vector3 = (plan.to - plan.from).normalized()
		var middle: Vector3 = (plan.road_from + plan.road_to) * 0.5
		for reverse in 2:
			var heading: Vector3 = direction if reverse == 0 else -direction
			var origin: Vector3 = plan.from if reverse == 0 else plan.to
			# on_foot остаётся настоящим профилем, со штатной пружиной и её коллизиями.
			world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
			if world.control_mode == &"in_car":
				world.exit_car()
			world.player.set_physics_process(false)
			var yaw := atan2(-heading.x, -heading.z)
			world.player.place(origin, yaw)
			world.camera_rig.follow(world.player, &"on_foot")
			world.camera_rig.yaw = yaw
			world.camera_rig.snap()
			await _frames(18)
			await _photo("%02d_%d_foot" % [i + 1, reverse + 1])
			# Подъезд по улице: смотреть на зебру нужно по направлению дороги, а не вдоль перехода.
			var drive := Vector3(heading.z, 0, -heading.x)
			var car_yaw := atan2(-drive.x, -drive.z)
			world.car.reset_to(middle - drive * 8.0, car_yaw)
			world.enter_car()
			world.camera_rig.yaw = car_yaw
			world.camera_rig.snap()
			await _frames(18)
			await _photo("%02d_%d_car" % [i + 1, reverse + 1])
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	print("CROSS01_CAPTURE: PASS")
	quit(0)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _photo(label: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame.save_png(ProjectSettings.globalize_path(out.path_join(label + ".png"))) != OK:
		push_error("CROSS01_CAPTURE cannot save " + label)
		quit(1)
	print("CROSS01 SHOT ", label, " ", frame.get_size())
