extends SceneTree
## Кадры greybox: make capture → builds/screenshots/grey01/. Окно 1920×1080, настоящий рендер.

const Layout = preload("res://game/world/layout.gd")

const SHOTS := [
	# имя, точка Илюши, yaw камеры, pitch камеры
	["01_spawn", Layout.SPAWN, PI, -0.30],
	["04_car", Vector3(-44, 0, 94), 2.4, -0.30],
	["05_yard_exit", Vector3(-5, 0, 62), 0.0, -0.25],
	["05_street_a", Vector3(10, 0, 32), -PI * 0.5, -0.25],
	["05_street_b", Vector3(68, 0, -20), 0.0, -0.25],
	["06_kiosk", Vector3(66, 0, -70), 0.9, -0.25],
]

var output_dir := "res://builds/screenshots/grey01"

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	await _save("00_menu")
	main.start_game()
	for i in 3:
		await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var world: DemoWorld = main.world
	for shot in SHOTS:
		world.player.place(shot[1], shot[2])
		world.camera_rig.yaw = shot[2]
		world.camera_rig.pitch = shot[3]
		world.camera_rig.snap()
		for i in 30:
			await physics_frame
		await _save(shot[0])
	# Вид сверху на весь квартал.
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 260.0
	top.far = 400.0
	top.position = Vector3(0, 200, 0)
	top.rotation = Vector3(-PI * 0.5, 0, 0)
	world.add_child(top)
	top.current = true
	await _save("99_top")
	main.queue_free()
	await process_frame
	quit(0)

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(output_dir.path_join(name + ".png"))
	root.get_texture().get_image().save_png(path)
	print("CAPTURE: ", path)
