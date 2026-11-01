extends SceneTree
## Independent integration witnesses for DECISIONS: actual music time and interrupted ordinary news.
const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const ORDINARY := "Проверенное событие двора. Новость должна закончиться после срочного сообщения"
const URGENT := "Срочно: перекрытие улицы"
var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var sound: Node
var receiver: Node
var music: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(70.0, true, false, true).timeout.connect(func(): quit(2))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/RADIO-02/interleaving-%d.json" % OS.get_process_id()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(90)
	world = main.world
	for sensor in get_nodes_in_group(&"detection_sensors"): sensor.enabled = false
	sound = world.get_node("SoundDirector")
	receiver = sound.car_radio
	music = receiver.music
	world.enter_car()
	await _until(func(): return music._tuned and music.player.playing, 4.0)
	check(sound.radio_shown == 0, "tuning itself does not consume the first music interval")
	var before: float = receiver._first_music
	music.player.stream_paused = true
	music.set_physics_process(false)
	await _frames(30)
	check(receiver._first_music == before and sound.radio_shown == 0, "playing-but-paused audio contributes no first-weather progress")
	music.set_physics_process(true)
	music.player.stream_paused = false
	await _until(func(): return sound.radio_shown > 0, 8.0)
	check(sound.radio_shown == 1 and music.player.get_playback_position() >= 4.8, "first weather follows five seconds of actual audio playback")
	# Intro is unrelated to the interruption witness; finish this fixture caption explicitly.
	sound.hide_radio_line()
	check(receiver.report_event(&"independent_interleave", ORDINARY), "a distinct confirmed event enters the actual receiver queue")
	await _natural_end()
	await _until(func(): return sound.radio_text() == ORDINARY, 2.0)
	check(sound.radio_text() == ORDINARY and not music.player.playing, "ordinary event owns the natural gap before interruption")
	await _frames(6)
	var remaining: float = sound._subtitle_left
	check(sound.urgent_radio_line(URGENT, 0.5), "urgent producer can interrupt the running ordinary caption")
	check(sound.radio_text() == URGENT, "urgent caption owns the narrator immediately")
	# Station changes preserve the interrupted reading obligation and urgent remainder.
	check(music.switch_station(), "switch to classical during urgent news")
	await _until(func(): return music._tuned and music.player.playing, 4.0)
	var urgent_left: float = sound._subtitle_left
	await _frames(30)
	check(sound.radio_text() == "" and not sound.radio.playing and is_equal_approx(sound._subtitle_left, urgent_left), "classical freezes the urgent remainder and has no narrator")
	_return_live("return to live while urgent remainder is pending")
	await _until(func(): return music._tuned, 4.0)
	await _until(func(): return sound.radio_text() == ORDINARY, 8.0)
	check(sound.radio_text() == ORDINARY, "urgent completion resumes the interrupted ordinary event instead of losing it")
	check(sound._subtitle_left <= remaining + 0.1 and sound._subtitle_left > 0, "ordinary resumes its unread remainder")
	check(not music.player.playing and sound.radio.playing, "resumed ordinary retains the same track gap and narrator")
	main.set_paused(true)
	var paused_left: float = sound._subtitle_left
	await _frames(20)
	check(is_equal_approx(sound._subtitle_left, paused_left), "pause freezes a resumed ordinary caption")
	main.set_paused(false)
	check(world.exit_car(), "exit while the resumed event is still active")
	await _frames(3)
	var exited_left: float = sound._subtitle_left
	await _frames(20)
	check(not sound.radio.playing and not music.player.playing and is_equal_approx(sound._subtitle_left, exited_left), "exit stops both players and keeps the reading remainder")
	world.enter_car()
	await _until(func(): return music._tuned, 4.0)
	await _until(func(): return sound.radio_text() == ORDINARY, 2.0)
	check(sound.radio_text() == ORDINARY and not music.player.playing, "return to the car resumes the event before starting a new song")
	await _until(func(): return music.player.playing and sound.radio_text() == "", 15.0)
	check(music.player.playing and receiver.queue_size() == 0, "the next song starts only after the complete interrupted event")
	await _finish()

func _natural_end() -> void:
	# A station boundary is owned by world time, never AudioServer.finished.
	var state: Dictionary = music.broadcast_state(music.Station.LIVE)
	var remaining: float = music._live[state.index].get_length() - state.position
	music.set_physics_process(false)
	music._physics_process(maxf(0.0, remaining - 0.02))
	check(not music.between_tracks() and music.broadcast_state(music.Station.LIVE).index == state.index,
		"ordinary news remains blocked just before the real broadcast boundary")
	music._physics_process(0.04)
	music.set_physics_process(true)
	await _frames(3)
	check(music.between_tracks() and music.broadcast_state(music.Station.LIVE).index == (state.index + 1) % music._live.size(),
		"world-time completion opens one silent news slot at the next broadcast recording")

func _until(condition: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < end:
		OS.delay_msec(5)
		await process_frame
	await _frames(2)

func _frames(count: int) -> void:
	for index in count: await physics_frame

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error("RADIO02_INTERLEAVE: " + label)

func _finish() -> void:
	paused = false
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): player.stop()
	main.queue_free()
	await _frames(5)
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	OS.delay_msec(100)
	await process_frame
	main = null
	world = null
	sound = null
	receiver = null
	music = null
	print("RADIO02_INTERLEAVE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _return_live(label: String) -> void:
	check(music.switch_station() and music.station == music.Station.OFF, "classical cycles to the third OFF position")
	check(not music.player.playing and not music.tuning.playing and not sound.radio.playing and not music.news_enabled(),
		"OFF is immediately silent without tuning or narrator")
	check(sound.engine.playing, "OFF preserves the actual engine world sound")
	check(music.switch_station() and music.station == music.Station.LIVE, label)
