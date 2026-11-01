extends SceneTree
## RADIO-03: real receiver joins two independent broadcasts driven by world time.

const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")

var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var music: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(2))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/RADIO-03/profile-%d.json" % OS.get_process_id()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(90)
	world = main.world
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	music = world.get_node("SoundDirector").car_radio.music
	# Only RadioMusic's world-time step is controlled; all car/phone/receiver code is real.
	music.set_physics_process(false)
	check(music.has_method("broadcast_state"), "receiver exposes its authoritative broadcast cursor")
	if not music.has_method("broadcast_state"):
		await _finish()
		return
	var live_lengths: Array[float] = []
	var classical_lengths: Array[float] = []
	for track: AudioStream in music._live:
		live_lengths.append(track.get_length())
	for track: AudioStream in music._classical:
		classical_lengths.append(track.get_length())
	check(music.CLASSICAL_PATHS == ["res://assets/audio/radio/beethoven_moonlight_1.ogg", "res://assets/audio/radio/ride_of_the_valkyries.ogg"] and classical_lengths.size() == 2, "classical contains Moonlight I and Ride of the Valkyries")
	if not await _first_weather_near_end():
		await _finish()
		return
	var live_before: Dictionary = music.broadcast_state(0)
	var classical_before: Dictionary = music.broadcast_state(1)
	music._physics_process(60.0)
	_check_advance(0, live_before, live_lengths, 60.0, "unheard Radio N advances on foot")
	_check_advance(1, classical_before, classical_lengths, 60.0, "unheard classical advances on foot")
	check(not music.player.playing and not music.tuning.playing, "unheard broadcasts create no audio playback")
	world.car.reset_to(Vector3(-80, 0, 32), -PI * 0.5)
	world.enter_car()
	_join_tuned_station()
	_check_join(0, "entering the car joins the current live song and offset")
	check(music.switch_station(), "driver can tune classical")
	_join_tuned_station()
	_check_join(1, "classical starts at its existing broadcast offset")
	classical_before = music.broadcast_state(1)
	var until_classical_boundary: float = classical_lengths[classical_before.index] - classical_before.position + 0.25
	music._physics_process(until_classical_boundary)
	_check_advance(1, classical_before, classical_lengths, until_classical_boundary, "classical moves to the next recording on its broadcast boundary")
	_check_join(1, "classical boundary immediately plays the current next recording")
	live_before = music.broadcast_state(0)
	classical_before = music.broadcast_state(1)
	var classical_cycle := _sum(classical_lengths)
	music._physics_process(classical_cycle)
	_check_advance(0, live_before, live_lengths, classical_cycle, "Radio N runs through its playlist while both classical tracks pass")
	_check_advance(1, classical_before, classical_lengths, classical_cycle, "classical wraps exactly after both full recordings")
	check(music.switch_station() and music.station == 2, "third receiver position turns the radio off")
	check(not music.player.playing and not music.tuning.playing and not music.news_enabled(), "off stops music and narrator without a tuning sound")
	live_before = music.broadcast_state(0)
	classical_before = music.broadcast_state(1)
	music._physics_process(37.0)
	_check_advance(0, live_before, live_lengths, 37.0, "Radio N continues while the receiver is off")
	_check_advance(1, classical_before, classical_lengths, 37.0, "classical continues while the receiver is off")
	check(world.exit_car(), "driver exits with the receiver off")
	world.enter_car()
	check(music.station == 2 and not music.player.playing and not music.tuning.playing, "re-entering preserves off without tuning or music")
	check(music.switch_station(), "driver returns from off to Radio N")
	_join_tuned_station()
	_check_join(0, "returning live joins the current broadcast instead of saved Cold Funk")
	live_before = music.broadcast_state(0)
	classical_before = music.broadcast_state(1)
	paused = true
	music._physics_process(1000.0)
	check(music.broadcast_state(0) == live_before and music.broadcast_state(1) == classical_before, "world pause freezes both broadcast cursors")
	paused = false
	var phone: Node = world.get_node("Phone")
	check(phone.open_phone(), "real phone opens while driving")
	music._physics_process(1000.0)
	check(music.broadcast_state(0) == live_before and music.broadcast_state(1) == classical_before, "phone pause freezes both broadcast cursors")
	phone.close_phone()
	var drift_position: float = music.broadcast_state(0).position
	music.player.seek(drift_position + 4.0)
	music._physics_process(0.0)
	_check_join(0, "output drift is corrected to the authoritative broadcast position")
	# Stop only the output, as AudioServer may do before its finished notification arrives.
	var current: Dictionary = music.broadcast_state(0)
	music.player.stop()
	music.player.finished.emit()
	check(music.broadcast_state(0) == current and not music.between_tracks(), "finished before the world-time boundary cannot move the station")
	var until_boundary: float = live_lengths[current.index] - current.position + 0.25
	music._physics_process(until_boundary)
	check(music.between_tracks() and not music.player.playing, "live broadcast boundary opens one silent ordinary-news slot")
	var after_boundary: Dictionary = music.broadcast_state(0)
	music.player.finished.emit()
	music.player.finished.emit()
	check(music.broadcast_state(0) == after_boundary, "late or duplicate finished callbacks cannot advance the broadcast twice")
	music.claim_gap()
	music._physics_process(8.0)
	_check_advance(0, after_boundary, live_lengths, 8.0, "broadcast continues underneath the full news reading slot")
	var after_news: Dictionary = music.broadcast_state(0)
	music.finish_gap()
	music.finish_gap()
	check(music.broadcast_state(0) == after_news and not music.between_tracks(), "finishing the reading slot changes no broadcast index or offset")
	_check_join(0, "news completion rejoins the current broadcast offset")
	# A clock boundary can stop an old playback before its callback is delivered.
	music.player.finished.emit()
	check(music.player.playing and music.broadcast_state(0) == after_news, "old finished after rejoining cannot stop or advance the current song")
	check(world.exit_car(), "driver exits the actual car")
	live_before = music.broadcast_state(0)
	classical_before = music.broadcast_state(1)
	var many_cycles := _sum(live_lengths) * 23.0 + 7.25
	music._physics_process(many_cycles)
	_check_advance(0, live_before, live_lengths, many_cycles, "long absence wraps the whole live playlist without drift")
	_check_advance(1, classical_before, classical_lengths, many_cycles, "long absence wraps classical independently")
	world.enter_car()
	_join_tuned_station()
	_check_join(0, "return after a long walk joins the current live broadcast")
	check(music.find_children("RadioBed", "AudioStreamPlayer", true, false).size() == 1, "both station clocks share a single audible music player")
	await _finish()

func _first_weather_near_end() -> bool:
	var sound: Node = world.get_node("SoundDirector")
	var receiver: Node = sound.car_radio
	check(sound.radio_shown == 0 and receiver._first_music == 0.0, "near-end first join starts without any heard music or weather")
	var before: Dictionary = music.broadcast_state(0)
	var until_join: float = music._live[before.index].get_length() - before.position - 2.0
	music._physics_process(until_join)
	world.car.reset_to(Vector3(-80, 0, 32), -PI * 0.5)
	world.enter_car()
	_join_tuned_station()
	_check_join(0, "first receiver join lands two seconds before the live recording ends")
	await _heard_frames(114)
	check(receiver._first_music > 1.0 and receiver._first_music < 5.0 and sound.radio_shown == 0 and sound.radio_text() == "", "less than five heard seconds near the recording end cannot start weather")
	var ending: Dictionary = music.broadcast_state(0)
	var remaining: float = music._live[ending.index].get_length() - ending.position
	music._physics_process(remaining + 0.02)
	check(music.between_tracks() and not music.player.playing, "first unheard-weather boundary reaches the real silent track gap")
	# Do not add artificial heard time: only exercise the receiver's gap decision.
	receiver._physics_process(0.0)
	var continued: bool = music.player.playing and not music.between_tracks()
	check(continued and sound.radio_shown == 0, "pending first weather releases the gap and continues music instead of waiting forever")
	if not continued:
		return false
	for index in 600:
		if sound.radio_shown > 0:
			break
		await _heard_frames(1)
	check(receiver._first_music >= 5.0 and sound.radio_shown == 1 and sound.radio_text() == QuestLines.RADIO and sound.radio.playing, "first weather follows at least five actually heard seconds across the song boundary")
	sound.hide_radio_line()
	await _heard_frames(120)
	check(sound.radio_shown == 1 and sound.radio_text() == "" and music.player.playing, "continued music produces no duplicate first-weather introduction")
	check(world.exit_car(), "first-weather regression returns the driver to the real on-foot state")
	return true

func _heard_frames(count: int) -> void:
	for index in count:
		music._physics_process(1.0 / 60.0)
		await physics_frame

func _check_advance(which: int, before: Dictionary, lengths: Array[float], seconds: float, label: String) -> void:
	var elapsed: float = before.position + seconds
	var index: int = before.index
	while elapsed >= lengths[index]:
		elapsed -= lengths[index]
		index = (index + 1) % lengths.size()
	var current: Dictionary = music.broadcast_state(which)
	check(current.index == index and absf(current.position - elapsed) < 0.002, label)

func _check_join(which: int, label: String) -> void:
	var current: Dictionary = music.broadcast_state(which)
	var tracks: Array = music._live if which == 0 else music._classical
	check(music.player.playing and music.player.stream == tracks[current.index] and absf(music.player.get_playback_position() - current.position) < 0.2, label)

func _join_tuned_station() -> void:
	music.tuning.stop()
	music._tune_finished()

func _sum(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total

func _frames(count: int) -> void:
	for index in count:
		await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("RADIO03: " + label)

func _finish() -> void:
	paused = false
	for audio_player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio_player.stop()
	main.queue_free()
	await _frames(5)
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	print("RADIO03: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
