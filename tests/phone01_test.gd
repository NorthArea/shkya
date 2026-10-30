extends SceneTree
## PHONE-01: настоящий main/world, ввод телефона, письма и владение паузой.

var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var phone: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	phone = world.get_node_or_null("Phone")
	if not check(phone != null, "Phone is attached to every real DemoWorld"):
		await _finish()
		return
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	await _reading()
	await _blocked()
	await _messages()
	await _intro_gate()
	await _restart()
	await _finish()

func _reading() -> void:
	var before := [world.mission.state, world.mission.money, world.mission.has_bread]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var original_mouse := Input.mouse_mode
	await _key(KEY_P)
	check(phone.is_open() and paused, "P opens the phone and pauses the world")
	check(not main.pause_menu.visible and world.ui_blocking, "phone owns its UI without opening the pause menu")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "phone releases the mouse")
	var ambient: Node = world.get_node("LevelGeometry/Ambient")
	var clock: float = ambient.clock
	await _frames(8)
	check(is_equal_approx(ambient.clock, clock), "the city remains paused while the phone is open")
	var first: int = phone.news_index
	await _key(KEY_DOWN)
	check(phone.news_index == first + 1, "arrow key advances the news")
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(phone.news_index == first + 2, "mouse wheel advances the news")
	await _drag(Vector2(140, 0))
	check(phone.news_index == first + 1, "a rightward drag returns to the previous post")
	var unread_before: int = phone.unread
	await _click(phone.tab_buttons[&"sms"])
	check(phone.tab == &"sms" and phone.unread == unread_before - 1, "SMS tab displays and reads one message")
	await _key(KEY_DOWN)
	check(phone.sms_index == 1 and phone.unread == unread_before - 2, "next SMS is readable and becomes read")
	var saved: Array = phone.inbox.duplicate(true)
	await _key(KEY_P)
	check(not phone.is_open() and not paused and not world.ui_blocking, "P closes the phone and releases only its pause")
	check(Input.mouse_mode == original_mouse, "closing restores the actual mouse mode from before opening")
	await _key(KEY_P)
	check(phone.tab == &"sms" and phone.sms_index == 1 and phone.inbox == saved, "reopening keeps the selected message and read state")
	await _key(KEY_ESCAPE)
	check(not phone.is_open() and not paused and not main.pause_menu.visible, "Escape closes only the phone")
	await _pad(JOY_BUTTON_BACK)
	check(phone.is_open(), "View opens the phone on a gamepad")
	await _pad(JOY_BUTTON_DPAD_LEFT)
	check(phone.tab == &"news", "D-pad left selects news")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(phone.news_index == first + 2, "D-pad down advances the news")
	await _pad(JOY_BUTTON_START)
	check(not phone.is_open() and not main.pause_menu.visible, "Start closes the phone without a pause menu")
	await _pad(JOY_BUTTON_BACK)
	await _pad(JOY_BUTTON_B)
	check(not phone.is_open() and not paused, "B closes the phone")
	await _key(KEY_P)
	await _key(KEY_TAB)
	await _key(KEY_ENTER)
	check(phone.tab == &"sms", "Tab and Enter make both sections accessible using only the keyboard")
	await _key(KEY_ESCAPE)
	check([world.mission.state, world.mission.money, world.mission.has_bread] == before, "reading changes neither mission nor money")

func _blocked() -> void:
	world.control_mode = &"in_car"
	await _key(KEY_P)
	check(not phone.is_open(), "phone cannot open while driving")
	world.control_mode = &"on_foot"
	world.ui_blocking = true
	await _key(KEY_P)
	check(not phone.is_open(), "phone cannot open over a dialog")
	world.ui_blocking = false
	main.set_paused(true)
	await _key(KEY_P)
	check(not phone.is_open() and paused and main.pause_menu.visible, "phone does not steal an existing pause")
	main.set_paused(false)

func _messages() -> void:
	var initial: int = phone.inbox.size()
	world.mission.interact(&"babka")
	world.mission.accept()
	check(phone.inbox.size() == initial + 1, "accepting the bread quest delivers Babka's SMS")
	world.mission.state_changed.emit(MissionDirector.OFFERED, MissionDirector.GO_TO_CAR)
	check(phone.inbox.size() == initial + 1, "repeated mission events do not duplicate an SMS")
	world.mission.notify_entered_car()
	world.mission.notify_arrived_kiosk()
	check(phone.inbox.size() == initial + 2, "arriving at the kiosk delivers the local notice")
	world.mission.add_money(MissionDirector.BREAD_PRICE)
	world.mission.buy_bread()
	check(phone.inbox.size() == initial + 3, "receiving bread delivers a new SMS")
	world.stealth.player_detected.emit()
	world.stealth.player_detected.emit()
	check(phone.inbox.size() == initial + 4, "a patrol detection adds just one notice")
	check(phone.unread >= 4, "new messages remain unread while the phone is closed")
	await _key(KEY_P)
	check(not phone.is_open(), "phone cannot open during the stealth failure")
	world.finish_stealth_fail()
	world.mission.interact(&"babka")
	check(phone.inbox.size() == initial + 4, "the finale does not deliver an SMS that cannot be read")
	await _key(KEY_P)
	check(not phone.is_open(), "phone cannot open over the finale")
	var lines = load("res://game/mission/phone_lines.gd")
	for text: String in lines.all_texts():
		check(not text.to_lower().contains("мобилизац") and not text.to_lower().contains("бусификац"), "phone text follows the game vocabulary")

func _intro_gate() -> void:
	var intro_script = load("res://game/ui/intro.gd")
	intro_script.force_enabled = true
	main.start_game()
	await _frames(10)
	world = main.world
	phone = world.get_node("Phone")
	var intro: Node = world.get_node("Intro")
	await _key(KEY_P)
	check(not phone.is_open() and intro.is_running(), "phone cannot open over the real introduction")
	intro.skip()
	await _frames(60)
	intro_script.force_enabled = false
	await _key(KEY_P)
	check(phone.is_open(), "phone becomes available after skipping the introduction")
	await _key(KEY_P)

func _restart() -> void:
	main.start_game()
	await _frames(12)
	world = main.world
	phone = world.get_node_or_null("Phone")
	check(phone != null and phone.inbox.size() == 2 and phone.unread == 2, "a new game starts a fresh inbox")
	await _key(KEY_P)
	check(phone.is_open(), "new phone opens after a restart")
	main.return_to_menu()
	await _frames(12)
	check(main.world == null and not paused and main.menu.visible, "removing an open phone restores the menu and releases its pause")
	main.start_game()
	await _frames(12)
	world = main.world
	phone = world.get_node_or_null("Phone")
	check(phone != null and not phone.is_open() and not paused, "the next game is active with a closed phone")

func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await _frames(2)

func _pad(button: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		await _frames(2)

func _wheel(button: MouseButton) -> void:
	# Как у настоящего колеса: отпускание освобождает захваченный GUI mouse_focus.
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = down
		event.position = root.get_final_transform() * phone.page_control.get_global_rect().get_center()
		event.global_position = event.position
		Input.parse_input_event(event)
		await _frames(2)

func _drag(delta: Vector2) -> void:
	var at: Vector2 = root.get_final_transform() * phone.page_control.get_global_rect().get_center()
	delta = root.get_final_transform().basis_xform(delta)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.global_position = at
	Input.parse_input_event(down)
	await _frames(2)
	var move := InputEventMouseMotion.new()
	move.position = at + delta
	move.global_position = move.position
	move.relative = delta
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(move)
	await _frames(2)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = at + delta
	up.global_position = up.position
	Input.parse_input_event(up)
	await _frames(2)

func _click(button: Button) -> void:
	var at: Vector2 = root.get_final_transform() * button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await _frames(1)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = down
		Input.parse_input_event(event)
		await _frames(2)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
	return ok

func _finish() -> void:
	paused = false
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	main = null
	world = null
	phone = null
	print("PHONE01: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
