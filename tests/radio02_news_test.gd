extends SceneTree
## RADIO-02: реальные события → очередь → естественный конец трека → одна передача.
## Отдельно: пять секунд музыки, срочный объезд, классика и повтор событий.
const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var sound: Node
var receiver: Node
var music: Node
var _heard_wall_seconds := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(2))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/RADIO-02/profile-%d.json" % OS.get_process_id()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(90)
	world = main.world
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	sound = world.get_node("SoundDirector")
	receiver = sound.car_radio
	music = receiver.music
	check(receiver.queue_size() == 0, "no invented incident is queued in a fresh city")
	world.car.reset_to(Vector3(-80, 0, 32), -PI * 0.5)
	world.enter_car()
	await _frames(2)
	check(music.tuning.playing and not music.player.playing and sound.radio_shown == 0, "manual tuning precedes music and weather")
	check(music.TUNE_DB == -1.0 and music.tuning.volume_db <= 0.0, "tuning is eight dB clearer with no positive playback gain")
	await _tune()
	await _music_time(4.0)
	check(_heard_wall_seconds >= 4.0 and receiver._first_music < 5.0 and music.player.playing and sound.radio_shown == 0 and sound.radio_text() == "", "four seconds of heard music do not yet trigger first weather")
	main.set_paused(true)
	var music_seconds: float = receiver._first_music
	await _frames(90)
	check(receiver._first_music == music_seconds and sound.radio_shown == 0, "pause never contributes to the five seconds")
	# PAUSE-01: пользовательское resume выполняется в обычном кадре, вне physics_frame.
	await process_frame
	main.set_paused(false)
	await _music_time(5.3)
	await _frames(3)
	check(_heard_wall_seconds >= 5.0 and receiver._first_music >= 5.0 and sound.radio_shown == 1 and sound.radio_text() == QuestLines.RADIO and sound.radio.playing, "first weather follows at least five seconds of heard music, independent of broadcast offset")
	await _frames(720)
	check(sound.radio_shown == 1 and sound.radio_text() == "" and music.player.playing, "no second introduction follows the first weather")
	var breakables = world.get_node("LevelGeometry/Breakables")
	var shawarmas: Array = breakables.objects.filter(func(item): return item.kind == &"shawarma")
	check(not shawarmas.is_empty(), "real city contains a breakable shawarma stand")
	if not shawarmas.is_empty():
		shawarmas[0].smash(&"car", Vector3.FORWARD)
	await _frames(3)
	check(receiver.queue_size() == 1 and sound.radio_text() == "" and music.player.playing, "real car demolition queues news without interrupting the song")
	check(not receiver.report_break(&"shawarma", &"car") and receiver.queue_size() == 1, "same event is coalesced while pending")
	check(not receiver.report_break(&"snowman", &"punch") and receiver.queue_size() == 1, "car incident is never invented for a different cause")
	check(not sound.show_radio_line("Проверка обычной новости", 2.0), "ordinary API rejects a mid-song announcement")
	# Оставшееся время настоящего трека проходит через канонические часы эфира.
	await _natural_end()
	check(sound.radio_text() == receiver.BREAK_NEWS[&"shawarma"] and sound.radio.playing and not music.player.playing, "natural completion delivers the confirmed shawarma incident between songs")
	check(not sound.car_radio.player.playing, "single narrator owns the complete incident caption")
	await _frames(1200)
	check(music.player.playing and sound.radio_text() == "" and receiver.queue_size() == 0, "next song waits until the long incident text can be read")
	# Реальная покупка, настоящий producer перекрытия: только он вправе прервать песню.
	world.mission.interact(&"babka")
	world.mission.accept()
	world.mission.notify_entered_car()
	world.mission.notify_arrived_kiosk()
	world.mission.add_money(MissionDirector.BREAD_PRICE)
	check(world.mission.buy_bread(), "bread purchase creates the actual road closure")
	await _frames(180)
	check(sound.radio_text() == "\n".join(PackedStringArray(QuestLines.RADIO_DETOUR)) and sound.radio.playing and music.player.playing, "urgent real closure interrupts the song with one caption and narrator")
	check(music.player.volume_db < music.BASE_DB - 1.0 and music.player.volume_db > -40.0, "urgent announcer ducks the song without muting it")
	check(music.switch_station(), "classical station can be selected during urgent news")
	await _tune()
	await _frames(3)
	check(sound.radio_text() == "" and not sound.radio.playing and music.player.playing, "classical remains free of every narrator")
	_return_live("return to live")
	await _tune()
	await _frames(900)
	# Cooldown advances naturally over simulated gameplay; repeated real kinds remain possible.
	await _frames(5400)
	# An authentic clock may have opened another ordinary slot during the cooldown.
	# Wait for its real reading obligation before testing a fresh mid-song burst.
	var idle_limit := 1200
	while (sound.radio_text() != "" or music.between_tracks()) and idle_limit > 0:
		await _frames(1)
		idle_limit -= 1
	check(idle_limit > 0 and music.player.playing, "cooldown fixture reaches a real music interval before another event burst")
	breakables.car_alarm.emit(Vector3.ZERO)
	breakables.bin_lid.emit(Vector3.ZERO)
	await _frames(2)
	check(receiver.queue_size() >= 2 and sound.radio_text() == "", "real repeated alarm and lid events wait in the ordinary queue")
	check(receiver.report_break(&"shawarma", &"car"), "same incident kind is eligible again after cooldown")
	for index in 20:
		receiver.report_event(StringName("bounded_%d" % index), "Проверка очереди")
	check(receiver.queue_size() == receiver.QUEUE_MAX, "city event burst cannot grow the news queue beyond its fixed bound")
	check(world.exit_car(), "leave the car")
	await _frames(3)
	check(not music.player.playing and not sound.radio.playing, "exit stops every radio sound synchronously")
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

func _tune() -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while music.tuning.playing and Time.get_ticks_msec() < deadline:
		OS.delay_msec(10)
		await process_frame
	await _frames(3)
	check(not music.tuning.playing and music._tuned, "real tuning cue finishes")

func _frames(count: int) -> void:
	for index in count:
		await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)

func _finish() -> void:
	paused = false
	for audio_player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio_player.stop()
	main.queue_free()
	await _frames(5)
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	OS.delay_msec(100)
	await process_frame
	print("RADIO02: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _music_time(seconds: float) -> void:
	# Independent listening exposure: the broadcast cursor may already be minutes
	# into a recording and seeks are not evidence of five seconds actually heard.
	var deadline := Time.get_ticks_msec() + 12000
	var previous := Time.get_ticks_msec()
	while _heard_wall_seconds < seconds and Time.get_ticks_msec() < deadline:
		var sounding: bool = music.player.playing and not music.player.stream_paused and not paused
		OS.delay_msec(8)
		await process_frame
		var now := Time.get_ticks_msec()
		if sounding and music.player.playing and not music.player.stream_paused and not paused:
			_heard_wall_seconds += (now - previous) / 1000.0
		previous = now

func _return_live(label: String) -> void:
	check(music.switch_station() and music.station == music.Station.OFF, "classical cycles to the third OFF position")
	check(not music.player.playing and not music.tuning.playing and not sound.radio.playing and not music.news_enabled(),
		"OFF is immediately silent without tuning or narrator")
	check(sound.engine.playing, "OFF preserves the actual engine world sound")
	check(music.switch_station() and music.station == music.Station.LIVE, label)
