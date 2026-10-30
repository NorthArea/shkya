extends SceneTree
## Естественная жизнь: меняется только положение героя и его игровой камеры.
## Жители/транспорт не переставляются, планы и часы не ускоряются вручную.

const Layout = preload("res://game/world/layout.gd")
const VIEWS := [
	["Z01_entrance", Vector3(-39, 0, 101), PI],
	["Z02_parking", Vector3(-39, 0, 92), PI * 0.5],
	["Z03_playground", Vector3(-50, 0, 86), PI * 0.5],
	["Z04_yard", Vector3(-24, 0, 76), PI],
	["Z05_domino", Vector3(1, 0, 101), -1.1],
	["Z06_rink", Vector3(62, 0, 85), PI],
	["Z07_worksite", Vector3(9, 0, 46), -2.0],
	["Z08_shawarma", Vector3(68, 0, 43.3), 2.0],
	["Z09_h3", Vector3(-40, 0, 63), 0.0],
	["Z10_pharmacy", Vector3(-79, 0, 20), 0.0],
	["Z11_press", Vector3(-7, 0, 22.5), 0.95],
	["Z12_corner_ab", Vector3(57.5, 0, 22), -PI * 0.5],
	["Z13_street_b", Vector3(59.5, 0, -15), 0.0],
	["Z14_kiosk", Vector3(55, 0, -51), 0.0],
	["Z15_inner_yard", Vector3(-43, 0, -28), -PI * 0.5],
	["Z16_dog", Vector3(37, 0, -68), PI],
	["Z17_shop_d", Vector3(-70.5, 0, -40), -PI * 0.5],
	["Z18_h11", Vector3(-73.5, 0, -63), PI * 0.5],
	["Z19_trade_c", Vector3(5, 0, -109.5), PI * 0.5],
	["Z20_north_d", Vector3(-73.5, 0, -120), PI],
]
var main: Node
var world: DemoWorld
var output := "res://builds/screenshots/ARENA-03/vibe"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(12)
	world = main.world
	world.stealth.grant_grace(900.0)
	var start := Engine.get_physics_frames()
	var people: Node = world.get_node("LevelGeometry/Residents")
	for seconds in [30, 180, 360]:
		while Engine.get_physics_frames() - start < seconds * Engine.physics_ticks_per_second:
			await physics_frame
		for view in VIEWS:
			world.player.place(view[1], view[2])
			world.camera_rig.follow(world.player, &"on_foot")
			world.camera_rig.yaw = view[2]
			world.camera_rig.snap()
			await _frames(8)
			await RenderingServer.frame_post_draw
			var label := "t%03d_%s" % [seconds, view[0]]
			var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(label + ".png")))
			if error != OK:
				push_error("ARENA03_VIBE cannot save " + label)
				quit(1)
				return
			var visible_near := 0
			for resident: Resident in people.residents:
				if not resident.hidden and resident.is_visible_in_tree() and resident.global_position.distance_to(view[1]) < 30.0:
					visible_near += 1
			print("ARENA03_VIBE ", label, " elapsed=", float(Engine.get_physics_frames() - start) / Engine.physics_ticks_per_second, " residents_30m=", visible_near)
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	main.queue_free()
	await _frames(6)
	OS.delay_msec(100)
	await process_frame
	print("ARENA03_VIBE: PASS")
	quit(0)

func _frames(count: int) -> void:
	for i in count: await physics_frame
