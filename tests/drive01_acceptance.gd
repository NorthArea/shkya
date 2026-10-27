extends SceneTree
## DRIVE-01: настоящий main.tscn, «Лада» и Илюша, ввод через Input. Критерии — карточка DRIVE-01.

const Layout = preload("res://game/world/layout.gd")

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: drive01 exceeded 900 simulated seconds")
		quit(2)
	)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.start_game()
	await _frames(10)
	world = main.world
	await _check_enter_exit()
	await _check_quest_hook()
	await _check_route()
	await _check_walls()
	await _check_handbrake()
	await _check_reset()
	await _check_repeat()
	_finish()

# --- критерий 1: вход и выход по E ---

func _check_enter_exit() -> void:
	var car := world.car
	check(car.global_position.distance_to(Layout.CAR_SPAWN) < 0.2, "Lada parked at CAR_SPAWN")
	check(car.is_on_floor() or car.global_position.y < 0.05, "Lada stands on the ground")
	world.player.place(car.global_position + Vector3(-2.2, 0, 0), 0.0)
	await _frames(4)
	check(world.get_hud_state()["prompt"] == "E — СЕСТЬ В МАШИНУ", "prompt next to the car: '%s'" % world.get_hud_state()["prompt"])
	check(world.get_hud_state()["speed_kmh"] < 0.0, "no speed on foot")
	await _press(&"interact")
	check(world.control_mode == &"in_car", "E enters the car")
	check(not world.player.visible and not world.player.input_enabled, "Ilyusha hidden, his input off")
	check(world.camera_rig.target == car and world.camera_rig.profile == &"in_car", "camera follows the car with in_car profile")
	check(world.get_hud_state()["prompt"] == "", "no foot prompt while driving")
	check(world.get_hud_state()["speed_kmh"] >= 0.0, "HUD speed shown in the car")
	await _press(&"interact")
	check(world.control_mode == &"on_foot", "E exits the car")
	var player := world.player
	check(player.visible and player.input_enabled, "Ilyusha visible and controllable after exit")
	check(player.global_position.distance_to(car.global_position) < 4.0, "Ilyusha appears next to the car")
	check(world.camera_rig.target == player and world.camera_rig.profile == &"on_foot", "camera back on foot")
	await _frames(20)
	check(player.is_on_floor(), "Ilyusha stands on the ground after exit")
	check(_overlaps_world(player.global_position) == false, "exit spot is free of walls and the car")
	var start := player.global_position
	world.camera_rig.yaw = 0.0
	Input.action_press(&"move_forward")
	await _frames(30)
	Input.action_release(&"move_forward")
	check(player.global_position.distance_to(start) > 1.0, "Ilyusha walks after exit")

func _overlaps_world(point: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1 | 4
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.8)
	return not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

# --- вход сообщает миссии (C4/C5) ---

func _check_quest_hook() -> void:
	var mission := world.mission
	mission.interact(&"babka")
	mission.accept()
	check(mission.state == MissionDirector.GO_TO_CAR, "quest accepted: GO_TO_CAR")
	world.player.place(world.car.global_position + Vector3(-2.2, 0, 0), 0.0)
	await _frames(4)
	await _press(&"interact")
	check(mission.state == MissionDirector.DRIVE_TO_KIOSK, "entering the car moves the quest to DRIVE_TO_KIOSK")
	await _press(&"interact")
	await _frames(4)
	world.player.place(world.car.global_position + Vector3(-2.2, 0, 0), 0.0)
	await _frames(4)
	await _press(&"interact")
	check(mission.state == MissionDirector.DRIVE_TO_KIOSK and world.control_mode == &"in_car", "re-entering keeps DRIVE_TO_KIOSK")

# --- критерий 2: маршрут настоящим вводом ---

func _check_route() -> void:
	var car := world.car
	car.reset_to(Layout.ROUTE_DRIVE[0], Layout.CAR_SPAWN_YAW)
	await _frames(5)
	var start_frame := Engine.get_physics_frames()
	var top_speed := 0.0
	var ok := true
	for i in range(1, Layout.ROUTE_DRIVE.size()):
		var last := i == Layout.ROUTE_DRIVE.size() - 1
		var result: Dictionary = await _drive_to(Layout.ROUTE_DRIVE[i], last, Vector3.INF if last else Layout.ROUTE_DRIVE[i + 1])
		top_speed = maxf(top_speed, result["top"])
		if not result["ok"]:
			ok = false
			check(false, "drive route reaches point %d %s (stuck at %s)" % [i, Layout.ROUTE_DRIVE[i], car.global_position])
			break
	_release_all()
	await _frames(90)
	var seconds := (Engine.get_physics_frames() - start_frame) / 60.0
	print("INFO: drive yard→kiosk %.1f s, top speed %.0f km/h" % [seconds, top_speed * 3.6])
	check(ok, "Lada drives yard → kiosk by real input in %.1f s" % seconds)
	check(top_speed * 3.6 > 50.0, "Lada reaches city speed (%.0f km/h)" % (top_speed * 3.6))
	check(seconds > 15.0 and seconds < 60.0, "drive feels like a trip but not a chore (%.1f s)" % seconds)
	check(world.kiosk_zone.is_occupied(), "car stopped inside the kiosk zone")

func _drive_to(target: Vector3, final: bool, next: Vector3 = Vector3.INF) -> Dictionary:
	var car := world.car
	var corner := 0.0
	if next != Vector3.INF:
		var incoming := target - car.global_position
		incoming.y = 0.0
		corner = absf(incoming.normalized().signed_angle_to((next - target).normalized(), Vector3.UP))
	var best := INF
	var stalled := 0
	var top := 0.0
	while true:
		var delta := target - car.global_position
		delta.y = 0.0
		var distance := delta.length()
		if distance < (3.0 if final else 5.0):
			return {"ok": true, "top": top}
		var forward := -car.global_basis.z
		var error := forward.signed_angle_to(delta.normalized(), Vector3.UP)
		_steer(clampf(error * 2.5, -1.0, 1.0))
		var speed := Vector2(car.velocity.x, car.velocity.z).length()
		top = maxf(top, speed)
		var wanted := 20.0 if absf(error) < 0.25 else 8.0
		if corner > 0.6 and distance < 30.0:
			wanted = minf(wanted, 9.0)  # тормозить перед поворотом, как игрок
		if final:
			wanted = minf(wanted, distance * 0.8 + 2.0)
		Input.action_release(&"move_forward")
		Input.action_release(&"move_back")
		if speed < wanted:
			Input.action_press(&"move_forward")
		elif speed > wanted + 2.0:
			Input.action_press(&"move_back")
		await physics_frame
		if distance < best - 0.05:
			best = distance
			stalled = 0
		else:
			stalled += 1
			if stalled > 240:
				_release_all()
				return {"ok": false, "top": top}
	return {"ok": false, "top": top}

func _steer(value: float) -> void:
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	if value > 0.02:
		Input.action_press(&"move_left", value)
	elif value < -0.02:
		Input.action_press(&"move_right", -value)

# --- критерий 3: стены и откат ---

func _check_walls() -> void:
	var car := world.car
	car.reset_to(Vector3(-51, 0, 64), 0.0)  # нос на север, впереди стена H3 (z = 58)
	await _frames(3)
	Input.action_press(&"move_forward")
	await _frames(150)
	Input.action_release(&"move_forward")
	var nose := car.global_position.z - Lada.SIZE.z * 0.5
	check(nose >= 58.0 - 0.05, "Lada does not pass through a building (nose z=%.2f)" % nose)
	var stuck := car.global_position
	Input.action_press(&"move_back")
	await _frames(90)
	Input.action_release(&"move_back")
	check(car.global_position.z - stuck.z > 2.0, "Lada reverses away from the wall")
	car.reset_to(Vector3(-95, 0, 32), PI * 0.5)  # на запад, к краю карты
	await _frames(3)
	Input.action_press(&"move_forward")
	await _frames(150)
	Input.action_release(&"move_forward")
	check(car.global_position.x - Lada.SIZE.z * 0.5 >= -100.0 - 0.05, "Lada stays inside the map edge (x=%.2f)" % car.global_position.x)
	await _frames(30)

# --- критерий 4: ручник, занос, нет вращения на месте ---

func _check_handbrake() -> void:
	var coast := await _stop_distance(&"")
	var hand := await _stop_distance(&"handbrake")
	print("INFO: stop from speed — coasting %.1f m, handbrake %.1f m" % [coast, hand])
	check(hand < coast * 0.5, "handbrake shortens the stop noticeably (%.1f vs %.1f m)" % [hand, coast])
	var slide_plain := await _peak_slide(false)
	var slide_hand := await _peak_slide(true)
	print("INFO: peak lateral speed in a turn — plain %.2f m/s, handbrake %.2f m/s" % [slide_plain, slide_hand])
	check(slide_hand > 2.0 and slide_hand > slide_plain * 1.5, "handbrake turn produces a drift")
	check(slide_plain > 0.1, "wet road gives a slight slide without handbrake (%.2f m/s)" % slide_plain)
	var car := world.car
	car.reset_to(Vector3(0, 0, 32), -PI * 0.5)
	await _frames(3)
	var yaw := car.global_rotation.y
	Input.action_press(&"handbrake")
	Input.action_press(&"move_left")
	await _frames(60)
	_release_all()
	check(absf(angle_difference(car.global_rotation.y, yaw)) < 0.01, "car does not spin in place")

func _accelerate_east() -> void:
	var car := world.car
	car.reset_to(Vector3(-90, 0, 32), -PI * 0.5)  # на восток по улице A
	await _frames(3)
	Input.action_press(&"move_forward")
	await _frames(150)
	Input.action_release(&"move_forward")

func _stop_distance(action: StringName) -> float:
	await _accelerate_east()
	var car := world.car
	var start := car.global_position
	if action != &"":
		Input.action_press(action)
	var frames := 0
	while Vector2(car.velocity.x, car.velocity.z).length() > 0.3 and frames < 1200:
		await physics_frame
		frames += 1
	_release_all()
	return car.global_position.distance_to(start)

func _peak_slide(handbrake: bool) -> float:
	await _accelerate_east()
	var car := world.car
	var peak := 0.0
	Input.action_press(&"move_left")
	if handbrake:
		Input.action_press(&"handbrake")
	for i in 45:
		await physics_frame
		peak = maxf(peak, car.lateral_speed)
	_release_all()
	await _frames(60)
	return peak

# --- критерий 5: «Сбросить автомобиль» из паузы ---

func _check_reset() -> void:
	var car := world.car
	for mode in [&"in_car", &"on_foot"]:
		car.reset_to(Vector3(-62, 0, 70), 2.0)   # двор у детской площадки, боком к маршруту
		await _frames(5)
		if mode == &"on_foot" and world.control_mode == &"in_car":
			await _press(&"interact")
		elif mode == &"in_car" and world.control_mode == &"on_foot":
			world.enter_car()
		await _frames(3)
		main.set_paused(true)
		main.pause_menu.reset_car_requested.emit()
		await _frames(5)
		var on_route := _distance_to_route(car.global_position)
		check(on_route < 0.5, "reset puts the car on the drive route (%s, %.2f m)" % [mode, on_route])
		check(car.global_basis.y.dot(Vector3.UP) > 0.999 and car.velocity.length() < 0.5, "reset car is upright and still (%s)" % mode)
		check(not paused and not main.pause_menu.visible, "reset closes the pause (%s)" % mode)
		if mode == &"on_foot":
			check(car.global_position.distance_to(world.player.global_position) > 2.5, "reset does not drop the car onto Ilyusha")
		Input.action_press(&"move_forward")
		await _frames(60)
		Input.action_release(&"move_forward")
		await _frames(30)

func _distance_to_route(point: Vector3) -> float:
	var flat := Vector3(point.x, 0, point.z)
	var best := INF
	for i in range(1, Layout.ROUTE_DRIVE.size()):
		best = minf(best, flat.distance_to(Geometry3D.get_closest_point_to_segment(flat, Layout.ROUTE_DRIVE[i - 1], Layout.ROUTE_DRIVE[i])))
	return best

# --- критерий 6: многократные пересадки ---

func _check_repeat() -> void:
	var car := world.car
	car.reset_to(Vector3(0, 0, 32), -PI * 0.5)
	if world.control_mode == &"in_car":
		await _press(&"interact")
	var consistent := true
	for i in 6:
		world.player.place(car.global_position + car.global_basis * Vector3(-2.2, 0, 0), 0.0)
		await _frames(4)
		await _press(&"interact")
		consistent = consistent and world.control_mode == &"in_car" and world.camera_rig.target == car and not world.player.visible
		Input.action_press(&"move_forward")
		await _frames(20)
		Input.action_release(&"move_forward")
		await _frames(40)
		await _press(&"interact")
		consistent = consistent and world.control_mode == &"on_foot" and world.camera_rig.target == world.player and world.player.visible and world.player.input_enabled
	check(consistent, "six enter/exit cycles keep input, camera and visibility consistent")

# --- служебное ---

func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)

func _release_all() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"handbrake"]:
		Input.action_release(action)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	print("DRIVE01: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
