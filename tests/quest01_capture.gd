extends SceneTree
## QUEST-01: кадры десяти шагов в настоящем окне → builds/screenshots/quest01/NN_*.png.
## Композиция каждого кадра повторяет концепт docs/art/concepts/NN_*.png (камера за Илюшей, Бабка/машина/киоск в кадре).
## Кадр 05 и дорога до киоска — настоящая езда «Лады» автопилотом (tests/quest01_driver.gd).
## Дополнительно в окне проверяется режим мыши после Esc при открытом диалоге (MOUSE_CHECK).
## Запуск: tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/quest01_capture.gd

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/quest01_driver.gd")
const OUT := "res://builds/screenshots/quest01"

var main: Node
var world: DemoWorld
var mouse_ok := true

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
	var car: Lada = world.car
	var driver := Driver.new(self, world)
	var near_babka := Layout.BABKA + Vector3(1.5, 0, -1.9)

	# 01: двор, «Подойди к Бабке», ! над Бабкой, ромб на неё
	await _place(Layout.SPAWN, Layout.SPAWN_YAW, Layout.SPAWN_YAW)   # ракурс первого кадра игры (POLISH-02, п. 5)
	await _shot("01_spawn")

	# 02: у Бабки, подсказка «E — ПОГОВОРИТЬ»
	await _place(near_babka, PI, PI)
	await _shot("02_talk_prompt")

	# 03: диалог выдачи; заодно проверка мыши: Esc, ПРОДОЛЖИТЬ, клик по миру
	await _press_interact()
	await _frames(60)  # реплика печатается ≈40 знаков/с (POLISH-02) — снимать допечатанной
	await _shot("03_offer_dialog")
	_press_action(&"pause")
	await _frames(3)
	main.pause_menu.resume_requested.emit()
	await _frames(3)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await _frames(3)
	mouse_ok = Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and flow.is_dialog_open() and world.ui_blocking
	print("MOUSE_CHECK ", "PASS" if mouse_ok else "FAIL", " mode=", Input.mouse_mode, " dialog=", flow.is_dialog_open())
	flow.dialog.buttons[&"accept"].pressed.emit()
	await _frames(3)
	print("MOUSE_CHECK after close ", "PASS" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "FAIL", " mode=", Input.mouse_mode)

	# 04: у машины, «Сядь в машину», подсказка «E — СЕСТЬ В МАШИНУ»
	await _place(car.global_position + Vector3(-1.9, 0, 1.2), 0.0, -0.45)
	await _shot("04_at_car")
	await _press_interact()
	await _frames(30)

	# 05: настоящая езда по маршруту
	var route: Array = Layout.ROUTE_DRIVE.slice(1)
	await driver.drive(route.slice(0, 3), 12.0, 6.0)
	# Кадр — на ходу вдоль улицы A (панельки, валы, фонари), а не в стену дома на выезде (POLISH-02, п. 22).
	await driver.drive([Vector3(28, 0, 32)], 12.0, 6.0)
	await _shot("05_drive")
	await driver.drive(route.slice(3), 12.0, 6.0)
	await driver.stop()
	await _press_interact()
	await _frames(10)

	# 06: вышли у киоска, идём к продавщице
	await _place(Layout.VENDOR_WINDOW + Vector3(3.0, 0, 1.5), PI * 0.5, PI * 0.5)
	await _shot("06_arrive_kiosk")

	# 07: диалог продавщицы
	await _place(Layout.VENDOR_WINDOW + Vector3(0.6, 0, 0), PI * 0.5, PI * 0.5)
	await _press_interact()
	await _frames(60)  # реплика печатается ≈40 знаков/с (POLISH-02) — снимать допечатанной
	await _shot("07_vendor_dialog")

	# 08: хлеб куплен — карточка «ХЛЕБ +1» справа сверху
	flow.dialog.buttons[&"buy"].pressed.emit()
	await _frames(20)
	await _shot("08_bread_toast")

	# 09: у Бабки, над ней ?, подсказка «E — СДАТЬ ЗАДАНИЕ»
	await _frames(130)
	await _place(near_babka, PI, PI)
	await _shot("09_return_babka")

	# 10: сдача — реплика над Бабкой и панель финала внизу
	await _press_interact()
	await _frames(20)
	await _shot("10_complete")
	print("CAPTURE done: ", mission.state, " xp=", mission.xp)
	driver.world = null
	driver.tree = null
	main.queue_free()
	# Несколько кадров: AudioServer освобождает остановленные воспроизведения не сразу,
	# иначе выход сразу после звука финала даёт «resources still in use at exit».
	for i in 10:
		await process_frame
	quit(0 if mouse_ok else 1)

func _place(point: Vector3, facing: float, camera_yaw: float) -> void:
	world.player.place(point, facing)
	world.camera_rig.yaw = camera_yaw
	await _frames(45)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT, label])
	image.save_png(path)
	print("SHOT ", path, " ", image.get_size())

func _press_action(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)

func _press_interact() -> void:
	_press_action(&"interact")
	await _frames(3)
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
