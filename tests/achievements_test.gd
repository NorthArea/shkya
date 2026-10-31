extends SceneTree
## ACHIEVE-01: isolated storage, real gameplay signals, settings and queued notifications.
## All save files stay under builds/checks; the owner's user:// data is never opened.

const StoreScript = preload("res://game/progression/achievements_store.gd")
const OUT := "res://builds/checks/ACHIEVE-01"
var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var store: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_test_storage()
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = OUT.path_join("world.json")
	_clean(main.achievement_path)
	root.add_child(main)
	await process_frame
	store = main.get_node_or_null("Achievements")
	if not check(store != null, "Main owns persistent Achievements store"):
		await _finish()
		return
	main.start_game()
	await _frames(8)
	world = main.world
	if not check(world != null, "real world starts"):
		await _finish()
		return
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	await _test_real_events()
	await _test_menu_and_toast()
	await _test_restart()
	await _finish()

func _test_storage() -> void:
	var path := OUT.path_join("store.json")
	_clean(path)
	var first: Node = StoreScript.new()
	check(first.setup(path) == OK, "missing file is a clean collection")
	check(first.entries().size() == 8, "eight distinct achievements")
	var unlocked_signals: Array = []
	first.achievement_unlocked.connect(func(id): unlocked_signals.append(id))
	check(not first.unlock(&"unknown_achievement"), "unknown id is rejected")
	check(first.unlock(&"double_granny"), "known id commits")
	check(not first.unlock(&"double_granny"), "duplicate event does not unlock twice")
	check(unlocked_signals == [&"double_granny"], "exactly one notification after commit")
	var second: Node = StoreScript.new()
	check(second.setup(path) == OK and second.unlocked(&"double_granny"), "unlock survives new store instance")
	check(not second.unlock(&"double_granny"), "reloaded achievement never notifies again")
	check(second.unlock(&"bread_zero"), "a second achievement preserves first")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{unfinished")
	file.close()
	var recovered: Node = StoreScript.new()
	check(recovered.setup(path) == OK, "corrupt primary recovers valid backup")
	check(recovered.unlocked(&"double_granny") and recovered.unlocked(&"bread_zero"), "recovery keeps latest committed set")
	first.free()
	second.free()
	recovered.free()
	_clean(path)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"version":1,"unlocked":{"not_a_real_id":1,"double_granny":"invalid"}}')
	file.close()
	var malformed: Node = StoreScript.new()
	check(malformed.setup(path) != OK, "invalid entries are not accepted as unlocked")
	check(not malformed.unlocked(&"double_granny"), "malformed timestamp cannot create an unlock")
	malformed.free()
	_clean(path)
	for bad_version: Variant in ["1", true, [], {}, null, 2]:
		file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"version": bad_version, "unlocked": {"double_granny": 1}}))
		file.close()
		var invalid_version: Node = StoreScript.new()
		check(invalid_version.setup(path) == ERR_PARSE_ERROR and not invalid_version.unlocked(&"double_granny"), "wrong version type/value is rejected without a runtime error")
		invalid_version.free()
		_clean(path)

func _test_real_events() -> void:
	var residents: Node = world.get_node("LevelGeometry/Residents")
	var grannies: Array = residents.residents.filter(func(r): return r.voice == &"babka")
	world.car.velocity = Vector3(9, 0, 0)
	grannies[0].knock()
	grannies[0].knock()
	check(not store.unlocked(&"double_granny"), "re-hitting the same granny does not make a pair")
	grannies[1].knock()
	check(store.unlocked(&"double_granny"), "two distinct granny KNOCK signals unlock the pair")
	var breakables: Node = world.get_node("LevelGeometry/Breakables")
	var bench: Node
	var tree: Node
	for item in breakables.objects:
		if item.kind in [&"bench", &"bench_big"] and bench == null:
			bench = item
		if item.kind in [&"birch", &"poplar", &"rowan"] and tree == null:
			tree = item
	if check(tree != null and bench != null, "real tree and bench exist"):
		tree.smash(&"car", Vector3.RIGHT)
		check(store.unlocked(&"timber_delivery"), "tree broken by car reaches store")
		bench.smash(&"punch", Vector3.RIGHT)
		check(store.unlocked(&"standing_room"), "bench broken by punch reaches store")
	var mission := world.mission
	mission.interact(&"babka")
	mission.decline()
	mission.interact(&"babka")
	mission.accept()
	mission.notify_entered_car()
	mission.notify_arrived_kiosk()
	mission.money = MissionDirector.BREAD_PRICE
	check(mission.buy_bread(), "bread purchase uses real director")
	check(store.unlocked(&"bread_zero"), "purchase with no change unlocks")
	check(world.player.set_hide_mode(&"box"), "real player enters box")
	check(store.unlocked(&"bread_box"), "bread in box reaches store")
	world.player.set_hide_mode(&"none")
	world.player.set_hide_mode(&"snowdrift")
	check(store.unlocked(&"cold_storage"), "bread in snow reaches store")
	world.player.set_hide_mode(&"none")
	var ambient: Node = world.get_node("LevelGeometry/Ambient")
	world.car.position = Vector3(-60, 0, 80)
	world.player.place(ambient.dog.global_position + Vector3(0.7, 0, 0), 0)
	await _frames(3)
	var pets_before: int = ambient.dog_pets
	ambient._pet_dog(world.player)
	check(ambient.dog_pets == pets_before + 1, "dog accepts real pet action")
	check(store.unlocked(&"good_boy_certificate"), "successful dog pet after destruction reaches store")
	mission.interact(&"babka")
	check(store.unlocked(&"professional_ditcher"), "decline then complete in one world reaches store")

func _test_menu_and_toast() -> void:
	var toast: Node = main.get_node_or_null("AchievementToast")
	if check(toast != null, "Main owns notification queue"):
		main.set_paused(true)
		await _frames(2)
		check(not toast.card.visible, "notification does not cover pause buttons")
		main.pause_menu._open_settings()
		main.pause_menu.settings._open_achievements()
		await process_frame
		var panel: Node = main.pause_menu.settings.achievements
		check(panel.visible, "achievements screen opens from pause settings")
		check(panel.cards.size() == 8, "screen renders all eight entries")
		check(panel.back_button.has_focus(), "screen has gamepad focus")
		var cancel := InputEventAction.new()
		cancel.action = &"ui_cancel"
		cancel.pressed = true
		panel._unhandled_input(cancel)
		await process_frame
		check(not panel.visible and main.pause_menu.settings.achievements_button.has_focus(), "back returns focus to settings")
		main.set_paused(false)
		world.ui_blocking = true
		await _frames(2)
		check(not toast.card.visible, "notification waits behind a dialog")
		world.ui_blocking = false

func _test_restart() -> void:
	main.start_game()
	await _frames(8)
	check(store.entries().all(func(e): return e["unlocked"]), "new game preserves all earned achievements")
	var previous_count: int = store.entries().filter(func(e): return e["unlocked"]).size()
	main.world.mission.interact(&"babka")
	main.world.mission.decline()
	check(store.entries().filter(func(e): return e["unlocked"]).size() == previous_count, "new world does not replay notifications")

func _clean(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _finish() -> void:
	if is_instance_valid(main):
		for type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
			for player in main.find_children("*", type, true, false):
				player.stop()
		main.queue_free()
	await _frames(3)
	OS.delay_msec(100)
	await process_frame
	print("ACHIEVE-01: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
