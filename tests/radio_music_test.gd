extends SceneTree
## RADIO-01: настоящий Main, водитель, единичный bed и диктор поверх неизменных субтитров.

const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var sound: Node
var music: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func():
		push_error("FAIL: RADIO01 exceeded 240 simulated seconds")
		quit(2))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/RADIO-01/profile-%d.json" % OS.get_process_id()
	root.add_child(main)
	await _frames(3)
	check(main.music.player.playing, "original Chopin remains in the menu")
	var station_events: Array[InputEvent] = InputMap.action_get_events(&"radio_station")
	check(station_events.any(func(event): return event is InputEventKey and event.physical_keycode == KEY_R) and station_events.any(func(event): return event is InputEventJoypadButton and event.button_index == JOY_BUTTON_DPAD_RIGHT), "station action maps R and right on the D-pad")
	main.start_game()
	await _frames(90)
	world = main.world
	sound = world.get_node("SoundDirector")
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	music = sound.car_radio.get("music")
	check(music != null, "CarRadio owns a separate RadioMusic bed")
	if music == null:
		await _finish()
		return
	check(not music.player.playing, "bed is silent on foot")
	check(music.player.stream is AudioStreamOggVorbis and music.player.stream.loop, "Cold Funk is a looping Ogg")
	check(music.player.stream.packet_sequence == load(music.LIVE_PATH).packet_sequence, "the sole bed is the selected Cold Funk recording")
	check(music.player.bus == &"Master", "radio does not share Chopin's pause filter")
	world.car.enter(world.player)
	await _frames(2)
	check(world.control_mode == &"on_foot" and not music.player.playing, "a driver reference alone does not start music while control remains on foot")
	world.car.exit()
	world.car.reset_to(Vector3(-80, 0, 32), -PI * 0.5)
	world.enter_car()
	await _frames(2)
	check(music.tuning.playing and not music.player.playing, "manual tuning sounds before the car music starts")
	var tune_limit := 180
	while not music.player.playing and tune_limit > 0:
		await _frames(1)
		tune_limit -= 1
	check(world.car.driver == world.player and world.car.speed_kmh() < 1.0 and music.player.playing, "real driver starts the bed while parked")
	check(not main.music.player.playing, "game bed never overlaps menu Chopin")
	check(sound.radio_shown == 0, "original door-to-announcement delay is retained")
	await _frames(45)
	check(sound.radio_text() == QuestLines.RADIO and sound.radio_shown == 1, "first story caption retains its text and order")
	check(sound.radio.playing and sound.radio.stream is AudioStreamWAV, "first story caption has our mumbling announcer")
	check(sound.radio.stream.data == sound.RADIO.data, "story announcer uses the project's radio_mumble recording")
	await _frames(40)
	check(music.player.playing and music.player.volume_db < music.BASE_DB - 1.0 and music.player.volume_db > -40.0, "announcer smoothly ducks the bed but leaves it audible")
	check(_voices() == 1, "one announcer plays over the first story caption")
	var remaining: float = sound._subtitle_left
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_R
	key.pressed = true
	Input.parse_input_event(key)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)
	await _frames(2)
	check(music.station == music.Station.CLASSICAL and music.tuning.playing, "real R input retunes from Radio N to classical")
	await _frames(120)
	check(music.station == music.Station.CLASSICAL and music.player.playing, "classical station plays its own continuous playlist")
	check(music._classical.size() == 2 and not music.player.stream.loop, "classical playlist has both prepared recordings with natural endings")
	var classical_before: AudioStream = music.player.stream
	# Реальный сигнал конца композиции, без ожидания нескольких минут исполнения.
	music.player.stop()
	music.player.finished.emit()
	await _frames(2)
	check(music.player.playing and music.player.stream != classical_before and not music.player.stream.loop, "finished classical track advances to the next recording")
	check(sound.radio_text() == "" and _voices() == 0 and sound.radio_shown == 1, "classical station has no news or announcer")
	check(absf(sound._subtitle_left - remaining) < 0.05, "classical station freezes remaining story reading time")
	check(music.station_label.text.contains("Классика") and music.station_label.text.contains("R"), "station HUD shows name, frequency and keyboard binding")
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_DPAD_RIGHT
	button.pressed = true
	Input.parse_input_event(button)
	button = button.duplicate() as InputEventJoypadButton
	button.pressed = false
	Input.parse_input_event(button)
	await _frames(2)
	check(music.station == music.Station.LIVE and music.tuning.playing, "real right D-pad input retunes to Radio N")
	await _frames(120)
	check(music.station == music.Station.LIVE and sound.radio_text() == QuestLines.RADIO and sound.radio_shown == 1 and sound.radio.playing, "returning live resumes the preserved first story caption")
	world.quest_flow._open_chain(QuestLines.VENDOR_CHAIN, [{"id": &"close", "text": "ЗАКРЫТЬ"}], &"vendor")
	await _frames(40)
	check(sound.radio_text() == "" and _voices() == 0, "dialog hides radio and silences the announcer")
	check(music.player.volume_db <= music.PRIORITY_DB + 0.5, "dialog receives priority over the music")
	world.quest_flow._close()
	await _frames(3)
	check(sound.radio_text() == QuestLines.RADIO and sound.radio_shown == 1 and sound.radio.playing, "interrupted story resumes with the same caption and announcer")
	var limit := 1500
	while sound.radio_text() != QuestLines.RADIO_PROGRESS and limit > 0:
		await _frames(1)
		limit -= 1
	check(limit > 0 and sound.radio_shown == 2 and sound.radio.playing, "second original story caption is also voiced")
	while sound.story_radio_pending() and limit > 0:
		await _frames(1)
		limit -= 1
	await _frames(60)
	check(limit > 0 and sound.radio_text() == "" and _voices() == 0, "two story captions finish without a third or leftover voice")
	check(music.player.playing and absf(music.player.volume_db - music.BASE_DB) < 0.5, "music smoothly restores after the announcement")
	# Покупка запускает настоящий таймер объезда; на классике новости не расходуются.
	check(music.switch_station(), "select classical before the detour announcement")
	world.mission.interact(&"babka")
	world.mission.accept()
	world.mission.notify_entered_car()
	world.mission.notify_arrived_kiosk()
	world.mission.add_money(MissionDirector.BREAD_PRICE)
	check(world.mission.buy_bread(), "real bread purchase enables the existing road closure")
	var closure: Node = world.get_node("LevelGeometry/Patrols/RoadClosure")
	var detour_remaining: float = closure._radio_left
	await _frames(200)
	check(closure.radio_shown == 0 and closure._radio_left == detour_remaining and sound.radio_text() == "" and _voices() == 0, "classic freezes detour news without a caption or voice")
	check(music.switch_station(), "return live for the pending detour announcement")
	var detour_limit := 1200
	while closure.radio_shown == 0 and detour_limit > 0:
		await _frames(1)
		detour_limit -= 1
	await _frames(3)
	check(detour_limit > 0 and sound.radio_text() == "\n".join(PackedStringArray(QuestLines.RADIO_DETOUR)) and sound.radio.playing and _voices() == 1, "existing detour text reaches the live radio with one mumbling announcer")
	while sound.radio_text() != "" and detour_limit > 0:
		await _frames(1)
		detour_limit -= 1
	await _frames(60)
	# Existing periodic trigger still requires motion; its explicit invocation exercises the production caption/voice path.
	sound.car_radio.wait = 0.0
	await _frames(120)
	check(sound.car_radio.plays == 0, "parked bed does not bypass periodic announcement speed gate")
	world.car.velocity = Vector3(0, 0, -6)
	sound.car_radio._physics_process(1.0 / 60.0)
	world.car.velocity = Vector3.ZERO
	await _frames(3)
	check(sound.car_radio.plays == 1 and sound.radio_text() == sound.car_radio.LINES[0], "periodic announcement retains its original text")
	check(sound.car_radio.player.playing and sound.car_radio.player.stream.data == sound.RADIO.data and _voices() == 1, "periodic caption uses one mumble voice without the old voiced jingle")
	await _frames(40)
	check(music.player.playing and music.player.volume_db < music.BASE_DB - 1.0 and music.player.volume_db > -40.0, "periodic announcer leaves a quiet audible bed")
	main.set_paused(true)
	await _frames(50)
	check(not music.switch_station(), "pause ignores station switching")
	check(main.music.player.playing and main.music.muffled(), "pause keeps the existing muffled Chopin")
	check(not music.player.playing or music.player.stream_paused, "car music cannot sound together with pause Chopin")
	main.set_paused(false)
	await _frames(2)
	check(not main.music.player.playing or not music.player.playing or music.player.stream_paused, "car bed waits for Chopin's resume fade to finish")
	await _frames(60)
	check(music.player.playing and not music.player.stream_paused and not main.music.player.playing, "bed resumes after pause Chopin stops")
	check(world.exit_car(), "real driver exits from the parked car")
	check(not music.player.playing and _voices() == 0, "exit synchronously stops music and announcers")
	var saved: float = music.resume_position
	await _frames(15)
	check(not music.player.playing, "bed stays stopped on foot")
	check(not music.switch_station() and not music.tuning.playing, "station switching is ignored on foot")
	world.enter_car()
	await _frames(120)
	check(music.player.playing and music.player.get_playback_position() >= saved - 0.1, "next entry resumes the saved track cursor")
	for index in 3:
		world.exit_car()
		world.enter_car()
		await _frames(2)
	check(music.tuning.playing and not music.player.playing, "rapid exit/re-entry cannot let an old tuning callback start music early")
	check(sound.car_radio.find_children("RadioMusic", "Node", true, false).size() == 1 and music.find_children("RadioBed", "AudioStreamPlayer", true, false).size() == 1, "repeated entries keep exactly one bed player")
	world.stealth.alert_now()
	await _frames(2)
	check(world.is_stealth_failing() and not music.player.playing and _voices() == 0 and sound.radio_text() == "", "stealth failure quiet gate clears radio sound and caption")
	await _frames(100)
	check(not music.player.playing and not music.tuning.playing, "cancelled tuning cannot restart music during the failure card")
	await _finish()

func _voices() -> int:
	return int(sound.radio.playing) + int(sound.car_radio.player.playing)

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
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
	main.queue_free()
	await _frames(5)
	main = null
	world = null
	sound = null
	music = null
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	await process_frame
	print("RADIO01: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
