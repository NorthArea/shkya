extends SceneTree
# Independent PAD-02 oracle. Scenarios and limits frozen before production edits.
const Setup = preload("res://game/input_setup.gd")
const CarScript = preload("res://game/vehicles/lada.gd")
const ORIGIN := Vector3(1000.0, 0.05, 1000.0)
const DEVICE := 0
const DRIVE_TICKS := 120
const SPEED_TOL := 0.08
const PATH_TOL := 0.08
const YAW_TOL := 0.02
var car: CarScript
var csv: FileAccess
var results := {}
var preflight_report := {}
var input_trials := {}
var errors: Array[String] = []
var checks := 0
var label := "initial_settle"
var travelled := 0.0
var previous := ORIGIN
var tick := 0
var sampled_yaw := 0.0
var last_yaw := 0.0

func _initialize() -> void:
	call_deferred("run")

func motion(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = DEVICE
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)

func key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func controls(x: float, y: float, rt: float, lt: float) -> void:
	motion(JOY_AXIS_LEFT_X, x)
	motion(JOY_AXIS_LEFT_Y, y)
	motion(JOY_AXIS_TRIGGER_RIGHT, rt)
	motion(JOY_AXIS_TRIGGER_LEFT, lt)
	Input.flush_buffered_events()

func neutral() -> void:
	controls(0.0, 0.0, 0.0, 0.0)
	for code in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_SPACE]:
		key(code, false)
	Input.flush_buffered_events()

func require_ok(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		print("FAIL: ", message)

func pad_preflight() -> bool:
	# Inspect the installed bindings; never rewrite them to accommodate the fixture.
	var bindings := {}
	for action in ["move_forward", "move_back", "move_left", "move_right", "car_gas", "car_brake"]:
		if not InputMap.has_action(action):
			continue
		var events: Array = []
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion:
				events.append({"device": event.device, "axis": event.axis, "direction": event.axis_value})
		bindings[action] = {"deadzone": InputMap.action_get_deadzone(action), "motions": events}
	preflight_report = {"device": DEVICE, "bindings": bindings, "probes": {}}
	var ready := true
	for probe in [["RT", JOY_AXIS_TRIGGER_RIGHT, "car_gas", "move_forward"],
			["LT", JOY_AXIS_TRIGGER_LEFT, "car_brake", "move_back"],
			["LS-left", JOY_AXIS_LEFT_X, "move_left", "move_left"]]:
		neutral()
		var action: StringName = probe[2] if InputMap.has_action(probe[2]) else probe[3]
		var value := -1.0 if probe[0] == "LS-left" else 1.0
		motion(probe[1], value)
		Input.flush_buffered_events()
		var raw := Input.get_joy_axis(DEVICE, probe[1])
		var strength := Input.get_action_strength(action)
		var valid := is_equal_approx(raw, value) and is_equal_approx(strength, 1.0)
		preflight_report["probes"][probe[0]] = {"action": action, "raw": raw, "strength": strength, "valid": valid}
		require_ok(valid, "fixture preflight: %s on device %s must reach %s through InputMap" % [probe[0], DEVICE, action])
		ready = ready and valid
	neutral()
	preflight_report["valid"] = ready
	print("PAD02_INPUT_PREFLIGHT ", JSON.stringify(preflight_report))
	return ready

func input_boundary(name_: String, held_rt: bool) -> void:
	var gas_action := "car_gas" if InputMap.has_action("car_gas") else "move_forward"
	var brake_action := "car_brake" if InputMap.has_action("car_brake") else "move_back"
	var gas := Input.get_action_strength(gas_action)
	var brake := Input.get_action_strength(brake_action)
	var raw_rt := Input.get_joy_axis(DEVICE, JOY_AXIS_TRIGGER_RIGHT)
	input_trials[name_] = {"gas_action": gas_action, "brake_action": brake_action,
		"gas": gas, "brake": brake, "raw_rt": raw_rt,
		"raw_y": Input.get_joy_axis(DEVICE, JOY_AXIS_LEFT_Y),
		"steer": Input.get_axis("move_right", "move_left")}
	print("PAD02_INPUT_BOUNDARY ", name_, " ", JSON.stringify(input_trials[name_]))
	if held_rt:
		require_ok(is_equal_approx(raw_rt, 1.0), name_ + ": RT remains physically held")
		require_ok(is_equal_approx(gas, 1.0) and is_zero_approx(brake), name_ + ": LEFT_Y may not change held RT gas or apply a brake")

func event_order_trials() -> void:
	for x in [-0.7, 0.7]:
		for y in [-0.35, 0.35]:
			for order in ["rt_then_y", "y_then_rt", "release_y"]:
				var name_ := "order_%s_x%s_y%s" % [order, x, y]
				await reset(name_)
				motion(JOY_AXIS_LEFT_X, x)
				Input.flush_buffered_events()
				if order == "y_then_rt":
					motion(JOY_AXIS_LEFT_Y, y)
					Input.flush_buffered_events()
					input_boundary(name_ + "/Y", false)
					motion(JOY_AXIS_TRIGGER_RIGHT, 1.0)
					Input.flush_buffered_events()
					input_boundary(name_ + "/RT", true)
				else:
					motion(JOY_AXIS_TRIGGER_RIGHT, 1.0)
					Input.flush_buffered_events()
					input_boundary(name_ + "/RT", true)
					motion(JOY_AXIS_LEFT_Y, y)
					Input.flush_buffered_events()
					input_boundary(name_ + "/Y", true)
					if order == "release_y":
						motion(JOY_AXIS_LEFT_Y, 0.0)
						Input.flush_buffered_events()
						input_boundary(name_ + "/releaseY", true)
				# No repeated RT event repairs or masks an action overwritten by Y.
				await frames(DRIVE_TICKS)
				var value := snapshot()
				results[name_] = value
				print(name_, " ", JSON.stringify(value))
				var side := "L" if x < 0.0 else "R"
				close_result(value, results["rt%s_y%s_%s" % [1.0, 0.0, side]], name_ + " equals Y-neutral held RT", false)

func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame
		var p := car.global_position
		travelled += Vector2(p.x - previous.x, p.z - previous.z).length()
		previous = p
		sampled_yaw += angle_difference(last_yaw, car.rotation.y)
		last_yaw = car.rotation.y
		tick += 1
		if tick % 10 == 0:
			var extras := {}
			for action in InputMap.get_actions():
				if String(action).contains("car") or String(action).contains("drive") or String(action).contains("vehicle"):
					extras[action] = Input.get_action_strength(action)
			csv.store_csv_line(PackedStringArray([label, str(tick), str(car.speed_kmh() / 3.6), str(car.velocity.dot(-car.global_basis.z)), str(travelled), str(sampled_yaw), str(car.get("_steer_now")), str(car.braking), str(Input.get_action_strength("move_forward")), str(Input.get_action_strength("move_back")), str(Input.get_axis("move_right", "move_left")), str(Input.get_joy_axis(DEVICE, JOY_AXIS_LEFT_X)), str(Input.get_joy_axis(DEVICE, JOY_AXIS_LEFT_Y)), str(Input.get_joy_axis(DEVICE, JOY_AXIS_TRIGGER_RIGHT)), str(Input.get_joy_axis(DEVICE, JOY_AXIS_TRIGGER_LEFT)), JSON.stringify(extras), str(car.snow_depth), str(car.is_on_floor())]))

func reset(name_: String) -> void:
	label = "settle_" + name_
	neutral()
	car.reset_to(ORIGIN, 0.0)
	travelled = 0.0
	previous = car.global_position
	tick = 0
	sampled_yaw = 0.0
	last_yaw = car.rotation.y
	await frames(12)
	label = name_
	travelled = 0.0
	previous = car.global_position
	tick = 0
	sampled_yaw = 0.0
	last_yaw = car.rotation.y

func snapshot() -> Dictionary:
	return {"speed": car.speed_kmh() / 3.6, "forward": car.velocity.dot(-car.global_basis.z), "path": travelled, "yaw": sampled_yaw, "braking": car.braking, "steer": car.get("_steer_now")}

func drive(name_: String, x: float, y: float, rt: float, lt: float) -> Dictionary:
	await reset(name_)
	controls(x, y, rt, lt)
	await frames(DRIVE_TICKS)
	var value := snapshot()
	results[name_] = value
	print(name_, " ", JSON.stringify(value))
	return value

func close_result(a: Dictionary, b: Dictionary, name_: String, mirrored: bool) -> void:
	require_ok(absf(a.speed - b.speed) <= SPEED_TOL, name_ + " speed differs")
	require_ok(absf(a.path - b.path) <= PATH_TOL, name_ + " path differs")
	var yaw_error: float = absf(a.yaw + b.yaw) if mirrored else absf(a.yaw - b.yaw)
	require_ok(yaw_error <= YAW_TOL, name_ + " yaw differs")

func run() -> void:
	Setup.install()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/checks/PAD-02/symmetry"))
	csv = FileAccess.open("res://builds/checks/PAD-02/symmetry/samples.csv", FileAccess.WRITE)
	csv.store_csv_line(PackedStringArray(["scenario", "tick", "speed_mps", "forward_mps", "path_m", "yaw_rad", "actual_steer", "braking", "move_forward", "move_back", "move_steer", "raw_x", "raw_y", "raw_rt", "raw_lt", "vehicle_actions", "snow_depth", "on_floor"]))
	if not pad_preflight():
		finish_report(false)
		return
	var world := Node3D.new()
	world.name = "Pad02UniformPlane"
	root.add_child(world)
	current_scene = world
	var floor_ := StaticBody3D.new()
	floor_.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_.add_child(shape)
	world.add_child(floor_)
	car = CarScript.new()
	car.position = ORIGIN
	world.add_child(car)
	var driver := Node3D.new()
	world.add_child(driver)
	car.enter(driver)
	await frames(12)
	# All combinations share identical surface, native controller and untouched physics.
	for rt in [0.25, 0.5, 1.0]:
		for y in [0.0, 0.35, -0.35]:
			var prefix := "rt%s_y%s" % [rt, y]
			var left := await drive(prefix + "_L", -0.7, y, rt, 0.0)
			var right := await drive(prefix + "_R", 0.7, y, rt, 0.0)
			close_result(left, right, prefix + " mirror", true)
			require_ok(left.speed > 0.2 and right.speed > 0.2, prefix + " must accelerate with analog RT")
			require_ok(left.yaw > 0.01 and right.yaw < -0.01, prefix + " must steer in opposite directions")
			if y != 0.0:
				close_result(left, results["rt%s_y0.0_L" % rt], prefix + " Y-neutral L", false)
				close_result(right, results["rt%s_y0.0_R" % rt], prefix + " Y-neutral R", false)
	await event_order_trials()
	var straight := {}
	for rt in [0.25, 0.5, 1.0]:
		straight[rt] = await drive("straight_rt%s" % rt, 0.0, 0.0, rt, 0.0)
	require_ok(straight[0.25].speed > 0.2, "RT .25 must accelerate")
	require_ok(straight[0.5].speed > straight[0.25].speed + 0.5 and straight[1.0].speed > straight[0.5].speed + 0.5, "RT must remain analog at .25/.5/1")
	for x in [-0.7, 0.7]:
		for y in [-0.35, 0.0, 0.35]:
			var parked := await drive("parked_x%s_y%s" % [x, y], x, y, 0.0, 0.0)
			require_ok(parked.speed < 0.03 and parked.path < 0.03 and absf(parked.yaw) < 0.01, "LS alone may not propel or rotate stationary vehicle")
	var reverse := await drive("lt_reverse", 0.0, 0.0, 0.0, 1.0)
	require_ok(reverse.forward < -1.0, "independent LT must reverse")
	await reset("keyboard_W")
	key(KEY_W, true)
	await frames(DRIVE_TICKS)
	close_result(snapshot(), straight[1.0], "keyboard W equals RT1", false)
	await reset("keyboard_S")
	key(KEY_S, true)
	await frames(DRIVE_TICKS)
	close_result(snapshot(), reverse, "keyboard S equals LT1", false)
	for code in [KEY_A, KEY_D]:
		await reset("keyboard_%s" % code)
		key(KEY_W, true)
		key(code, true)
		await frames(DRIVE_TICKS)
		var keyboard_result := snapshot()
		var gamepad := await drive("fullsteer_%s" % code, -1.0 if code == KEY_A else 1.0, 0.0, 1.0, 0.0)
		close_result(keyboard_result, gamepad, "keyboard steering equals LS", false)
	for both in [false, true]:
		await reset("brake_both%s" % both)
		controls(0.0, 0.0, 1.0, 0.0)
		await frames(90)
		var initial: float = car.speed_kmh() / 3.6
		controls(0.0, 0.0, 1.0 if both else 0.0, 1.0)
		await frames(30)
		require_ok(car.braking, "LT or both pedals must activate real braking while moving")
		require_ok(car.speed_kmh() / 3.6 < initial * 0.3, "LT or both pedals must decelerate")
		if both:
			await frames(90)
			require_ok(car.speed_kmh() / 3.6 < 0.03, "RT+LT must hold stopped without reverse")
	neutral()
	for rt in [0.25, 0.5, 1.0]:
		controls(0.0, 0.0, rt, 0.0)
		require_ok(Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() < 0.001, "RT must not create walking input")
		controls(0.0, 0.0, 0.0, rt)
		require_ok(Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() < 0.001, "LT must not create walking input")
	neutral()
	finish_report(true)

func finish_report(fixture_valid: bool) -> void:
	csv.flush()
	var report := {"oracle_version": 2, "scope": "InputEventJoypadMotion/Input.parse_input_event -> native Lada physics on uniform plane at (1000,1000); not demo-world acceptance, not hardware diagnosis", "input_sha256": FileAccess.get_sha256("res://game/input_setup.gd"), "lada_sha256": FileAccess.get_sha256("res://game/vehicles/lada.gd"), "fixture_valid": fixture_valid, "preflight": preflight_report, "input_trials": input_trials, "errors": errors, "results": results, "pass": fixture_valid and errors.is_empty()}
	var out := FileAccess.open("res://builds/checks/PAD-02/symmetry/result.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "\t"))
	print("PAD02_SYMMETRY ", ("PASS" if errors.is_empty() else "FAIL") if fixture_valid else "INVALID_FIXTURE", " failures=", errors.size())
	print("PAD02: %d checks, %d failures" % [checks, errors.size()])
	quit((0 if errors.is_empty() else 1) if fixture_valid else 2)
