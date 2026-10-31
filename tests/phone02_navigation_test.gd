extends SceneTree

var main: Node
var phone: Node
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	main.start_game()
	await frames(12)
	for sensor in get_nodes_in_group(&"detection_sensors"): sensor.enabled = false
	phone = main.world.get_node("Phone")
	await button(JOY_BUTTON_DPAD_UP)
	check(phone.is_open() and paused, "up opens actual phone")
	check(root.gui_get_focus_owner() == phone.tab_buttons[&"news"], "news tab starts with controller focus")
	await axis(JOY_AXIS_LEFT_X, 0.9)
	await axis(JOY_AXIS_LEFT_X, 0.0)
	check(root.gui_get_focus_owner() == phone.tab_buttons[&"sms"], "left stick reaches SMS tab through GUI navigation")
	await button(JOY_BUTTON_A)
	check(phone.tab == &"sms", "A opens the SMS section selected with the stick")
	await button(JOY_BUTTON_LEFT_SHOULDER)
	check(phone.tab == &"news", "LB directly selects news")
	await button(JOY_BUTTON_RIGHT_SHOULDER)
	check(phone.tab == &"sms", "RB directly selects SMS")
	var unread: int = phone.unread
	var first: int = phone.sms_index
	await button(JOY_BUTTON_DPAD_RIGHT)
	check(phone.sms_index == first + 1 and phone.unread < unread, "right reads next actual SMS without leaving the section")
	await button(JOY_BUTTON_DPAD_DOWN)
	check(not phone.is_open() and not paused, "down closes without a pause menu")
	main.world.enter_car()
	await frames(3)
	await button(JOY_BUTTON_DPAD_UP)
	phone.select_tab(&"news")
	await axis(JOY_AXIS_LEFT_X,0.9)
	await axis(JOY_AXIS_LEFT_X,0)
	await button(JOY_BUTTON_A)
	check(phone.tab == &"sms" and main.world.car.driver == main.world.player, "stick and A switch sections while seated")
	phone.close_phone()
	for audio in main.find_children("*","AudioStreamPlayer",true,false)+main.find_children("*","AudioStreamPlayer3D",true,false): audio.stop()
	main.queue_free()
	await frames(5)
	main = null
	phone = null
	preload("res://game/world/materials.gd").clear_cache()
	preload("res://game/world/environment_dress.gd").clear_cache()
	preload("res://game/vehicles/vehicle_mesh.gd").cache().clear()
	OS.delay_msec(100)
	await process_frame
	print("PHONE02: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func button(code: JoyButton) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		Input.parse_input_event(event)
		await frames(2)

func axis(code: JoyAxis, amount: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = code
	event.axis_value = amount
	Input.parse_input_event(event)
	await frames(2)

func frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool, description: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + description)
	if not ok: failures.append(description)
