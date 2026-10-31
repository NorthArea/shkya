extends SceneTree
## Independent witness: AudioServer end can precede delivery of player.finished.
const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const FIRST := "res://assets/audio/radio/cold_funk.ogg"
const NEXT := "res://assets/audio/radio/local_forecast_elevator.ogg"
const ORDINARY := "Проверенное событие: снег у магазина уберут после следующего снегопада"

var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var sound: Node
var receiver: Node
var music: Node
var finished_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func():
		push_error("RADIO_PLAYLIST_INTERLEAVE: exceeded 60 seconds")
		quit(2))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/RADIO-01/playlist/interleave-profile-%d.json" % OS.get_process_id()
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
	world.car.reset_to(Vector3(-80, 0, 32), -PI * 0.5)
	world.enter_car()
	await _until(func(): return music._tuned and music.player.playing, 4.0)
	check(_recording_is(FIRST), "the actual driver starts the preserved Cold Funk recording")
	await _until(func(): return sound.radio_shown == 1, 8.0)
	check(sound.radio_shown == 1 and sound.radio_text() == QuestLines.RADIO, "the actual first-weather path precedes the ordinary-event witness")
	# The intro is unrelated to the delayed-finished boundary.
	sound.hide_radio_line()
	check(receiver.report_event(&"independent_playlist_end", ORDINARY), "a confirmed ordinary event enters the actual receiver queue")
	var plays_before: int = receiver.plays
	music.player.finished.connect(func(): finished_count += 1)

	music.set_physics_process(false)
	var short_track := AudioStreamWAV.new()
	short_track.format = AudioStreamWAV.FORMAT_16_BITS
	short_track.mix_rate = 48000
	var pcm := PackedByteArray()
	pcm.resize(9600)
	short_track.data = pcm
	music.player.stream = short_track
	music.player.play()
	# Fault injection delays only main-thread finished delivery; AudioServer still mixes.
	music.player.set_process_internal(false)
	check(music._live_index == 0 and not music.between_tracks(), "starting the finite witness does not advance the live playlist")
	await _until(func(): return not music.player.playing, 2.0)
	var boundary_valid: bool = not music.player.playing and music.player.has_stream_playback() and finished_count == 0
	check(boundary_valid, "AudioServer has ended while the player still owns the undelivered finished playback")
	if not boundary_valid:
		await _finish()
		return

	music._physics_process(1.0 / 60.0)
	var retained: bool = music.player.stream == short_track and music.player.has_stream_playback() and not music.player.playing and finished_count == 0
	check(retained, "physics polling preserves the ended playback until its real finished notification")
	check(music._live_index == 0 and not music.between_tracks() and receiver.queue_size() == 1 and sound.radio_text() == "", "undelivered finished neither advances a track nor consumes ordinary news")
	if not retained:
		await _finish()
		return

	music.player.set_process_internal(true)
	music.set_physics_process(true)
	await _until(func(): return finished_count == 1 and music.between_tracks(), 2.0)
	check(finished_count == 1 and music.between_tracks() and not music.player.playing, "restoring delivery emits one real finished and opens one silent gap")
	await _until(func(): return sound.radio_text() == ORDINARY, 2.0)
	check(sound.radio_text() == ORDINARY and music._live_index == 0 and not music.player.playing, "the queued ordinary event owns the gap before any index advance")
	await _frames(12)
	check(sound.radio_text() == ORDINARY and music.between_tracks() and music._live_index == 0 and not music.player.playing, "the next recording stays blocked while ordinary news remains unread")
	await _until(func(): return music.player.playing and sound.radio_text() == "", 15.0)
	check(_recording_is(NEXT) and music._live_index == 1 and not music.between_tracks(), "natural news completion advances exactly once to Local Forecast")
	check(finished_count == 1 and receiver.plays == plays_before + 1 and receiver.queue_size() == 0, "one natural track ending produces exactly one ordinary announcement")
	var resumed: AudioStream = music.player.stream
	music.finish_gap()
	music.finish_gap()
	check(music._live_index == 1 and music.player.stream == resumed and music.player.playing and receiver.plays == plays_before + 1, "duplicate gap completion leaves the next recording and announcement count unchanged")
	await _finish()

func _recording_is(path: String) -> bool:
	return music.player.stream is AudioStreamOggVorbis and music.player.stream.packet_sequence == load(path).packet_sequence

func _until(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(5)
		await process_frame
	await _frames(2)

func _frames(count: int) -> void:
	for index in count:
		await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("RADIO_PLAYLIST_INTERLEAVE: " + label)

func _finish() -> void:
	paused = false
	for audio_player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio_player.stop()
	main.queue_free()
	await _frames(5)
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	main = null
	world = null
	sound = null
	receiver = null
	music = null
	print("RADIO_PLAYLIST_INTERLEAVE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
