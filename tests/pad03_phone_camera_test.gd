extends SceneTree

var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	main.start_game()
	await _frames(12)
	world = main.world
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	var phone: Node = world.get_node("Phone")
	await _pad(JOY_BUTTON_DPAD_UP)
	check(phone.is_open() and paused, "D-pad up opens the phone on foot")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(not phone.is_open() and not paused, "D-pad down closes the phone")
	if phone.is_open(): phone.close_phone()
	world.enter_car()
	await _frames(3)
	check(world.car.driver == world.player, "real driver enters the car")
	var yaw_before: float = world.camera_rig.yaw
	var pitch_before: float = world.camera_rig.pitch
	Input.action_press(&"look_right", 0.8)
	Input.action_press(&"look_up", 0.7)
	await _frames(24)
	Input.action_release(&"look_right")
	Input.action_release(&"look_up")
	check(absf(angle_difference(yaw_before, world.camera_rig.yaw)) > 0.25, "right stick rotates car camera horizontally")
	check(world.camera_rig.pitch > pitch_before + 0.1, "right stick rotates car camera vertically")
	var manual: float = world.camera_rig.yaw
	await _frames(20)
	check(absf(angle_difference(manual, world.camera_rig.yaw)) < 0.05, "camera holds manual look after stick release")
	await _frames(180)
	check(absf(angle_difference(world.camera_rig.yaw, world.car.rotation.y)) < 0.1, "camera returns behind car after idle delay")
	await _pad(JOY_BUTTON_DPAD_UP)
	check(phone.is_open() and paused and world.car.driver == world.player, "phone opens while seated without exiting the car")
	var at: Vector3 = world.car.position
	Input.action_press(&"car_gas")
	await _frames(20)
	check(world.car.position.distance_to(at) < 0.001, "phone pauses driving")
	Input.action_release(&"car_gas")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(not phone.is_open() and not paused and not world.ui_blocking, "phone restores driving control")
	if phone.is_open(): phone.close_phone()
	world.mission.state = MissionDirector.COMPLETE
	await _pad(JOY_BUTTON_DPAD_UP)
	check(phone.is_open(), "phone remains available in post-mission free play")
	if phone.is_open(): phone.close_phone()
	await _finish()

func _pad(button: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		await _frames(2)

func _frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	paused = false
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): player.stop()
	main.queue_free()
	await _frames(5)
	print("PAD03: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
