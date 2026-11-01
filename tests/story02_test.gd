extends SceneTree
## STORY-02: независимые сценарии по demo_update.md/DECISIONS, без новых состояний миссии.
## Ожидания: радио уступает предупреждению/гэгу и сохраняет единственную первую погоду за мир;
## реальные события отражаются в восьми фактических строках, классификация вынесена отдельно;
## новый мир очищает передачи/уведомления/счётчики. C7 и полный маршрут — существующие наборы.

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")

var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var drv

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func():
		push_error("FAIL: STORY02 exceeded 240 simulated seconds")
		quit(2))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	await _fresh()
	await _radio_priority()
	await _fresh()
	await _protocol_events()
	await _fresh()
	await _reset_world()
	await _finish()

func _fresh() -> void:
	main.start_game()
	await _frames(12)
	world = main.world
	drv = Driver.new(self, main)
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false

func _radio_priority() -> void:
	var sound = world.get_node("SoundDirector")
	world.player.place(Layout.BABKA + Vector3(0, 0, -2.2), 0.0)
	await _frames(4)
	await drv.interact()
	check(world.quest_flow.dialog.buttons.has(&"accept"), "real Babka dialog offers acceptance")
	if not world.quest_flow.dialog.buttons.has(&"accept"):
		return
	world.quest_flow.dialog.buttons[&"accept"].pressed.emit()
	await _frames(2)
	check(sound.gag_playing() and not world.ui_blocking and world.player.input_enabled, "Babka warning follows acceptance without blocking walking")
	var hud = world.get_node("GameHUD")
	check(hud.coin_counter_label.text == "%d / %d" % [world.mission.money, MissionDirector.BREAD_PRICE], "accepted quest reveals the real wallet and price target (%s)" % hud.coin_counter_label.text)
	var earning: String = hud.coins_label.text.to_lower()
	check(hud.coins_row.visible and earning.contains("монет") and earning.contains("дрон") and (earning.contains("хлам") or earning.contains("предмет")), "HUD names coins, drones and breakable objects as earning sources")
	check(not earning.contains("35") and not earning.contains("0/"), "earning explanation does not duplicate the numeric target")
	world.car.reset_to(Vector3(-80, 0, 32), -PI * 0.5)
	world.enter_car()
	await _frames(60)
	check(sound.radio_shown == 0 and sound.gag_playing(), "first radio does not replace Babka warning on early car entry")
	check(not paused and not world.ui_blocking and world.control_mode == &"in_car", "warning and pending radio leave driving active")
	await _wait_radio_tuning(sound)
	await _wait_first_weather(sound)
	var limit := 1200
	while sound.radio_text() != QuestLines.RADIO and limit > 0:
		await _frames(1)
		limit -= 1
	check(limit > 0 and sound.radio_shown == 1, "welcome transmission follows warning once")
	check(sound.played["radio"] == 1 and sound.radio.playing and not sound.car_radio.player.playing and sound.radio.stream.data == sound.RADIO.data, "welcome uses one original mumbling announcer with its caption")
	check(sound.car_radio.music.player.playing and sound.car_radio.music.target_db() == sound.car_radio.music.DUCK_DB and sound.car_radio.music.player.volume_db > -40.0, "welcome ducks the music toward an audible bed")
	# Общий production-opener создаёт настоящий DialogPanel и включает UI-blocking.
	# Проверяется приоритет общей плашки, а не доступность разговора из машины.
	world.quest_flow._open_chain(QuestLines.VENDOR_CHAIN, [{"id": &"close", "text": "ЗАКРЫТЬ"}], &"vendor")
	await _frames(120)
	check(world.quest_flow.dialog.is_open() and world.ui_blocking and not sound.subtitle_card.visible and sound.radio_text() == "", "an open dialog hides an already active radio transmission")
	world.quest_flow._close()
	await _frames(2)
	check(sound.radio_text() == QuestLines.RADIO and sound.radio_shown == 1 and sound.radio.playing and not sound.car_radio.player.playing, "welcome resumes caption and its single announcer after dialog without consuming another transmission")
	# Настоящий потребитель общей плашки: гэг появляется во время первой передачи.
	sound.show_gag(["Проверка очереди города"], 1.5)
	await _frames(2)
	check(sound.gag_playing() and sound.radio_text() == "", "a situational gag takes priority over active radio")
	await _frames(720)
	check(sound.radio_shown == 1 and sound.radio_text() == "" and not sound.radio.playing, "one weather transmission finishes without the cancelled progress bulletin")
	check(world.exit_car(), "exit after first weather")
	await _frames(3)
	world.enter_car()
	await _wait_radio_tuning(sound)
	await _frames(360)
	check(sound.radio_shown == 1 and sound.radio_text() == "", "re-entry does not replay completed weather")

func _protocol_events() -> void:
	var mission := world.mission
	var coins = world.get_node("LevelGeometry/Coins")
	var residents = world.get_node("LevelGeometry/Residents")
	var drones = world.get_node("LevelGeometry/Drones")
	var breakables = world.get_node("LevelGeometry/Breakables")
	var finale = world.quest_flow.finale
	var hud = world.get_node("GameHUD")
	# Счётчики меняются реальными командами компонентов, без записи самих итоговых значений.
	for point: Vector3 in Layout.COIN_POINTS:
		if point.y == 0.0 and coins.collected_count < 3:
			world.player.place(point, 0.0)
			await _frames(3)
	check(coins.collected_count >= 3, "real pickups contribute to the final statistics")
	residents.residents[0].knock()
	drones.break_drone(drones.drones[0])
	breakables.objects[0].smash(&"punch", Vector3.FORWARD)
	world.stealth.alert_now()
	await _frames(2)
	check(world.stealth.detections == 1 and world.is_stealth_failing(), "a real detection enters the existing failure flow")
	check(world.finish_stealth_fail(), "existing checkpoint retry completes")
	await _frames(3)
	var stats: Dictionary = finale.stats()
	check(stats["knocks"] == 1 and stats["drones"] == 1 and stats["broken"] == 1 and stats["detections"] == 1, "checkpoint keeps already counted arcade events and detection")
	mission.interact(&"babka")
	mission.accept()
	mission.notify_entered_car()
	mission.notify_arrived_kiosk()
	mission.add_money(mission.money_missing() + 7)
	check(mission.buy_bread(), "existing 35-ruble purchase succeeds")
	var remaining := mission.money
	check(not mission.buy_bread() and mission.money == remaining, "purchase remains one-time")
	world.player.place(Layout.BABKA + Vector3(0, 0, -2.2), 0.0)
	await _frames(4)
	await drv.interact()
	var dialog = world.quest_flow.dialog
	for index in 10:
		if not dialog.is_open() or dialog.is_last_line():
			break
		dialog.finish_typing()
		dialog.advance()
		await _frames(2)
	dialog.finish_typing()
	check(dialog.buttons.has(&"turn_in"), "return conversation reaches bread handover")
	if not dialog.buttons.has(&"turn_in"):
		return
	dialog.buttons[&"turn_in"].pressed.emit()
	await _frames(2)
	check(mission.state == MissionDirector.COMPLETE and mission.xp == 50 and not mission.has_bread, "handover preserves COMPLETE, bread clearing and 50 XP")
	check(not hud.completion_panel.visible and not world.get_hud_state()["protocol_ready"], "protocol waits for Babka's final conversation")
	await _frames(ceili(maxf(QuestLines.THANKS_PAUSE, QuestLines.read_seconds(QuestLines.THANKS)) * 60.0) + 3)
	check(world.quest_flow.thanks_after_back.visible and not hud.completion_panel.visible, "second Babka bubble gets its reading time before protocol")
	await _frames(ceili(QuestLines.read_seconds(QuestLines.THANKS_AFTER) * 60.0) + 5)
	check(hud.completion_panel.visible, "protocol appears after both final bubbles")
	var protocol: Dictionary = world.get_hud_state()["protocol"]
	check(protocol.size() == 8 and hud.protocol_values.size() == 8, "all eight actual result rows reach the displayed protocol")
	check(protocol[&"coins"] == "%d ₽" % coins.collected_count and protocol[&"spent"] == "35 ₽" and protocol[&"left"] == "%d ₽" % mission.money, "protocol shows actual collected, spent and remaining money")
	check(protocol[&"knocks"].begins_with("1") and protocol[&"drones"] == "1" and protocol[&"broken"] == "1" and protocol[&"detections"].begins_with("1 "), "protocol preserves counted events after retry")
	check(protocol[&"time"] != "0:00", "protocol time is measured during this playthrough")
	for id in protocol:
		check(hud.protocol_values[id].text == protocol[id], "HUD displays actual value for %s" % id)
	var classification: Label = hud.completion_panel.find_child("Classification", true, false)
	check(classification != null and classification.visible and classification.text.contains("доступность") and classification.text.contains("возможностей") and classification.text.to_lower().contains("оценка"), "official classification appears separately from actual result values")
	mission.interact(&"babka")
	check(mission.xp == 50 and mission.money == remaining, "repeat handover cannot duplicate rewards or charges")

func _reset_world() -> void:
	var sound = world.get_node("SoundDirector")
	var phone = world.get_node("Phone")
	var stats: Dictionary = world.quest_flow.finale.stats()
	check(sound.radio_shown == 0 and sound.radio_text() == "" and not sound.gag_playing(), "new world clears radio and warning presentation")
	check(phone.inbox.size() == 2 and phone.unread == 2 and not phone.is_open(), "new world clears detour and quest notifications")
	check(stats["coins"] == 0 and stats["knocks"] == 0 and stats["drones"] == 0 and stats["broken"] == 0 and stats["detections"] == 0, "new world starts fresh actual counters")
	check(world.mission.money == 0 and world.mission.xp == 0 and world.mission.state == MissionDirector.NOT_STARTED, "new world resets mission, money and XP")
	check(world.get_hud_state()["money_goal"] == 0 and world.get_hud_state()["coins_task"] == "", "new world hides the future bread target again")
	world.car.reset_to(Vector3(-80, 0, 32), -PI * 0.5)
	world.enter_car()
	await _wait_radio_tuning(sound)
	await _wait_first_weather(sound)
	check(sound.radio_shown == 1 and sound.radio_text() == QuestLines.RADIO, "fresh world can show the welcome again")
	check(sound.radio.playing and not sound.car_radio.player.playing, "fresh world's welcome has one announcer")

## AudioServer завершает настройку по реальным аудиочасам, даже при --fixed-fps.
func _wait_radio_tuning(sound: Node) -> void:
	var cue: AudioStreamPlayer = sound.car_radio.music.tuning
	var deadline_ms: int = Time.get_ticks_msec() + ceili(cue.stream.get_length() * 1000.0) + 1500
	while (cue.playing or not sound.car_radio.music._tuned) and Time.get_ticks_msec() < deadline_ms:
		OS.delay_msec(10)
		await process_frame
	check(not cue.playing and sound.car_radio.music.news_enabled(), "receiver finishes its actual tuning sound before news timing starts")

func _frames(count: int) -> void:
	for index in count:
		await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	paused = false
	if drv:
		drv.release_all()
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
	main.queue_free()
	await _frames(5)
	drv = null
	world = null
	main = null
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	OS.delay_msec(100)
	await process_frame
	print("STORY02: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _wait_first_weather(sound: Node) -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while sound.radio_text() != QuestLines.RADIO and Time.get_ticks_msec() < deadline:
		OS.delay_msec(8)
		await physics_frame
	await _frames(30)
