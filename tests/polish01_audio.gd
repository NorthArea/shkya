extends SceneTree
## POLISH-01, звук: шаги, мотор, занос, двери, интерфейс, хлеб, финал, фон — на настоящем main.tscn.

const Layout = preload("res://game/world/layout.gd")

var failures: Array[String] = []
var checks := 0
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(300.0, true, false, true).timeout.connect(func():
		push_error("FAIL: audio test exceeded 300 simulated seconds")
		quit(2)
	)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.menu.start_button.pressed.emit()  # настоящая кнопка меню: щелчок вне мира
	check(main.ui_click.playing and main.ui_click.stream == main.UI_CLICK, "main menu button clicks")
	await _frames(10)
	var world: DemoWorld = main.world
	var sound = world.get_node("SoundDirector")
	check(sound.ambience.playing and sound.ambience.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "yard ambience loops from the start")
	check(sound.ENGINE.loop_mode == AudioStreamWAV.LOOP_FORWARD and sound.SKID.loop_mode == AudioStreamWAV.LOOP_FORWARD, "engine and skid streams loop")
	# Шаги.
	world.player.place(Layout.SPAWN, 0.0)
	world.camera_rig.yaw = PI * 0.5
	await _frames(3)
	Input.action_press(&"move_forward")
	await _frames(120)
	Input.action_release(&"move_forward")
	var steps: int = sound.played["step"]
	check(steps >= 6 and steps <= 12, "footsteps while walking ~8 m: %d" % steps)
	world.player.place(Layout.SPAWN + Vector3(0, 0, -5), 0.0)
	await _frames(30)
	check(sound.played["step"] == steps, "teleport and standing still make no steps")
	# Машина: дверь, мотор, высота тона, занос.
	world.car.reset_to(Vector3(-80, 0, 32), -PI * 0.5)
	world.enter_car()
	await _frames(5)
	check(sound.played["door_close"] == 1, "door sound when getting in")
	check(sound.engine.playing, "engine runs with a driver")
	check(sound.played["radio"] == 0 and sound.radio_text() == "", "radio waits a moment after the door (EXT-01)")
	var idle_pitch: float = sound.engine.pitch_scale
	Input.action_press(&"move_forward")
	await _frames(150)
	var fast_pitch: float = sound.engine.pitch_scale
	check(fast_pitch > idle_pitch + 0.5, "engine pitch rises with speed (%.2f → %.2f)" % [idle_pitch, fast_pitch])
	check(not sound.skid.playing, "no skid sound driving straight")
	check(sound.played["radio"] == 1 and sound.radio.stream == sound.RADIO, "radio mumble once after getting in (EXT-01, stage 2)")
	check(sound.radio_text() == QuestLines.RADIO and sound.subtitle_card.visible, "radio subtitle line on screen: '%s'" % sound.radio_text())
	check(sound.radio.volume_db < sound.engine.volume_db, "radio is quieter than the engine (muffled)")
	check(world.player.input_enabled == false and world.control_mode == &"in_car" and world.car.speed_kmh() > 5.0, "radio does not block driving")
	Input.action_press(&"handbrake")
	Input.action_press(&"move_left")
	var skid_heard := false
	for i in 40:
		await physics_frame
		skid_heard = skid_heard or sound.skid.playing
	_release_all()
	check(skid_heard, "slush skid sound in a handbrake drift")
	var frames := 0
	await _press(&"interact")
	while world.control_mode == &"in_car" and frames < 400:
		await physics_frame
		frames += 1
	await _frames(3)
	check(sound.played["door_open"] == 1 and not sound.engine.playing, "door sound and engine off after exit")
	await _frames(400)
	check(sound.radio_text() == "" and not sound.subtitle_card.visible, "radio subtitle gone after %.0f s" % QuestLines.RADIO_SECONDS)
	world.player.place(world.car.global_position + world.car.global_basis.x * 2.2, 0.0)
	await _frames(4)
	await _press(&"interact")
	await _frames(60)
	check(world.control_mode == &"in_car" and sound.played["radio"] == 1 and sound.radio_text() == "", "re-entering the car plays no second radio line")
	await _press(&"interact")
	frames = 0
	while world.control_mode == &"in_car" and frames < 400:
		await physics_frame
		frames += 1
	await _frames(3)
	# Интерфейс, хлеб, финал.
	world.player.place(Layout.BABKA + Vector3(0, 0, -2.2), 0.0)
	await _frames(4)
	await _press(&"interact")
	var flow = world.get_node("QuestFlow")
	if flow.is_dialog_open() and flow.dialog.buttons.has(&"accept"):
		flow.dialog.buttons[&"accept"].pressed.emit()
	await _frames(3)
	check(sound.played["ui"] >= 1, "dialog button click sound")
	var mission := world.mission
	mission.notify_entered_car()
	mission.notify_arrived_kiosk()
	# Покупка через настоящую кнопку диалога продавщицы: щелчок не должен оборвать звон.
	# EXT-01: первый подход — цепочка реплик, «ДАЛЬШЕ» тоже щёлкает; кнопка покупки на последней.
	mission.add_money(mission.money_missing())   # монеты — COINS: 35 ₽ собраны (сбор проверяет tests/coins_test.gd)
	world.player.place(Layout.VENDOR_WINDOW, 0.0)
	await _frames(4)
	await _press(&"interact")
	var clicks_before: int = sound.played["ui"]
	while flow.is_dialog_open() and not flow.dialog.is_last_line():
		flow.dialog.finish_typing()
		flow.dialog.buttons[&"next"].pressed.emit()
	check(sound.played["ui"] == clicks_before + 4, "ДАЛЬШЕ clicks four times through the vendor chain (%d)" % (sound.played["ui"] - clicks_before))
	if flow.is_dialog_open() and flow.dialog.buttons.has(&"buy"):
		flow.dialog.buttons[&"buy"].pressed.emit()
	await _frames(2)
	check(sound.played["bread"] == 1, "bread chime once on purchase")
	check(sound.chime.stream == sound.BREAD and sound.ui.stream == sound.UI_CLICK, "button click does not replace bread chime")
	mission.interact(&"babka")
	await _frames(2)
	check(sound.played["complete"] == 1, "quest complete jingle once")
	mission.interact(&"babka")
	await _frames(2)
	check(sound.played["complete"] == 1, "no second jingle on repeated talk")
	# Пауза останавливает звук мира.
	var position_before: float = sound.ambience.get_playback_position()
	await _frames(30)
	var advanced: float = sound.ambience.get_playback_position() - position_before
	if advanced <= 0.0:
		print("NOT_RUN: audio playback does not advance with this audio driver; pause check needs a real device")
	else:
		main.set_paused(true)
		main.ui_click.stop()
		(main.pause_menu.find_children("*", "Button", true, false)[0] as Button).pressed.emit()
		check(main.ui_click.playing, "pause menu button clicks while paused")
		main.set_paused(true)
		var paused_at: float = sound.ambience.get_playback_position()
		await _frames(30)
		check(absf(sound.ambience.get_playback_position() - paused_at) < 0.05, "pause freezes world sound")
		main.set_paused(false)
	_finish()

func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)

func _release_all() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"handbrake"]:
		Input.action_release(action)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	print("AUDIO: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	for i in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)
