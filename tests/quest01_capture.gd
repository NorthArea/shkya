extends SceneTree
## QUEST-01: кадры десяти шагов в настоящем окне → builds/screenshots/quest01/NN_*.png.
## Запуск: tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/quest01_capture.gd

const Layout = preload("res://game/world/layout.gd")
const OUT := "res://builds/screenshots/quest01"

var main: Node
var world: DemoWorld

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.menu.start_button.pressed.emit()
	await _frames(30)
	world = main.world
	var flow: Node = world.get_node("QuestFlow")
	var mission := world.mission
	var player := world.player
	var near_babka := Layout.BABKA + Vector3(0, 0, -2.2)

	# 01: двор, задача «Подойди к Бабке», ! над Бабкой
	world.camera_rig.yaw = PI
	await _frames(40)
	await _shot("01_spawn")

	# 02: у Бабки, открыт диалог выдачи
	player.place(near_babka, PI)
	world.camera_rig.yaw = 0.35
	await _frames(40)
	await _press_interact()
	await _frames(20)
	await _shot("02_offer_dialog")

	# 03: принято
	flow.dialog.buttons[&"accept"].pressed.emit()
	await _frames(40)
	await _shot("03_accepted")

	# 04: у машины, вход по E
	var car = world.car
	player.place(car.global_position + Vector3(-2.2, 0, 0), -PI * 0.5)
	world.camera_rig.yaw = -PI * 0.5
	await _frames(40)
	await _shot("04_at_car")
	await _press_interact()
	await _frames(30)

	# 05: едем
	Input.action_press(&"move_forward")
	await _frames(100)
	await _shot("05_drive")
	Input.action_release(&"move_forward")

	# 06: прибытие к киоску (машина ставится на площадку)
	car.reset_to(Layout.ROUTE_DRIVE[-1], PI * 0.5)
	world.camera_rig.yaw = PI * 0.5
	await _frames(40)
	await _shot("06_arrive_kiosk")

	# 07: вышли, диалог продавщицы
	await _press_interact()
	await _frames(20)
	player.place(Layout.VENDOR_WINDOW, PI * 0.5)
	world.camera_rig.yaw = -PI * 0.5
	await _frames(40)
	await _press_interact()
	await _frames(20)
	await _shot("07_vendor_dialog")

	# 08: хлеб куплен — «ХЛЕБ +1»
	flow.dialog.buttons[&"buy"].pressed.emit()
	await _frames(20)
	await _shot("08_bread_toast")

	# 09: вернулись к Бабке, над ней ?
	await _frames(130)
	player.place(near_babka, PI)
	world.camera_rig.yaw = 0.35
	await _frames(40)
	await _shot("09_return_babka")

	# 10: сдача
	await _press_interact()
	await _frames(20)
	await _shot("10_complete")
	print("CAPTURE done: ", mission.state, " xp=", mission.xp)
	main.queue_free()
	await process_frame
	quit(0)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT, label])
	image.save_png(path)
	print("SHOT ", path, " ", image.get_size())

func _press_interact() -> void:
	var down := InputEventAction.new()
	down.action = &"interact"
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(3)
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
