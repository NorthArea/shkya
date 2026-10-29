extends SceneTree
## PAD-01: вся игра только геймпадом на настоящем main.tscn (набор PAD01). Ввод — InputEventJoypadButton и
## InputEventJoypadMotion через Input.parse_input_event, как от настоящего геймпада (раскладка SDL: A, B, X, Start,
## крестовина, стики, курки). Путь: меню (крестовина и стик, A — «НАЧАТЬ») → заставка (пропуск A) → подсказка «X — …» →
## ходьба и камера стиками → пауза Start (стик и крестовина по пунктам, B и A — продолжить) → диалог с Бабкой
## (A дописывает, B — «ОТКАЗАТЬСЯ», пауза над диалогом и возврат фокуса, A — «ПРИНЯТЬ») → удар B, прыжок A → «Лада» X,
## езда курками и стиком → продавщица (реплики A и X, «КУПИТЬ ХЛЕБ» A) → обратно на «Ладе» → Бабка («СДАТЬ ХЛЕБ» A) →
## «ЗАКРЫТЬ» A → «Конец демо» (стик и крестовина, «В МЕНЮ» A) → новый мир → пауза → «В ГЛАВНОЕ МЕНЮ».
## Перемещение пешком между точками квеста — place() (как quest01 «real»); всё остальное — только кнопки и оси.

const Layout = preload("res://game/world/layout.gd")
const IntroScript = preload("res://game/ui/intro.gd")
const PadInput = preload("res://game/ui/pad_input.gd")

## Автопилот quest01_driver, но руль — левый стик, газ и тормоз — курки RT/LT (как игрок с геймпадом).
class PadDriver extends "res://tests/quest01_driver.gd":
	func release_all() -> void:
		_axis(JOY_AXIS_LEFT_X, 0.0)
		_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)

	func _apply_steer(steer: float) -> void:
		_axis(JOY_AXIS_LEFT_X, -_stick(steer))   # руль влево (move_left) — стик влево, ось X отрицательная

	func _throttle(value: float) -> void:
		_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0 if value > 0.0 else 0.0)
		_axis(JOY_AXIS_TRIGGER_LEFT, 1.0 if value < 0.0 else 0.0)

	## Сила действия у Godot — (|ось| − мёртвая зона) / (1 − мёртвая зона): ось подбирается под нужную силу.
	static func _stick(value: float) -> float:
		if absf(value) < 0.001:
			return 0.0
		var dz := InputMap.action_get_deadzone(&"move_left")
		return signf(value) * (dz + (1.0 - dz) * minf(absf(value), 1.0))

	func _axis(axis: JoyAxis, value: float) -> void:
		var motion := InputEventJoypadMotion.new()
		motion.axis = axis
		motion.axis_value = value
		Input.parse_input_event(motion)

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var flow: Node
var hud: CanvasLayer

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: pad01 exceeded 900 simulated seconds")
		quit(2)
	)
	IntroScript.force_enabled = true   # заставка как в игре: её тоже проходим геймпадом
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	_mapping()
	await _menu()
	if world == null:
		_finish()
		return
	await _intro_skip(JOY_BUTTON_A, "A")
	await _hints_and_sticks()
	await _pause()
	await _babka_offer()
	await _punch_and_jump()
	await _car_to_kiosk()
	await _buy_bread()
	await _car_back()
	await _turn_in()
	await _end_card_and_menu()
	_finish()

func _bind() -> void:
	world = main.world
	flow = world.get_node("QuestFlow") if world else null
	hud = world.get_node("GameHUD") if world else null

# --- раскладка ---

func _mapping() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"look_left", &"look_right", &"look_up",
			&"look_down", &"interact", &"jump", &"punch", &"handbrake", &"pause", &"ui_accept", &"ui_cancel",
			&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		var pad := InputMap.action_get_events(action).any(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion)
		check(pad, "map: %s has a gamepad binding" % action)
	check(_has_button(&"ui_accept", JOY_BUTTON_A), "map: A confirms in menus (ui_accept)")
	check(_has_button(&"ui_cancel", JOY_BUTTON_B), "map: B goes back in menus (ui_cancel)")
	check(_has_button(&"interact", JOY_BUTTON_X) and _has_button(&"pause", JOY_BUTTON_START), "map: X — action, Start — pause")
	for action in [&"move_left", &"look_left"]:
		var dz := InputMap.action_get_deadzone(action)
		check(dz >= 0.15 and dz <= 0.35, "map: %s stick dead zone %.2f within 0.15–0.35" % [action, dz])
	check(_has_key(&"ui_accept", KEY_ENTER) and _has_key(&"ui_cancel", KEY_ESCAPE) and _has_key(&"interact", KEY_E),
		"map: keyboard bindings kept (Enter, Esc, E)")

func _has_button(action: StringName, index: JoyButton) -> bool:
	return InputMap.action_get_events(action).any(func(e): return e is InputEventJoypadButton and e.button_index == index)

func _has_key(action: StringName, code: Key) -> bool:
	return InputMap.action_get_events(action).any(func(e): return e is InputEventKey and (e.physical_keycode == code or e.keycode == code))

# --- главное меню ---

func _menu() -> void:
	await _frames(2)
	check(main.menu.visible and _focus_text() == "НАЧАТЬ", "menu: НАЧАТЬ has focus when the menu opens (%s)" % _focus_text())
	await _button(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "НАСТРОЙКИ", "menu: d-pad down → НАСТРОЙКИ (%s)" % _focus_text())
	await _button(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "ВЫХОД", "menu: d-pad down → ВЫХОД (%s)" % _focus_text())
	await _button(JOY_BUTTON_DPAD_UP)
	await _button(JOY_BUTTON_DPAD_UP)
	check(_focus_text() == "НАЧАТЬ", "menu: d-pad up ×2 → НАЧАТЬ (%s)" % _focus_text())
	await _stick_push(JOY_AXIS_LEFT_Y, 1.0)
	check(_focus_text() == "НАСТРОЙКИ", "menu: left stick down → НАСТРОЙКИ (%s)" % _focus_text())
	# Настройки: A открывает таблицу управления, фокус на НАЗАД; B закрывает, фокус снова на НАСТРОЙКИ.
	await _button(JOY_BUTTON_A)
	await _frames(2)
	check(main.menu.settings.visible and not main.menu.card.visible and _focus_text() == "НАЗАД", "settings: A opens the controls table, focus on НАЗАД (%s)" % _focus_text())
	await _button(JOY_BUTTON_B)
	await _frames(2)
	check(not main.menu.settings.visible and main.menu.card.visible and _focus_text() == "НАСТРОЙКИ", "settings: B closes, focus back on НАСТРОЙКИ (%s)" % _focus_text())
	await _stick_push(JOY_AXIS_LEFT_Y, -1.0)
	check(_focus_text() == "НАЧАТЬ", "menu: left stick up → НАЧАТЬ (%s)" % _focus_text())
	check(_focused() is Button and _focus_ring_visible(_focused() as Button), "menu: the focused button draws a visible focus ring")
	await _button(JOY_BUTTON_B)
	check(main.menu.visible and main.world == null, "menu: B does not start or quit")
	await _button(JOY_BUTTON_A)
	await _frames(3)
	_bind()
	check(world != null and not main.menu.visible, "menu: A on НАЧАТЬ starts the game")

# --- заставка ---

func _intro_skip(index: JoyButton, label: String) -> void:
	var intro: Node = world.get_node_or_null("Intro")
	check(intro != null, "intro %s: the intro plays after НАЧАТЬ" % label)
	if intro == null:
		return
	await _frames(30)
	check(intro.is_running() and not world.player.input_enabled, "intro %s: running, input disabled" % label)
	await _button(index)
	var frames := 0
	while is_instance_valid(intro) and intro.is_running() and frames < 60:
		await physics_frame
		frames += 1
	check(not is_instance_valid(intro) or not intro.is_running(), "intro %s: %s skips the intro (%d frames)" % [label, label, frames])
	await _frames(40)
	check(world.player.input_enabled and not paused, "intro %s: control is back after the skip" % label)
	check(not flow.is_dialog_open(), "intro %s: the skip button opened no dialog" % label)

# --- подсказки и стики ---

func _hints_and_sticks() -> void:
	var player := world.player
	check(PadInput.pad_active, "hint: the gamepad is the last used device")
	player.place(Layout.BABKA + Vector3(0, 0, -2.2), PI)
	await _frames(4)
	check(hud.prompt_label.visible and hud.prompt_label.text == "X — ПОГОВОРИТЬ", "hint: HUD shows «X — ПОГОВОРИТЬ» with the gamepad (%s)" % hud.prompt_label.text)
	await _key(KEY_CTRL)
	await _frames(2)
	check(not PadInput.pad_active and hud.prompt_label.text == "E — ПОГОВОРИТЬ", "hint: a keyboard key switches back to «E — ПОГОВОРИТЬ» (%s)" % hud.prompt_label.text)
	await _button(JOY_BUTTON_DPAD_UP)   # вне меню крестовина ничего не делает, но устройство — снова геймпад
	await _frames(2)
	check(PadInput.pad_active and hud.prompt_label.text == "X — ПОГОВОРИТЬ", "hint: a gamepad button switches to «X — …» again")
	check(not flow.is_dialog_open(), "hint: d-pad outside menus opens nothing")
	# Левый стик — ходьба.
	player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await _frames(4)
	var start := player.global_position
	_motion(JOY_AXIS_LEFT_Y, -1.0)
	await _frames(40)
	_motion(JOY_AXIS_LEFT_Y, 0.0)
	await _frames(40)
	var walked := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	check(walked > 1.5, "stick: left stick walks Ilyusha (%.2f m)" % walked)
	var flat := Vector2(player.velocity.x, player.velocity.z).length()
	check(flat < 0.1, "stick: released stick stops Ilyusha (%.2f m/s)" % flat)
	# Мёртвая зона: дрожь стика (0,15) Илюшу не двигает.
	var rest := player.global_position
	_motion(JOY_AXIS_LEFT_X, 0.15)
	await _frames(30)
	_motion(JOY_AXIS_LEFT_X, 0.0)
	check(player.global_position.distance_to(rest) < 0.05, "stick: drift 0.15 stays inside the dead zone")
	# Правый стик — камера.
	var yaw: float = world.camera_rig.yaw
	_motion(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(20)
	_motion(JOY_AXIS_RIGHT_X, 0.0)
	await _frames(2)
	check(absf(angle_difference(world.camera_rig.yaw, yaw)) > 0.3, "stick: right stick turns the camera (%.2f rad)" % angle_difference(world.camera_rig.yaw, yaw))

# --- пауза ---

func _pause() -> void:
	await _button(JOY_BUTTON_START)
	await _frames(2)
	check(paused and main.pause_menu.visible, "pause: Start opens the pause menu")
	check(_focus_text() == "ПРОДОЛЖИТЬ", "pause: ПРОДОЛЖИТЬ has focus (%s)" % _focus_text())
	await _stick_push(JOY_AXIS_LEFT_Y, 1.0)
	check(_focus_text() == "СБРОСИТЬ АВТОМОБИЛЬ", "pause: one push of the left stick moves focus by exactly one item (%s)" % _focus_text())
	await _button(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "НАЧАТЬ ЗАНОВО", "pause: d-pad down → НАЧАТЬ ЗАНОВО (%s)" % _focus_text())
	await _button(JOY_BUTTON_DPAD_UP)
	await _stick_push(JOY_AXIS_LEFT_Y, -1.0)
	check(_focus_text() == "ПРОДОЛЖИТЬ", "pause: back up to ПРОДОЛЖИТЬ (%s)" % _focus_text())
	await _button(JOY_BUTTON_B)
	check(not paused and not main.pause_menu.visible, "pause: B resumes")
	await _button(JOY_BUTTON_START)
	check(paused, "pause: Start pauses again")
	await _button(JOY_BUTTON_START)
	check(not paused and not main.pause_menu.visible, "pause: Start resumes")
	await _button(JOY_BUTTON_START)
	await _frames(2)
	await _button(JOY_BUTTON_A)
	await _frames(2)
	check(not paused and not main.pause_menu.visible and world.player.input_enabled, "pause: A on ПРОДОЛЖИТЬ resumes")

# --- Бабка: предложение ---

func _babka_offer() -> void:
	var mission := world.mission
	var player := world.player
	player.place(Layout.BABKA + Vector3(0, 0, -2.2), PI)
	await _frames(4)
	await _button(JOY_BUTTON_X)
	check(flow.is_dialog_open() and flow.dialog.buttons.has(&"accept"), "offer: X opens Babka's offer")
	check(_focused() == flow.dialog.buttons.get(&"accept"), "offer: ПРИНЯТЬ has focus (%s)" % _focus_text())
	check(flow.dialog.is_typing(), "offer: the line is being typed")
	await _button(JOY_BUTTON_A)
	check(flow.is_dialog_open() and not flow.dialog.is_typing() and mission.state == MissionDirector.OFFERED,
		"offer: A while typing only finishes the line (open %s, typing %s, state %s)" % [flow.is_dialog_open(), flow.dialog.is_typing(), mission.state])
	await _button(JOY_BUTTON_DPAD_RIGHT)
	check(_focus_text() == QuestLines.BUTTON_DECLINE, "offer: d-pad right → ОТКАЗАТЬСЯ (%s)" % _focus_text())
	await _stick_push(JOY_AXIS_LEFT_X, -1.0)
	check(_focus_text() == QuestLines.BUTTON_ACCEPT, "offer: left stick left → ПРИНЯТЬ (%s)" % _focus_text())
	await _button(JOY_BUTTON_B)
	await _frames(2)
	check(not flow.is_dialog_open() and mission.state == MissionDirector.NOT_STARTED and player.input_enabled,
		"offer: B leaves the talk (ОТКАЗАТЬСЯ), input back")
	await _frames(40)   # удар B на выходе из диалога не запускается: кулдаун не нужен, но ждём, чтобы не смешивать
	await _button(JOY_BUTTON_X)
	check(flow.is_dialog_open(), "offer: X opens the offer again")
	await _button(JOY_BUTTON_START)
	await _frames(2)
	check(paused and _focus_text() == "ПРОДОЛЖИТЬ", "offer: Start over the dialog pauses, focus on ПРОДОЛЖИТЬ")
	await _button(JOY_BUTTON_B)
	await _frames(2)
	check(not paused and flow.is_dialog_open(), "offer: B resumes, the dialog stays open")
	check(_focused() == flow.dialog.buttons.get(&"accept"), "offer: focus returns to ПРИНЯТЬ after the pause (%s)" % _focus_text())
	if flow.dialog.is_typing():
		await _button(JOY_BUTTON_A)   # на паузе печать стояла: первое A дописывает
	check(not flow.dialog.is_typing() and flow.is_dialog_open(), "offer: the line is complete, the offer still open")
	var y_before := player.global_position.y
	await _button(JOY_BUTTON_A)
	await _frames(2)
	check(mission.state == MissionDirector.GO_TO_CAR and not flow.is_dialog_open() and player.input_enabled, "offer: A on ПРИНЯТЬ accepts the quest")
	check(player.global_position.y - y_before < 0.05, "offer: the A that accepted does not make Ilyusha jump")

# --- удар и прыжок ---

func _punch_and_jump() -> void:
	var player := world.player
	player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await _frames(30)
	var punches: int = player.punches
	await _button(JOY_BUTTON_B)
	check(player.punches == punches + 1, "foot: B punches")
	await _frames(60)
	var y := player.global_position.y
	await _button(JOY_BUTTON_A)
	await _frames(4)
	check(player.global_position.y > y + 0.1, "foot: A jumps (%.2f m up)" % (player.global_position.y - y))
	await _frames(90)

# --- «Лада» до киоска ---

func _car_to_kiosk() -> void:
	var mission := world.mission
	var player := world.player
	var car: Lada = world.car
	player.place(car.global_position + Vector3(2.2, 0, 0), 0.0)
	await _frames(4)
	check(hud.prompt_label.text == "X — СЕСТЬ В МАШИНУ", "car: «X — СЕСТЬ В МАШИНУ» at the Lada (%s)" % hud.prompt_label.text)
	await _button(JOY_BUTTON_X)
	await _frames(4)
	check(world.control_mode == &"in_car" and mission.state == MissionDirector.DRIVE_TO_KIOSK, "car: X enters the Lada")
	var driver := PadDriver.new(self, world)
	var drove: bool = await driver.drive(Layout.ROUTE_DRIVE.slice(1), 12.0, 6.0)
	check(drove and mission.state == MissionDirector.BUY_BREAD, "car: RT and the left stick drive to the kiosk (state %s)" % mission.state)
	# Ручник B: машина на ходу тормозит быстрее, удара нет (Илюша в машине).
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	var punches: int = player.punches
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_B
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(10)
	check(Input.is_action_pressed(&"handbrake") and player.punches == punches, "car: B holds the handbrake, no punch")
	var release: InputEventJoypadButton = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	check(await driver.stop(), "car: LT stops the Lada")
	await _button(JOY_BUTTON_X)
	await _frames(6)
	check(world.control_mode == &"on_foot", "car: X exits the Lada")
	check(mission.money >= MissionDirector.BREAD_PRICE, "car: coins collected on the way cover the bread (%d ₽)" % mission.money)
	driver.world = null
	driver.tree = null

# --- продавщица ---

func _buy_bread() -> void:
	var mission := world.mission
	world.player.place(Layout.VENDOR_WINDOW, PI * 0.5)
	await _frames(4)
	await _button(JOY_BUTTON_X)
	check(flow.is_dialog_open() and flow.dialog.line_count() > 1, "vendor: X opens the vendor chain (%d lines)" % flow.dialog.line_count())
	var used_x := false
	var steps := 0
	while flow.is_dialog_open() and not flow.dialog.is_last_line() and steps < 20:
		steps += 1
		if flow.dialog.is_typing():
			await _button(JOY_BUTTON_A)   # дописать
			continue
		check_quiet(_focus_text() == QuestLines.BUTTON_NEXT, "vendor: ДАЛЬШЕ has focus between lines")
		var index: int = flow.dialog.line_index()
		if not used_x:
			used_x = true
			await _button(JOY_BUTTON_X)   # X — как E: следующая реплика
			check(flow.dialog.line_index() == index + 1, "vendor: X shows the next line")
		else:
			await _button(JOY_BUTTON_A)   # A — кнопка «ДАЛЬШЕ» в фокусе
			check_quiet(flow.dialog.line_index() == index + 1, "vendor: A on ДАЛЬШЕ shows the next line")
	if flow.dialog.is_typing():
		await _button(JOY_BUTTON_A)
	check(flow.dialog.is_last_line() and _focused() == flow.dialog.buttons.get(&"buy"), "vendor: last line, КУПИТЬ ХЛЕБ has focus (%s)" % _focus_text())
	await _button(JOY_BUTTON_A)
	await _frames(2)
	check(mission.state == MissionDirector.RETURN_HOME and mission.has_bread and not flow.is_dialog_open(), "vendor: A on КУПИТЬ ХЛЕБ buys the bread")

# --- обратно на «Ладе» ---

func _car_back() -> void:
	var player := world.player
	var car: Lada = world.car
	player.place(car.global_position + car.global_basis.x * 2.2, 0.0)
	await _frames(4)
	await _button(JOY_BUTTON_X)
	await _frames(4)
	check(world.control_mode == &"in_car", "back: X re-enters the Lada")
	var driver := PadDriver.new(self, world)
	var turned: bool = await driver.drive(Layout.ROUTE_LEAVE_KIOSK, 8.0, 3.0)
	var back: Array = Layout.ROUTE_DRIVE.slice(0, Layout.ROUTE_DRIVE.size() - 2)
	back.reverse()
	var returned: bool = turned and await driver.drive(back, 12.0, 6.0)
	check(returned, "back: the Lada drove back to the yard on the gamepad")
	check(await driver.stop(), "back: stopped in the yard")
	driver.world = null
	driver.tree = null
	await _button(JOY_BUTTON_X)
	await _frames(6)
	check(world.control_mode == &"on_foot", "back: X exits in the yard")

# --- сдача ---

func _turn_in() -> void:
	var mission := world.mission
	world.player.place(Layout.BABKA + Vector3(0, 0, -2.2), PI)
	await _frames(4)
	check(hud.prompt_label.text == "X — СДАТЬ ЗАДАНИЕ", "turn-in: «X — СДАТЬ ЗАДАНИЕ» at Babka (%s)" % hud.prompt_label.text)
	await _button(JOY_BUTTON_X)
	check(flow.is_dialog_open(), "turn-in: X opens the return chain")
	var steps := 0
	while flow.is_dialog_open() and not flow.dialog.is_last_line() and steps < 20:
		steps += 1
		await _button(JOY_BUTTON_X)   # X: во время печати дописать, после — следующая реплика
	if flow.dialog.is_typing():
		await _button(JOY_BUTTON_X)
	check(flow.dialog.is_last_line() and _focused() == flow.dialog.buttons.get(&"turn_in"), "turn-in: СДАТЬ ХЛЕБ has focus (%s)" % _focus_text())
	await _button(JOY_BUTTON_B)
	check(flow.is_dialog_open() and mission.state == MissionDirector.RETURN_HOME, "turn-in: B does not hand in or close without an exit button")
	await _button(JOY_BUTTON_A)
	await _frames(3)
	check(mission.state == MissionDirector.COMPLETE and hud.completion_panel.visible, "turn-in: A on СДАТЬ ХЛЕБ completes the quest")
	check(_focus_text() == "ЗАКРЫТЬ", "turn-in: ЗАКРЫТЬ has focus (%s)" % _focus_text())
	await _button(JOY_BUTTON_A)
	await _frames(3)
	check(hud.is_end_card_open() and _focus_text() == "ЕЩЁ РАЗ", "turn-in: A on ЗАКРЫТЬ opens «Конец демо», focus on ЕЩЁ РАЗ (%s)" % _focus_text())

# --- «Конец демо» и меню ---

func _end_card_and_menu() -> void:
	await _button(JOY_BUTTON_DPAD_RIGHT)
	check(_focus_text() == "В МЕНЮ", "end: d-pad right → В МЕНЮ (%s)" % _focus_text())
	await _stick_push(JOY_AXIS_LEFT_X, 1.0)
	check(_focus_text() == "ПОГУЛЯТЬ", "end: left stick right → ПОГУЛЯТЬ (%s)" % _focus_text())
	await _button(JOY_BUTTON_DPAD_LEFT)
	await _button(JOY_BUTTON_A)
	await _frames(4)
	check(main.world == null and main.menu.visible, "end: A on В МЕНЮ returns to the main menu")
	await _frames(2)
	check(_focus_text() == "НАЧАТЬ", "end: НАЧАТЬ has focus in the menu again (%s)" % _focus_text())
	await _button(JOY_BUTTON_A)
	await _frames(3)
	_bind()
	check(world != null and world.mission.state == MissionDirector.NOT_STARTED, "again: A on НАЧАТЬ starts a fresh world")
	if world == null:
		return
	await _intro_skip(JOY_BUTTON_B, "B")
	await _button(JOY_BUTTON_START)
	await _frames(2)
	for i in 3:
		await _button(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "НАСТРОЙКИ", "again: d-pad down ×3 → НАСТРОЙКИ (%s)" % _focus_text())
	await _button(JOY_BUTTON_A)
	await _frames(2)
	check(paused and main.pause_menu.settings.visible and _focus_text() == "НАЗАД", "pause settings: A opens, focus on НАЗАД (%s)" % _focus_text())
	await _button(JOY_BUTTON_B)
	await _frames(2)
	check(paused and not main.pause_menu.settings.visible and _focus_text() == "НАСТРОЙКИ", "pause settings: B closes settings, the game stays paused (%s)" % _focus_text())
	await _button(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "В ГЛАВНОЕ МЕНЮ", "again: d-pad down → В ГЛАВНОЕ МЕНЮ (%s)" % _focus_text())
	await _button(JOY_BUTTON_A)
	await _frames(4)
	check(main.world == null and main.menu.visible and not paused, "again: A on В ГЛАВНОЕ МЕНЮ returns to the menu")
	await _frames(2)
	check(_focus_text() == "НАЧАТЬ", "again: НАЧАТЬ has focus (%s)" % _focus_text())
	await _button(JOY_BUTTON_DPAD_DOWN)
	await _button(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "ВЫХОД", "again: ВЫХОД is reachable from the gamepad (not pressed: it quits)")
	# Клавиатура работает как раньше.
	await _key(KEY_UP)
	check(_focus_text() == "НАСТРОЙКИ", "keyboard: the Up arrow still moves the focus")

# --- ввод ---

func _button(index: JoyButton, hold := 2) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = index
	down.pressed = true
	down.pressure = 1.0
	Input.parse_input_event(down)
	await _frames(hold)
	var up := InputEventJoypadButton.new()
	up.button_index = index
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)

func _motion(axis: JoyAxis, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	Input.parse_input_event(motion)

## Один толчок стика, как от настоящего: поток значений на подъёме, дрожь у края и возврат к нулю.
func _stick_push(axis: JoyAxis, direction: float) -> void:
	for v in [0.2, 0.45, 0.62, 0.75, 0.9, 1.0, 0.97, 1.0, 0.99, 0.6, 0.35, 0.1, 0.0]:
		_motion(axis, v * direction)
		await physics_frame
	await _frames(2)

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)

func _focused() -> Control:
	return root.gui_get_focus_owner()

func _focus_text() -> String:
	var focus := _focused()
	return (focus as Button).text if focus is Button and focus.is_visible_in_tree() else "<%s>" % focus

## Рамка фокуса: стиль focus есть и заметно толще обычного (или выходит за кнопку).
func _focus_ring_visible(button: Button) -> bool:
	var focus := button.get_theme_stylebox("focus") as StyleBoxFlat
	var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
	if focus == null or normal == null:
		return false
	return focus.border_width_top >= normal.border_width_top + 2 and focus.expand_margin_top >= 4.0

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

var _quiet_failed := {}
func check_quiet(condition: bool, label: String) -> void:
	if not condition and not _quiet_failed.has(label):
		_quiet_failed[label] = true
		check(false, label)

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	IntroScript.force_enabled = false
	print("PAD01: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
