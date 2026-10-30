extends SceneTree
## DOG-01: погладить Шарика настоящими E и X; будка остаётся целой.

const PadInput = preload("res://game/ui/pad_input.gd")
const Driver = preload("res://tests/playthrough_driver.gd")

var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var ambient: Node
var zone: Interactable

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	ambient = world.get_node("LevelGeometry/Ambient")
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	zone = ambient.dog.get_node_or_null("PetInteraction")
	if not check(zone != null, "dog has an Interactable for petting"):
		await _finish()
		return
	check(zone.collision_layer == 8, "petting uses the shared Interact layer")
	var mission_before := [world.mission.state, world.mission.money, world.mission.has_bread, world.mission.xp]
	await _approach()
	check(world.player.current_interactable() == zone, "player can approach and select the dog")
	check(world.get_hud_state()["prompt"] == "E — ПОГЛАДИТЬ", "HUD explains petting")
	var at: Vector3 = ambient.dog.global_position
	await _key(KEY_E)
	check(ambient.get("dog_pets") == 1 and ambient.dog_state == &"pet", "E pets the dog")
	var tail: Node3D = ambient.get("_dog_tail")
	var head: Node3D = ambient.get("_dog_head")
	var tail_before := tail.rotation.y
	await _frames(20)
	check(ambient.dog.global_position.distance_to(at) < 0.03, "dog stays still while being petted")
	check(absf(tail.rotation.y - tail_before) > 0.1, "dog visibly wags its tail")
	check(head.rotation.x < -0.1, "dog raises its head to the hand")
	await _key(KEY_E)
	check(ambient.get("dog_pets") == 1, "repeated input during petting does not restart the reaction")
	await _frames(180)
	check(zone.enabled, "petting becomes available again")
	await _pad_x()
	check(ambient.get("dog_pets") == 2, "X on the gamepad also pets the dog")
	check(PadInput.hint("E — ПОГЛАДИТЬ") == "X — ПОГЛАДИТЬ", "gamepad hint names X")
	await _frames(180)
	await _car_interrupt()
	await _blocked_states()
	check([world.mission.state, world.mission.money, world.mission.has_bread, world.mission.xp] == mission_before,
		"petting changes neither mission nor money")
	await _house()
	await _finish()

func _approach() -> void:
	world.player.place(ambient.dog.global_position + Vector3(-6, 0, 0), 0.0)
	var start := world.player.global_position
	var driver := Driver.new(self, main)
	for frame in 360:
		if world.player.current_interactable() == zone:
			break
		var to_dog: Vector3 = ambient.dog.global_position - world.player.global_position
		to_dog.y = 0.0
		driver._walk_axes(to_dog.normalized())
		await physics_frame
	driver.release_all()
	await _frames(15)
	check(world.player.current_interactable() == zone and world.player.global_position.distance_to(start) > 3.0,
		"dog can be reached from 6 m by walking with actual movement input")
	driver.tree = null
	driver.main = null

func _car_interrupt() -> void:
	await _key(KEY_E)
	check(ambient.dog_state == &"pet", "dog is being petted before the car approaches")
	var at: Vector3 = ambient.dog.global_position
	world.car.reset_to(at + Vector3(0, 0, 3.5), 0.0)
	world.car.velocity = Vector3(0, 0, -4)
	await _frames(6)
	check(ambient.dog_state == &"flee" and ambient.dog.global_position.distance_to(at) > 0.05,
		"dog immediately interrupts petting and gets away from an approaching car")
	world.reset_car()
	await _frames(5)

func _blocked_states() -> void:
	var count: int = ambient.get("dog_pets")
	zone.interact(main)
	check(ambient.get("dog_pets") == count, "only Ilyusha can pet the dog")
	world.player.force_hide_mode(&"box")
	await _frames(2)
	zone.interact(world.player)
	check(not zone.enabled and ambient.get("dog_pets") == count, "petting is unavailable inside a hiding place")
	world.player.force_hide_mode(&"none")
	world.ui_blocking = true
	await _frames(2)
	zone.interact(world.player)
	check(not zone.enabled and ambient.get("dog_pets") == count, "dialog or blocking UI prevents petting")
	world.ui_blocking = false
	await _frames(2)
	main.set_paused(true)
	zone.interact(world.player)
	check(ambient.get("dog_pets") == count, "pause prevents even a stale interaction")
	main.set_paused(false)
	world.control_mode = &"in_car"
	await _frames(2)
	zone.interact(world.player)
	check(not zone.enabled and ambient.get("dog_pets") == count, "petting is unavailable from the car")
	world.control_mode = &"on_foot"
	world.player.place(ambient.dog.global_position + Vector3(-8, 0, 0), 0.0)
	zone.interact(world.player)
	check(ambient.get("dog_pets") == count, "a stale interaction cannot pet from far away")
	var at: Vector3 = ambient.dog.global_position
	await _frames(180)
	check(ambient.dog.global_position.distance_to(at) > 0.5, "dog resumes its own walk after the player leaves")

func _house() -> void:
	var house: Node3D = world.get_node_or_null("LevelGeometry/Props/DogHouse")
	if not check(house != null, "dog house exists"):
		return
	var p: Vector3 = house.global_position
	var breaks: Node = world.get_node("LevelGeometry/Breakables")
	var target_found := false
	for object in breaks.objects:
		if String(object.name) == "DogHouse" or String(object.get("kind")) == "doghouse":
			target_found = true
	check(not target_found, "dog house is excluded from destructible objects")
	world.player.place(p + Vector3(-1, 0, 0), -PI * 0.5)
	world.car.reset_to(p + Vector3(0, 0, 0.5), 0.0)
	world.car.velocity = Vector3(0, 0, -8)
	world.player.punch()
	await _frames(40)
	check(is_instance_valid(house) and house.is_visible_in_tree() and house.global_position.is_equal_approx(p),
		"punching and driving at the house leave it intact")

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	e = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(2)

func _pad_x() -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_X
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	e = InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_X
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(2)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
	return ok

func _finish() -> void:
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	main = null
	world = null
	ambient = null
	zone = null
	print("DOG01: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
