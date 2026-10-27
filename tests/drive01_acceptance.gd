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
	await _check_review_gaps()
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

# --- пробелы из независимого ревью ---

func _check_review_gaps() -> void:
	var car := world.car
	await _ensure_in_car()
	# Выход на ходу: машина сама тормозит, Илюша выходит после остановки.
	await _accelerate_east()
	var speed_before := car.speed_kmh()
	await _press(&"interact")
	check(world.control_mode == &"in_car", "E at %.0f km/h does not throw Ilyusha out at speed" % speed_before)
	var frames := 0
	while world.control_mode == &"in_car" and frames < 400:
		await physics_frame
		frames += 1
	check(world.control_mode == &"on_foot", "after braking Ilyusha exits (%.1f s)" % (frames / 60.0))
	check(car.speed_kmh() < Lada.EXIT_SPEED_KMH + 0.5 and world.player.global_position.distance_to(car.global_position) < 5.0, "exit happens next to a stopped car")
	await _frames(60)
	check(car.speed_kmh() < 0.5, "car without a driver stays still")
	# Нет места для выхода: остаёмся в машине и видим подсказку.
	car.reset_to(Vector3(0, 0, 32), -PI * 0.5)
	await _ensure_in_car()
	var walls := []
	for spec in [[Vector3(0, 1, 34.3), Vector3(9, 2, 2)], [Vector3(0, 1, 29.7), Vector3(9, 2, 2)], [Vector3(3.6, 1, 32), Vector3(1, 2, 3)], [Vector3(-3.6, 1, 32), Vector3(1, 2, 3)]]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		body.add_child(shape)
		body.position = spec[0]
		world.add_child(body)
		walls.append(body)
	await _frames(3)
	await _press(&"interact")
	await _frames(3)
	check(world.control_mode == &"in_car", "with every exit blocked Ilyusha stays in the car")
	check(world.get_hud_state()["prompt"] == DemoWorld.HINT_NO_EXIT, "HUD says there is no room to exit: '%s'" % world.get_hud_state()["prompt"])
	await _frames(150)
	check(world.get_hud_state()["prompt"] == "", "no-exit hint disappears after 2 s")
	for body in walls:
		body.queue_free()
	await _frames(3)
	await _press(&"interact")
	await _frames(3)
	check(world.control_mode == &"on_foot", "exit works once the way is clear")
	# Выход у края карты: место за границей не выбирается.
	car.reset_to(Vector3(-98.9, 0, -20), 0.0)
	await _ensure_in_car()
	await _press(&"interact")
	await _frames(3)
	var p := world.player.global_position
	check(world.control_mode == &"on_foot" and Layout.BOUNDS.has_point(Vector2(p.x, p.z)), "exit at the map edge stays inside the map (%s)" % p)
	# Сброс пешком, когда Илюша стоит на маршруте рядом с машиной.
	world.player.place(Vector3(0, 0, 32), 0.0)
	car.reset_to(Vector3(4, 0, 36), 1.0)
	await _frames(5)
	main.set_paused(true)
	main.pause_menu.reset_car_requested.emit()
	await _frames(5)
	check(car.global_position.distance_to(world.player.global_position) >= DemoWorld.RESET_CLEARANCE - 0.01, "reset next to Ilyusha keeps clearance (%.1f m)" % car.global_position.distance_to(world.player.global_position))
	check(_distance_to_route(car.global_position) < 0.5, "reset next to Ilyusha still lands on the route")
	# Знак руления на заднем ходу: руль влево — нос уходит вправо.
	car.reset_to(Vector3(0, 0, 32), -PI * 0.5)
	await _ensure_in_car()
	Input.action_press(&"move_back")
	await _frames(70)
	var yaw := car.global_rotation.y
	Input.action_press(&"move_left")
	await _frames(30)
	_release_all()
	check(angle_difference(yaw, car.global_rotation.y) < -0.05, "reversing with left steer turns the nose right")
	# Радиус поворота растёт со скоростью.
	var slow := await _turn_radius(6.0)
	var fast := await _turn_radius(19.0)
	print("INFO: turn radius %.1f m at 6 m/s, %.1f m at 19 m/s" % [slow, fast])
	check(fast > slow * 1.5, "turn radius grows with speed (%.1f → %.1f m)" % [slow, fast])

## Подготовка сценария: посадить в машину напрямую (путь по E проверен в _check_enter_exit).
func _ensure_in_car() -> void:
	await _frames(2)
	if world.control_mode == &"on_foot":
		world.enter_car()
	await _frames(2)

func _turn_radius(speed: float) -> float:
	var car := world.car
	car.reset_to(Vector3(-60, 0, 32), -PI * 0.5)
	await _frames(2)
	car.velocity = -car.global_basis.z * speed
	var yaw := car.global_rotation.y
	Input.action_press(&"move_left")
	var travelled := 0.0
	for i in 20:
		var before := car.global_position
		await physics_frame
		travelled += before.distance_to(car.global_position)
	_release_all()
	var turned := absf(angle_difference(yaw, car.global_rotation.y))
	await _frames(60)
	return travelled / maxf(turned, 0.0001)

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
