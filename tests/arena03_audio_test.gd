extends SceneTree
## ARENA-03: реальные события жителей → звук по адресу; видимый порыв → ветер.
const Layout = preload("res://game/world/layout.gd")
var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var sound: Node
var residents: Node
var weather: Node
var actors: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	sound = world.get_node("SoundDirector")
	residents = world.get_node("LevelGeometry/Residents")
	weather = world.get_node("LightingAndWeather")
	actors = [residents.residents[0], residents.residents[1], residents.residents[3], residents.residents[4], residents.residents[5]]
	for r: Resident in residents.residents:
		r.set_physics_process(false)
		r._act_stop()
	residents.life.reserved.clear()
	weather.set_process(false)
	sound.set_physics_process(false)
	_no_phantom_doors()
	_wind()
	_doors()
	_work_audio()
	await _pause()
	await _finish()

func _listen(at: Vector3) -> void:
	world.player.place(at, 0.0)
	world.camera_rig.snap()

func _no_phantom_doors() -> void:
	var before: int = sound.played["door_slam"]
	for i in 180:
		sound._ambient_sounds(1.0)
	check(sound.played["door_slam"] == before, "three empty minutes never produce a door slam without a resident")

func _settle_wind(gust: float) -> float:
	weather.gust = gust
	for i in 120:
		sound._ambient_sounds(1.0 / 60.0)
	return sound.wind.volume_db

func _wind() -> void:
	_listen(Vector3(59.5, 0, -15))
	var calm := _settle_wind(0.0)
	var gust := _settle_wind(1.0)
	check(gust >= calm + 3.0, "the visible gust audibly raises wind volume (%.1f → %.1f dB)" % [calm, gust])
	check(gust <= -14.0 + 0.01, "even a full gust stays within the existing wind mix ceiling")
	_listen(Layout.SPAWN)
	var yard := _settle_wind(1.0)
	check(yard <= gust - 3.0, "the enclosed yard shelters the listener from the same gust (%.1f vs %.1f dB)" % [yard, gust])
	check(sound.wind.playing, "wind remains a continuous bed during the transition")
	check(not sound.FOOTSTEP_SOUND, "the owner's disabled footsteps remain disabled")

func _at(r: Resident, id: StringName) -> void:
	r._act_stop()
	if r.spot_id != &"":
		residents.life.release(r.spot_id, r)
	r.hidden = false
	r.show()
	r.state = &"walk"
	r.spot_id = id
	residents.life.reserve(id, r)
	r._arrive()

func _door_players() -> Array:
	return sound.find_children("EntranceDoor*", "AudioStreamPlayer3D", false, false)

func _stop_doors() -> void:
	for p: AudioStreamPlayer3D in _door_players():
		p.stop()

func _heard_at(at: Vector3) -> bool:
	for p: AudioStreamPlayer3D in _door_players():
		if p.playing and Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < 0.5:
			return true
	return false

func _doors() -> void:
	var r: Resident = actors[0]
	if not check(r.has_signal(&"entrance_used"), "real residents expose the entrance event"):
		return
	_stop_doors()
	_listen(Layout.SPAWN)
	var at: Vector3 = residents.life.spots[&"door_h1e"].pos
	var before: int = sound.played["door_slam"]
	_at(r, &"door_h1e")
	check(sound.played["door_slam"] == before + 1, "entering a real home produces one door sound")
	check(_heard_at(at), "the sound comes from that home's actual entrance")
	_at(actors[1], &"door_h1e")
	check(sound.played["door_slam"] == before + 1, "residents entering the same doorway together do not stack slams")
	sound._ambient_sounds(3.0)
	_stop_doors()
	r._wait = 0.0
	r._tick_hidden(1.0 / 60.0)
	check(sound.played["door_slam"] == before + 2, "leaving the home later also produces one door sound")
	check(_heard_at(at), "leaving sounds at the same entrance")
	_stop_doors()
	sound._ambient_sounds(3.0)
	before = sound.played["door_slam"]
	_at(r, &"press")
	check(sound.played["door_slam"] == before, "standing at a kiosk window never invents a door event")
	_at(r, &"door_h9a")
	check(sound.played["door_slam"] == before, "a doorway beyond hearing distance does not start a sound")
	_listen(Layout.SPAWN)
	_stop_doors()
	sound._ambient_sounds(3.0)
	before = sound.played["door_slam"]
	var ids: Array[StringName] = [&"door_h1e", &"door_h1w", &"door_h3w", &"door_h3e"]
	for i in ids.size():
		_at(actors[i], ids[i])
	check(sound.played["door_slam"] == before + 4, "four distinct nearby doorways can sound at once")
	var sources_stay := true
	for id in ids:
		sources_stay = sources_stay and _heard_at(residents.life.spots[id].pos)
	check(sources_stay, "simultaneous doors retain their individual world positions")
	_listen(residents.life.spots[&"door_h4"].pos)
	_at(actors[4], &"door_h4")
	check(_door_players().size() <= 4, "a fifth simultaneous event cannot grow the bounded sound pool")
	check(sound.played["door_slam"] == before + 4, "a full pool does not relocate a sound already playing")
	var quiet := true
	for p: AudioStreamPlayer3D in _door_players():
		quiet = quiet and p.volume_db <= -14.0 and p.stream == sound.DOOR_SLAM
	check(quiet, "door sounds preserve the existing quiet mix and original asset")
	check(sound.door_slam_times.size() == sound.played["door_slam"], "door diagnostics count only sounds actually started")

func _work_audio() -> void:
	var actor: Resident = actors[0]
	_listen(Layout.SPAWN)
	actor.global_position = world.player.global_position + Vector3.RIGHT * 2.0
	for kind: StringName in [&"dig", &"carpet", &"hood"]:
		var key := "life_%s" % kind
		var before: int = sound.played.get(key, 0)
		actor.activity_sound.emit(actor, kind)
		check(sound.played.get(key, 0) == before + 1, "%s tool contact reaches the real sound director" % kind)
		var player: AudioStreamPlayer3D = sound.life_players.get(kind)
		if player:
			check(player.playing and player.global_position.distance_to(actor.global_position + Vector3.UP * 0.6) < 0.01,
				"%s sounds at the working resident" % kind)
			check(player.volume_db <= -8.0, "%s stays below quest sounds in the mix" % kind)
			player.stop()

func _pause() -> void:
	sound.set_physics_process(true)
	main.set_paused(true)
	var before: float = sound._ambient_clock
	var volume: float = sound.wind.volume_db
	await _frames(30)
	check(is_equal_approx(sound._ambient_clock, before) and is_equal_approx(sound.wind.volume_db, volume),
		"pausing the world also freezes wind updates and door cooldown time")
	main.set_paused(false)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("PASS: " if ok else "FAIL: ", label)
	if not ok:
		failures.append(label)
	return ok

func _finish() -> void:
	for p in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		p.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	actors.clear()
	main = null
	world = null
	sound = null
	residents = null
	weather = null
	print("ARENA03_AUDIO: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
