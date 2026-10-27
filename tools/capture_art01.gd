extends SceneTree
## Кадры ART-01: Илюша с четырёх сторон и в ходьбе, Бабка с четырёх сторон, продавщица в окне киоска,
## сцены 01/02/06/07 → builds/screenshots/art01/. Окно 1920×1080, настоящий рендер:
## ./tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture_art01.gd

const Layout = preload("res://game/world/layout.gd")
const OUT := "res://builds/screenshots/art01"

var world: DemoWorld

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main.start_game()
	for i in 3:
		await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world = main.world
	# Илюша в открытом месте двора: камера обходит его, сам он смотрит на юг (yaw = PI).
	var spot := Vector3(-20, 0, 70)
	for side in [["ilyusha_back", 0.0], ["ilyusha_front", PI], ["ilyusha_left", PI * 0.5], ["ilyusha_right", -PI * 0.5]]:
		await _shot(side[0], spot, PI, PI + side[1], -0.15)
	# Ходьба боком: несколько шагов вдоль оси x, камера сбоку.
	world.player.place(spot, -PI * 0.5)
	world.camera_rig.yaw = 0.0
	world.camera_rig.pitch = -0.15
	world.camera_rig.snap()
	for i in 13:
		world.player.global_position += Vector3(0.075, 0, 0)
		await process_frame
	await _save("ilyusha_walk_side")
	# Бабка с четырёх сторон: Илюша в 3 м от неё лицом к ней, камера за Илюшей.
	for side in [["babka_front", Vector3(0, 0, -3.2)], ["babka_left", Vector3(-3.2, 0, 0)], ["babka_right", Vector3(3.2, 0, 0)]]:
		var at: Vector3 = Layout.BABKA + side[1]
		var to_babka: Vector3 = Layout.BABKA - at
		var yaw := atan2(-to_babka.x, -to_babka.z)
		# Илюша на шаг в сторону, чтобы не закрывать Бабку от камеры.
		at += to_babka.normalized().cross(Vector3.UP) * 1.4
		await _shot(side[0], at, yaw, yaw, -0.2)
	# Сцены кадров 01, 02 (09), 06, 07.
	await _shot("scene01_spawn", Layout.SPAWN, PI, PI, -0.30)
	await _shot("scene02_babka", Layout.BABKA + Vector3(0.6, 0, -4.5), PI, PI, -0.22)
	await _shot("scene06_kiosk", Vector3(66, 0, -70), 0.9, 0.9, -0.25)
	await _shot("scene07_window", Layout.VENDOR_WINDOW + Vector3(1.8, 0, 0.6), PI * 0.5, PI * 0.5 + 0.35, -0.12)
	main.queue_free()
	for i in 5:
		await process_frame
	quit(0)

func _shot(name: String, at: Vector3, facing: float, camera_yaw: float, pitch: float) -> void:
	world.player.place(at, facing)
	world.camera_rig.yaw = camera_yaw
	world.camera_rig.pitch = pitch
	world.camera_rig.snap()
	for i in 20:
		await physics_frame
	await _save(name)

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT.path_join(name + ".png"))
	root.get_texture().get_image().save_png(path)
	print("CAPTURE: ", path)
