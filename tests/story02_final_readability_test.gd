extends SceneTree
## Runtime sequencing and cancellation of the final dialogue; Dummy rendering cannot prove visual quality.
const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
var main: Node
var world: DemoWorld
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	await _fresh()
	var flow = world.quest_flow
	var hud = world.get_node("GameHUD")
	_handover()
	flow._on_completion_closed()
	check(not flow.finale.playing, "early completion close cannot skip the thanks reading interval")
	var first_seconds := 0.0
	var second_seconds := 0.0
	var overlap := false
	for frame in 420:
		await _frames(1)
		if flow.thanks_bubble.is_visible_in_tree():
			first_seconds += 1.0 / 60.0
		if flow.thanks_after_bubble.is_visible_in_tree():
			second_seconds += 1.0 / 60.0
		overlap = overlap or (hud.completion_panel.visible and (flow.thanks_back.visible or flow.thanks_after_back.visible))
	check(first_seconds + 0.02 >= QuestLines.read_seconds(QuestLines.THANKS), "first thanks receives its full reading interval")
	check(second_seconds + 0.02 >= QuestLines.read_seconds(QuestLines.THANKS_AFTER), "second thanks receives its full reading interval")
	check(hud.completion_panel.visible and not overlap, "protocol never overlaps either thanks bubble")
	check(world.mission.xp == 50, "handover awards 50 XP once")
	world.mission.interact(&"babka")
	check(world.mission.xp == 50 and flow.protocol_ready(), "duplicate handover neither awards XP nor restarts the presentation")
	hud.completion_close.pressed.emit()
	var shown: int = flow.finale.shown
	flow._on_completion_closed()
	check(flow.finale.shown == shown, "duplicate completion close cannot replay the scene")
	var last_seconds := 0.0
	overlap = false
	for frame in 300:
		await _frames(1)
		if flow.finale.is_bubble_visible():
			last_seconds += 1.0 / 60.0
		overlap = overlap or (hud.is_end_card_open() and flow.finale.is_bubble_visible())
	check(last_seconds + 0.02 >= QuestLines.read_seconds(QuestLines.FINALE_LOOK), "last phrase receives its full reading interval")
	check(hud.is_end_card_open() and not overlap, "end card never overlaps the last phrase")
	check(not flow.finale._done.is_valid(), "completed finale releases its callback")
	# Cancelling the playing scene must invalidate its completion callback.
	await _fresh()
	flow = world.quest_flow
	hud = world.get_node("GameHUD")
	_handover()
	await _frames(420)
	hud.completion_close.pressed.emit()
	await _frames(80)
	var before_pause: float = flow.finale._t
	paused = true
	await _frames(90)
	check(flow.finale._t == before_pause and not hud.is_end_card_open(), "pause preserves the last phrase reading interval")
	paused = false
	flow._close()
	await _frames(300)
	check(not hud.is_end_card_open() and not flow.finale.playing and not flow.finale.is_bubble_visible(), "cancel during the last phrase cannot open a delayed end card")
	check(not world.ui_blocking and world.player.input_enabled and world.camera_rig.target == world.player, "cancel restores camera and input")
	check(not flow.finale._done.is_valid(), "cancel releases the deferred completion callback")
	# Cancel the thanks phase, then run beyond its original deadline.
	await _fresh()
	flow = world.quest_flow
	hud = world.get_node("GameHUD")
	_handover()
	await _frames(30)
	flow._close()
	await _frames(420)
	check(not flow.protocol_ready() and not hud.completion_panel.visible and not flow.thanks_back.visible and not flow.thanks_after_back.visible, "cancel during thanks cannot open a delayed protocol")
	# Actual main lifecycle at both deferred presentation stages.
	for stage in [&"thanks", &"finale"]:
		for operation in [&"restart", &"menu"]:
			await _fresh()
			_handover()
			if stage == &"finale":
				await _frames(420)
				world.get_node("GameHUD").completion_close.pressed.emit()
				await _frames(80)
			else:
				await _frames(30)
			var old_world: WeakRef = weakref(world)
			if operation == &"restart":
				main.start_game()
			else:
				main.return_to_menu()
			await _frames(450)
			check(old_world.get_ref() == null, "%s during %s releases old world" % [operation, stage])
			if operation == &"restart":
				check(main.world.mission.xp == 0 and main.world.mission.state == MissionDirector.NOT_STARTED and not main.world.get_node("GameHUD").is_end_card_open(), "restart during %s has no inherited reward or card" % stage)
			else:
				check(main.world == null and main.menu.visible, "menu during %s stays in menu past old deadline" % stage)
	flow = null
	hud = null
	main.queue_free()
	world = null
	await _frames(5)
	main = null
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	OS.delay_msec(100)
	await process_frame
	print("STORY02_FINAL_READABILITY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _fresh() -> void:
	main.start_game()
	await _frames(12)
	world = main.world
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	var intro = world.get_node_or_null("Intro")
	if intro:
		intro.skip()

func _handover() -> void:
	var mission := world.mission
	mission.interact(&"babka")
	mission.accept()
	mission.notify_entered_car()
	mission.notify_arrived_kiosk()
	mission.add_money(mission.money_missing())
	mission.buy_bread()
	world.quest_flow._on_choice(&"turn_in")

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
