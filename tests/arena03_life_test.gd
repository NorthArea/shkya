extends SceneTree

const Layout = preload("res://game/world/layout.gd")
var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var residents: Node
var life
var one: Resident
var two: Resident
var sounds: Array = []
var entrances: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	residents = world.get_node("LevelGeometry/Residents")
	life = residents.life
	for resident: Resident in residents.residents:
		resident.set_physics_process(false)
		resident.set_process(false)
		resident._act_stop()
		resident._tick_bubble(1000.0)
	life.reserved.clear()
	one = residents.residents[17]
	two = residents.residents[29]
	one.activity_sound.connect(_sound)
	two.activity_sound.connect(_sound)
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	_alone()
	_domino_pair()
	_chat_pair()
	await _entrances()
	await _finish()

func _at(resident: Resident, spot: StringName) -> void:
	if resident.spot_id != &"":
		life.release(resident.spot_id, resident)
	resident._act_stop()
	resident.hidden = false
	resident.show()
	resident.state = &"walk"
	resident.knock_phase = &""
	resident.spot_id = spot
	life.reserve(spot, resident)
	resident._arrive()
	resident.clock = 0.0
	resident._wait = 300.0
	resident._bubble_ready_at = 0.0
	resident._idle_at = 0.0
	resident.bubble_log.clear()
	resident.sound_counts.clear()
	resident._tick_bubble(1000.0)
	resident._process(0.0)

func _step(seconds: float, actors: Array) -> void:
	var dt := 1.0 / 60.0
	for i in int(seconds / dt):
		residents._break_clock += dt
		for actor: Resident in actors:
			actor.clock += dt
			actor._tick_bubble(dt)
		for actor: Resident in actors:
			actor._tick_activity(dt)
			actor._process(dt)

func _alone() -> void:
	_at(one, &"domino_w")
	_step(7.0, [one])
	check(one.sound_counts.get(&"domino", 0) == 0, "an unaccompanied domino player waits without playing against nobody")
	one._idle_at = 0.0
	one._react()
	check(one.bubble_log.is_empty(), "an unaccompanied domino player does not announce a game")
	_at(one, &"chat_b1")
	_step(1.0, [one])
	one._idle_at = 0.0
	one._react()
	check(one.bubble_log.is_empty(), "an unaccompanied neighbour does not converse with an empty place")

func _domino_pair() -> void:
	_at(one, &"domino_w")
	_at(two, &"domino_e")
	sounds.clear()
	_step(12.0, [one, two])
	check(one.sound_counts.get(&"domino", 0) > 1 and two.sound_counts.get(&"domino", 0) > 1,
		"both real players put down dominoes")
	var alternating := sounds.size() >= 4
	for i in range(1, sounds.size()):
		alternating = alternating and sounds[i][0] != sounds[i - 1][0]
	check(alternating, "domino sounds alternate between the two players")
	var count: int = one.sound_counts.get(&"domino", 0)
	two._act_stop()
	life.release(two.spot_id, two)
	two.state = &"walk"
	_step(7.0, [one])
	check(one.sound_counts.get(&"domino", 0) == count, "the remaining player stops playing when the partner leaves")
	_at(two, &"domino_e")
	two.hidden = true
	two.hide()
	_step(4.0, [one])
	check(one.sound_counts.get(&"domino", 0) == count, "an invisible partner cannot keep the game alive")
	two.hidden = false
	two.show()
	two.state = &"knocked"
	_step(4.0, [one])
	check(one.sound_counts.get(&"domino", 0) == count, "a knocked-down partner cannot keep the game alive")
	_at(two, &"domino_e")
	two.position.y = 4.0
	_step(4.0, [one])
	check(one.sound_counts.get(&"domino", 0) == count, "a partner on another floor cannot play through the ceiling")
	_at(two, &"domino_e")
	var table = world.get_node("LevelGeometry/Breakables").get_by_id(&"Z5_4")
	for i in 3: table.punch(Vector3.RIGHT)
	_step(1.0 / 60.0, [one, two])
	check(not life.anchor_intact(&"domino_w") and not one.is_playing(&"domino") and not two.is_playing(&"domino"),
		"breaking the shared table ends the game for both players")

func _chat_pair() -> void:
	_at(one, &"chat_b1")
	_at(two, &"chat_b2")
	residents._chatter_at = -100.0
	var gestured := false
	for i in 40:
		_step(0.2, [one, two])
		gestured = gestured or absf(one.visual.position.y) > 0.015 or absf(two.visual.position.y) > 0.015
	check(gestured, "neighbours visibly nod or gesture while addressing their partner")
	_step(28.0, [one, two])
	check(not one.bubble_log.is_empty() and not two.bubble_log.is_empty(), "both neighbours take turns speaking")
	var chatter: Array = one.bubble_log.duplicate() + two.bubble_log.duplicate()
	chatter.sort_custom(func(a, b): return a[0] < b[0])
	var separate := true
	for i in range(1, chatter.size()):
		separate = separate and chatter[i][0] - chatter[i - 1][0] >= 3.0
	check(separate, "social bubbles retain the street chatter limit")
	for actor: Resident in [one, two]:
		var spaced := true
		for i in range(1, actor.bubble_log.size()):
			spaced = spaced and actor.bubble_log[i][0] - actor.bubble_log[i - 1][0] >= actor.BUBBLE_COOLDOWN
		check(spaced, "each speaker retains their existing bubble cooldown")
	if life.has_method("social_members"):
		check(life.social_members(one).size() == 2, "the two occupied paired chat spots share a conversation")
		two.position = life.spots[&"chat_bw2"].pos
		check(life.social_members(one).size() == 1, "distant neighbours at another conversation are not partners")
	else:
		check(false, "Life resolves social membership from present participants")
	var before := one.bubble_log.size()
	two._act_stop()
	_step(20.0, [one])
	check(one.bubble_log.size() == before, "conversation ends when the listener leaves")

func _sound(resident: Resident, kind: StringName) -> void:
	if kind == &"domino": sounds.append([resident.index, resident.clock])

func _entrances() -> void:
	one.entrance_used.connect(func(resident, at, entering): entrances.append([resident, at, entering]))
	var home: StringName = one.home
	one.plan = [home, &"bench"]
	one.plan_i = 0
	_at(one, home)
	check(entrances.size() == 1 and entrances[0][0] == one and entrances[0][1] == life.spots[home].pos and entrances[0][2],
		"entering a home emits one event at its actual entrance")
	one._arrive()
	check(entrances.size() == 1, "an already hidden resident cannot enter the same door twice")
	one._wait = 0.1
	var wait: float = one._wait
	one.set_physics_process(true)
	paused = true
	await _frames(30)
	check(one._wait == wait and entrances.size() == 1, "a paused world cannot advance a doorway visit")
	paused = false
	await _frames(12)
	one.set_physics_process(false)
	check(entrances.size() == 2 and not entrances[1][2] and entrances[1][1] == life.spots[home].pos,
		"leaving emits one event at the same entrance")
	one._tick_hidden(2.0)
	check(entrances.size() == 2, "a resident already outside cannot repeat the exit event")
	entrances.clear()
	one._enter_inside(&"gastro")
	check(entrances.size() == 1 and entrances[0][1] == life.spots[&"gastro"].pos and entrances[0][2],
		"the trolley-to-shop route uses the same entrance event")

func _frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): player.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	print("ARENA03_LIFE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
