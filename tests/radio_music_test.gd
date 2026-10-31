extends SceneTree
## RADIO-01: настоящий Main, водитель, единичный bed и диктор поверх неизменных субтитров.

const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const EXPECTED_LIVE_PATHS: Array[String] = [
	"res://assets/audio/radio/cold_funk.ogg",
	"res://assets/audio/radio/local_forecast_elevator.ogg",
	"res://assets/audio/radio/monkeys_spinning_monkeys.ogg",
	"res://assets/audio/radio/sneaky_snitch.ogg",
]

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
	var live_paths: Array = music.get_script().get_script_constant_map().get("LIVE_PATHS", [])
	check(live_paths == EXPECTED_LIVE_PATHS, "live playlist contains the four licensed recordings in the selected order")
	if live_paths != EXPECTED_LIVE_PATHS:
		await _finish()
		return
	check(not music.player.playing, "bed is silent on foot")
	check(music.player.stream is AudioStreamOggVorbis and not music.player.stream.loop, "Cold Funk has a natural end for between-track news")
	check(music.player.stream.packet_sequence == load(music.LIVE_PATH).packet_sequence, "the first live track remains the selected Cold Funk recording")
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
	check(sound.radio_shown == 0, "tuning finishes before the five seconds of music")
	await _frames(330)
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
	while sound.story_radio_pending() and limit > 0:
		await _frames(1)
		limit -= 1
	await _frames(360)
	check(limit > 0 and sound.radio_shown == 1 and sound.radio_text() == "" and _voices() == 0, "one first weather finishes with no cancelled second introduction")
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
	# Обычная передача допускается только после реального finished, без таймера езды.
	var before_plays: int = sound.car_radio.plays
	await _frames(120)
	check(sound.car_radio.plays == before_plays and music.player.playing, "parked track is not interrupted by a periodic timer")
	music.player.stop()
	music.player.finished.emit()
	await _frames(3)
	check(sound.car_radio.plays == before_plays + 1 and sound.radio_text() != "", "track finished admits one routine announcement")
	check(sound.radio.playing and not sound.car_radio.player.playing and _voices() == 1, "routine caption uses the single mumble voice")
	await _frames(40)
	check(not music.player.playing and music.between_tracks(), "next song waits for the entire between-track announcement")
	await _frames(900)
	check(music.player.playing and sound.radio_text() == "", "next song starts after the announced text finishes")
	check(_live_recording_is(1), "first completed gap advances from Cold Funk to Local Forecast")
	await _playlist_cycles()
	var before_pause: AudioStream = music.player.stream
	var before_pause_position: float = music.player.get_playback_position()
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
	check(music.player.stream == before_pause and music.player.get_playback_position() >= before_pause_position - 0.1, "pause preserves the current live recording and cursor")
	var before_station: AudioStream = music.player.stream
	var before_station_position: float = music.player.get_playback_position()
	check(music.switch_station(), "switch away from a non-first live recording")
	await _frames(120)
	check(music.switch_station(), "return to the non-first live recording")
	await _frames(120)
	check(music.player.stream == before_station and music.player.get_playback_position() >= before_station_position - 0.1, "classical round trip preserves live track identity and cursor")
	var before_exit: AudioStream = music.player.stream
	check(world.exit_car(), "real driver exits from the parked car")
	check(not music.player.playing and _voices() == 0, "exit synchronously stops music and announcers")
	var saved: float = music.resume_position
	await _frames(15)
	check(not music.player.playing, "bed stays stopped on foot")
	check(not music.switch_station() and not music.tuning.playing, "station switching is ignored on foot")
	world.enter_car()
	await _frames(120)
	check(music.player.playing and music.player.get_playback_position() >= saved - 0.1, "next entry resumes the saved track cursor")
	check(music.player.stream == before_exit and _live_recording_is(1), "re-entry resumes the non-first live recording instead of Cold Funk")
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

func _live_recording_is(index: int) -> bool:
	return music.player.stream is AudioStreamOggVorbis and music.player.stream.packet_sequence == load(EXPECTED_LIVE_PATHS[index]).packet_sequence

func _playlist_cycles() -> void:
	# Настоящий AudioServer finished: сокращаем только текущий тестовый stream.
	# Следующий трек должен быть настоящей записью; ожидаемый порядок задан независимо.
	for step in 8:
		var expected := (step + 2) % EXPECTED_LIVE_PATHS.size()
		var short_track := AudioStreamWAV.new()
		short_track.format = AudioStreamWAV.FORMAT_16_BITS
		short_track.mix_rate = 48000
		var pcm := PackedByteArray()
		pcm.resize(9600)
		short_track.data = pcm
		music.player.stream = short_track
		music.player.play()
		await _until_wall(func(): return music.between_tracks(), 2000)
		check(music.between_tracks() and not music.player.playing, "cycle %d waits in the real finished gap" % step)
		await _until_wall(func(): return sound.radio_text() != "", 1000)
		check(sound.radio_text() != "" and not music.player.playing, "cycle %d admits news before the next recording" % step)
		sound.hide_radio_line()
		await _until_wall(func(): return music.player.playing, 1000)
		check(_live_recording_is(expected) and not music.between_tracks(), "cycle %d starts expected live recording %d after the gap" % [step, expected])

func _until_wall(condition: Callable, milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while not condition.call() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(5)
		await process_frame
	await _frames(2)

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
