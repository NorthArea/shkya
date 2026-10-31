extends SceneTree
## GREY-01: настоящий main.tscn, мир из Layout, ввод через Input. Критерии — карточка GREY-01.

const Layout = preload("res://game/world/layout.gd")

var failures: Array[String] = []
var checks := 0
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(600.0, true, false, true).timeout.connect(func():
		push_error("FAIL: grey01 exceeded 600 simulated seconds")
		quit(2)
	)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	check(main.menu.visible and main.world == null, "menu shown on launch, no world yet")
	main.menu.start_button.pressed.emit()
	await _frames(10)
	var world: DemoWorld = main.world
	check(world != null and not main.menu.visible, "НАЧАТЬ creates DemoWorld and hides menu")
	if world == null:
		_finish()
		return
	for name in ["LevelGeometry", "LightingAndWeather", "Ilyusha", "Car", "Babka", "Vendor", "KioskZone", "CameraRig", "MissionDirector", "GameHUD"]:
		check(world.has_node(name), "DemoWorld has %s (canon §7)" % name)
	_check_layout(world)
	_check_ring()
	await _check_spawn_and_hud(world)
	await _check_camera_relative(world)
	await _check_camera_follow(world)
	await _check_walls(world)
	await _check_interaction(world)
	await _check_kiosk_zone(world)
	await _check_review_gaps(world)
	await _check_route(world)
	await _check_pause(world)
	await _check_restart(world)
	_finish()

# --- критерий 2: раскладка ---

func _check_layout(world: DemoWorld) -> void:
	var b := Layout.BOUNDS
	var outside := []
	for body in world.get_node("LevelGeometry").get_children():
		if not body is StaticBody3D or body.name.begins_with("Bound_") or body.name == "Ground":
			continue
		var shape: BoxShape3D = body.get_child(0).shape
		var lo: Vector3 = body.position - shape.size * 0.5
		var hi: Vector3 = body.position + shape.size * 0.5
		if lo.x < b.position.x or hi.x > b.end.x or lo.z < b.position.y or hi.z > b.end.y or lo.y < -0.001:
			outside.append(body.name)
	check(outside.is_empty(), "all solids inside 200x250 bounds and on the ground %s" % [outside])
	check(is_equal_approx(b.size.x, 200.0) and is_equal_approx(b.size.y, 250.0), "map is 200x250 m")
	var points := {"spawn": Layout.SPAWN, "babka": Layout.BABKA, "car": Layout.CAR_SPAWN, "window": Layout.VENDOR_WINDOW}
	for i in Layout.ROUTE_WALK.size():
		points["walk%d" % i] = Layout.ROUTE_WALK[i]
	for i in Layout.ROUTE_DRIVE.size():
		points["drive%d" % i] = Layout.ROUTE_DRIVE[i]
	for key in points:
		var p: Vector3 = points[key]
		check(b.has_point(Vector2(p.x, p.z)) and is_zero_approx(p.y), "point %s inside bounds at ground level" % key)
		var hit := _solid_at(p, 0.5)
		check(hit == "", "point %s is not inside solid %s" % [key, hit])
	# EXT-01 (приёмка 28.10): парковка — южнее павильона, окно в KIOSK_ZONE не входит; пешком у окна прибытие
	# засчитывает KIOSK_WINDOW_ZONE.
	check(not Layout.KIOSK_ZONE.has_point(Layout.VENDOR_WINDOW + Vector3.UP), "vendor window is outside the parking zone KIOSK_ZONE")
	check(Layout.KIOSK_WINDOW_ZONE.has_point(Layout.VENDOR_WINDOW + Vector3.UP), "vendor window is inside the on-foot KIOSK_WINDOW_ZONE")
	check(Layout.VENDOR_WINDOW.distance_to(Layout.ROUTE_DRIVE[-1]) > 20.0, "kiosk parking is > 20 m from the window (%.1f m)" % Layout.VENDOR_WINDOW.distance_to(Layout.ROUTE_DRIVE[-1]))
	check(Layout.KIOSK_ZONE.has_point(Layout.ROUTE_DRIVE[-1] + Vector3.UP), "drive route ends inside kiosk zone")
	var drive := 0.0
	for i in range(1, Layout.ROUTE_DRIVE.size()):
		drive += Layout.ROUTE_DRIVE[i].distance_to(Layout.ROUTE_DRIVE[i - 1])
	print("INFO: drive route length %.1f m" % drive)
	check(drive >= 150.0 and drive <= 300.0, "drive yard→kiosk is a trip, not a chore (%.0f m)" % drive)

# --- ARENA-01 (C8): кольцо дорог ---

const RING_ROAD_MARGIN := 1.5    # м от оси полосы до края проезжей части: половина троллейбуса 1,25 + запас
const RING_CLEARANCE := 2.05     # м от оси полосы до коробок: половина троллейбуса 1,25 + 0,8 (C8: от припаркованных)

## Ось правой полосы кольца со скруглёнными углами идёт по проезжей части (не по тротуару) и держит зазор от всех
## коробок — домов, валов, фонарей, машин, павильонов. Шаг 0,5 м по всей замкнутой ломаной.
func _check_ring() -> void:
	_check_lane(Layout.ring_lane(), "ring lane")
	# Встречная полоса машин (ARENA-01 fix P2-2): CAR_RING, скругление PathVehicle.CAR_TURN_RADIUS.
	_check_lane(Layout.ring_lane(PathVehicle.CAR_TURN_RADIUS, 6, true), "car lane")

func _check_lane(lane: Array[Vector3], title: String) -> void:
	var roads := Layout.SURFACES.filter(func(spec): return spec[1] == "road")
	var off_road := []
	var blocked := []
	var seen := {}
	var length := 0.0
	for i in lane.size():
		var a: Vector3 = lane[i]
		var b: Vector3 = lane[(i + 1) % lane.size()]
		length += a.distance_to(b)
		var steps := maxi(1, int(a.distance_to(b) / 0.5))
		for s in steps:
			var p := a.lerp(b, float(s) / steps)
			# На проезжей части и точки в RING_ROAD_MARGIN вокруг — тоже (улицы примыкают друг к другу без зазора).
			var inside := true
			for k in 9:
				var q := p + (Vector3.ZERO if k == 8 else Vector3(RING_ROAD_MARGIN, 0, 0).rotated(Vector3.UP, k * PI / 4.0))
				var on_road := false
				for spec in roads:
					var c: Vector2 = spec[2]
					var size: Vector2 = spec[3]
					if absf(q.x - c.x) <= size.x * 0.5 and absf(q.z - c.y) <= size.y * 0.5:
						on_road = true
						break
				inside = inside and on_road
			if not inside and off_road.size() < 5:
				off_road.append(Vector2(p.x, p.z))
			var hit := _solid_near(p, RING_CLEARANCE)
			if hit != "" and not seen.has(hit):
				seen[hit] = true
				blocked.append("%s@(%.0f,%.0f)" % [hit, p.x, p.z])
	print("INFO: %s length %.0f m, %d corner points" % [title, length, lane.size()])
	check(length > 450.0, "%s closes around the block (%.0f m)" % [title, length])
	check(off_road.is_empty(), "%s stays on the carriageway, %.1f m inside the road edge %s" % [title, RING_ROAD_MARGIN, off_road])
	check(blocked.is_empty(), "%s keeps %.2f m from solids (parked cars, banks, lamps, houses) %s" % [title, RING_CLEARANCE, blocked.slice(0, 6)])

## Первая коробка ближе margin к точке в плане — по настоящему расстоянию до прямоугольника (у углов — по дуге),
## а не по коробке, раздутой на margin: ось полосы на повороте обходит угол вала по кругу.
func _solid_near(p: Vector3, margin: float) -> String:
	for spec in Layout.all_solids():
		var xz: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		var d := (Vector2(p.x, p.z) - xz).abs() - Vector2(size.x, size.z) * 0.5
		if Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() < margin:
			return spec[0]
	return ""

func _solid_at(p: Vector3, margin: float) -> String:
	for spec in Layout.all_solids():
		var xz: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		if absf(p.x - xz.x) < size.x * 0.5 + margin and absf(p.z - xz.y) < size.z * 0.5 + margin:
			return spec[0]
	return ""

# --- появление и HUD ---

func _check_spawn_and_hud(world: DemoWorld) -> void:
	var player := world.player
	check(player.global_position.distance_to(Layout.SPAWN) < 0.3, "Ilyusha spawns at Layout.SPAWN")
	check(player.is_on_floor(), "Ilyusha stands on the ground")
	check(world.camera_rig.camera.current, "CameraRig camera is current")
	var hud := world.get_hud_state()
	check(hud["title"] == "ГОРОД Н." and hud["task"] == "Подойди к Бабке", "HUD objective of frame 01: %s / %s" % [hud["title"], hud["task"]])
	check(hud["target_position"] is Vector3 and hud["target_position"].distance_to(Layout.BABKA) < 0.01, "HUD target is Babka")
	check(hud["babka_marker"] == "!", "babka marker is ! before the quest")
	check(hud["prompt"] == "", "no E prompt at spawn (Babka is %.1f m away)" % Layout.SPAWN.distance_to(Layout.BABKA))
	check(hud["speed_kmh"] < 0.0, "no speed on foot")
	var labels = world.get_node("GameHUD")
	check(labels.title_label.text == "ГОРОД Н." and labels.task_label.text.ends_with("Подойди к Бабке"), "GameHUD shows the objective")

# --- критерий 5: ходьба относительно камеры ---

func _check_camera_relative(world: DemoWorld) -> void:
	var player := world.player
	for case in [[PI * 0.5, Vector3.LEFT, "west"], [0.0, Vector3.FORWARD, "north"]]:
		player.place(Layout.SPAWN, 0.0)
		world.camera_rig.yaw = case[0]
		await _frames(2)
		var start := player.global_position
		Input.action_press(&"move_forward")
		await _frames(40)
		Input.action_release(&"move_forward")
		await _frames(10)
		var moved := player.global_position - start
		moved.y = 0.0
		var along := moved.dot(case[1])
		check(along > 2.0 and moved.length() - along < 0.3, "W with camera yaw %s walks %s (moved %s)" % [case[0], case[2], moved])

# --- POLISH-03 C: доводка камеры пешком (за спину через ~0,5 с, при ходьбе на камеру — облёт), тонкие столбы ---

func _check_camera_follow(world: DemoWorld) -> void:
	var player := world.player
	var rig := world.camera_rig
	var dt := 1.0 / Engine.physics_ticks_per_second
	# 1. Ходьба на камеру: улица A, камера смотрит на восток, S — Илюша идёт на запад, лицом к камере.
	player.place(Vector3(20, 0, 32), -PI * 0.5)
	rig.yaw = -PI * 0.5
	rig.snap()
	await _frames(70)   # пауза ручной камеры
	var yaw0 := rig.yaw
	var start := player.global_position
	var still_until := -1.0
	var max_step := 0.0
	var prev := rig.yaw
	Input.action_press(&"move_back")
	for i in 210:
		await _frames(1)
		var step := absf(angle_difference(prev, rig.yaw))
		max_step = maxf(max_step, step)
		prev = rig.yaw
		if still_until < 0.0 and absf(angle_difference(yaw0, rig.yaw)) > 0.01:
			still_until = (i + 1) * dt
	Input.action_release(&"move_back")
	await _frames(10)
	var moved := player.global_position - start
	var behind := absf(angle_difference(rig.yaw, rig.follow_heading))
	check(still_until >= CameraRig.TURN_AROUND_DELAY - 0.05, "walking toward the camera: it holds for %.2f s before swinging (≥ %.1f)" % [still_until, CameraRig.TURN_AROUND_DELAY])
	check(behind < 0.35, "walking toward the camera: after 3.5 s the camera is behind Ilyusha (%.2f rad off)" % behind)
	check(max_step <= CameraRig.AUTO_FOLLOW_SPEED * dt + 0.002, "camera swing is smooth: max %.3f rad per frame (≤ %.3f)" % [max_step, CameraRig.AUTO_FOLLOW_SPEED * dt])
	check(moved.x < -8.0 and absf(moved.z) < 1.0, "Ilyusha keeps walking west while the camera swings (moved %s)" % moved)
	# 2. Ходьба вбок: доводка начинается не раньше AUTO_FOLLOW_DELAY и приводит камеру за спину.
	player.place(Vector3(20, 0, 32), 0.0)
	rig.yaw = 0.0
	rig.snap()
	await _frames(70)
	Input.action_press(&"move_left")
	await _frames(int(CameraRig.AUTO_FOLLOW_DELAY * 60.0) - 6)
	var early := absf(angle_difference(0.0, rig.yaw))
	await _frames(150)
	Input.action_release(&"move_left")
	var side_off := absf(angle_difference(rig.yaw, rig.follow_heading))
	check(early < 0.01, "no auto-follow before %.1f s of walking (%.3f rad)" % [CameraRig.AUTO_FOLLOW_DELAY, early])
	check(side_off < 0.3, "walking sideways: the camera settles behind Ilyusha (%.2f rad off)" % side_off)
	# 3. Ручная камера в приоритете: пока двигают мышью/стиком, доводки нет.
	player.place(Vector3(20, 0, 32), 0.0)
	rig.yaw = 0.0
	rig.snap()
	await _frames(70)
	Input.action_press(&"move_back")
	var drift := 0.0
	for i in 120:
		rig.apply_mouse(Vector2.ZERO)
		await _frames(1)
		drift = maxf(drift, absf(angle_difference(0.0, rig.yaw)))
	Input.action_release(&"move_back")
	check(drift < 0.001, "manual camera has priority: no auto-follow while the mouse moves (%.4f rad)" % drift)
	await _frames(20)
	# 4. Фонарь в валу не притягивает камеру к затылку (критик, v05); стена дома — притягивает.
	var h3: Array = Layout.SOLIDS.filter(func(spec): return spec[0] == "H3_North")[0]
	var h3_face_z: float = h3[2].y + h3[3].z * 0.5
	# Прежние 0,6 м от фасада: дом сдвинулся, старт должен оставаться снаружи.
	var h3_start := Vector3(h3[2].x, 0.0, h3_face_z + 0.6)
	var cases := [
		[Vector3(55, 0, 40), atan2(55.0 - 75.0, 40.0 - 20.0), true, "lamp in the snow bank at A∩B"],
		[h3_start, PI, false, "H3 wall behind"],
	]
	for c in cases:
		player.place(c[0], 0.0)
		rig.yaw = c[1]
		rig.pitch = -0.25
		rig.snap()
		await _frames(90)
		var hit: float = rig.arm.get_hit_length()
		if c[2]:
			check(hit > float(CameraRig.PROFILES[&"on_foot"]["distance"]) - 0.3, "%s: spring arm stays long (%.2f m)" % [c[3], hit])
			var head: Vector3 = player.global_position + Vector3.UP * 1.5
			var ray := PhysicsRayQueryParameters3D.create(rig.camera.global_position, head, 1, [player.get_rid()])
			var seen: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
			check(seen.is_empty(), "%s: the camera steps aside, the pole does not cover Ilyusha (%s)" % [c[3], seen["collider"].name if not seen.is_empty() else "clear"])
			var faded: Array = rig.faded_poles()
			var near_opaque := 0
			for body in rig._thin.values():
				if Vector2(body.global_position.x - rig.camera.global_position.x, body.global_position.z - rig.camera.global_position.z).length() < CameraRig.POLE_FADE_NEAR and not faded.has(body):
					near_opaque += 1
			check(absf(rig._dodge) > 0.2 and near_opaque == 0, "%s: camera steps %.2f m aside, no opaque pole right at the lens (%d faded)" % [c[3], rig._dodge, faded.size()])
		else:
			check(hit < 2.5, "%s: spring arm still shortens at a wall (%.2f m)" % [c[3], hit])
			var lift: float = rig.camera.global_position.y - player.global_position.y
			check(lift >= float(CameraRig.PROFILES[&"on_foot"]["height"]) + 0.3, "%s: squeezed camera rises over the head, not into it (%.2f m)" % [c[3], lift])
	rig.pitch = CameraRig.PROFILES[&"on_foot"]["pitch"]

# --- критерий 4: стены и сугробы ---

func _check_walls(world: DemoWorld) -> void:
	var player := world.player
	var cases := [
		# старт, yaw камеры, ось, граница, знак: игрок должен остаться по эту сторону
		[Vector3(-51, 0, 62), 0.0, "z", 58.0 + 0.3, 1.0, "H3 wall"],
		[Vector3(-70, 0, 80), PI * 0.5, "x", -73.5 + 0.3, 1.0, "yard snow bank"],
		[Vector3(-95, 0, 32), PI * 0.5, "x", -100.0 + 0.3, 1.0, "map edge"],
	]
	for case in cases:
		player.place(case[0], 0.0)
		world.camera_rig.yaw = case[1]
		await _frames(2)
		Input.action_press(&"move_forward")
		await _frames(150)
		Input.action_release(&"move_forward")
		await _frames(5)
		var value: float = player.global_position.x if case[2] == "x" else player.global_position.z
		check((value - case[3]) * case[4] >= 0.0, "%s blocks walking (%s=%.2f, limit %.2f)" % [case[5], case[2], value, case[3]])

# --- критерий 6: подсказки и E ---

func _check_interaction(world: DemoWorld) -> void:
	var player := world.player
	var mission := world.mission
	var counts := {"babka": 0, "vendor": 0}
	world.babka.interactable.interacted.connect(func(_a): counts["babka"] += 1)
	world.vendor.interactable.interacted.connect(func(_a): counts["vendor"] += 1)
	player.place(Layout.BABKA + Vector3(0, 0, -2.2), 0.0)
	await _frames(4)
	check(world.get_hud_state()["prompt"] == "E — ПОГОВОРИТЬ", "E prompt next to Babka: '%s'" % world.get_hud_state()["prompt"])
	await _press_interact()
	check(counts["babka"] == 1 and counts["vendor"] == 0, "E next to Babka fires Babka interaction once (%s)" % [counts])
	await _close_dialog(world, &"decline")
	player.place(Layout.VENDOR_WINDOW, 0.0)
	await _frames(4)
	check(world.get_hud_state()["prompt"] == "", "vendor has no prompt before BUY_BREAD")
	await _press_interact()
	check(counts["vendor"] == 0, "E at the kiosk does nothing before BUY_BREAD")
	mission.interact(&"babka")
	mission.accept()
	mission.notify_entered_car()
	mission.notify_arrived_kiosk()
	check(mission.state == MissionDirector.BUY_BREAD, "mission driven to BUY_BREAD through its API")
	await _frames(2)
	check(world.get_hud_state()["prompt"] == "E — ПОГОВОРИТЬ", "vendor prompt in BUY_BREAD")
	await _press_interact()
	check(counts["vendor"] == 1, "E at the kiosk window fires vendor interaction")
	await _close_dialog(world, &"leave")
	player.place(Layout.SPAWN, 0.0)
	await _frames(4)
	check(world.get_hud_state()["prompt"] == "", "prompt disappears away from interactables")
	await _press_interact()
	check(counts["babka"] == 1 and counts["vendor"] == 1, "E far from everyone does nothing")

## E у Бабки и продавщицы открывает диалог QUEST-01; закрыть его кнопкой, как игрок.
## EXT-01: первая реплика продавщицы — цепочка, кнопки выбора на последней; долистать «ДАЛЬШЕ».
func _close_dialog(world: DemoWorld, button: StringName) -> void:
	var flow = world.get_node("QuestFlow")
	check(flow.is_dialog_open() and world.ui_blocking, "E opens a dialog that blocks walking")
	while flow.is_dialog_open() and not flow.dialog.is_last_line():
		flow.dialog.finish_typing()
		flow.dialog.advance()
	if flow.is_dialog_open() and flow.dialog.buttons.has(button):
		flow.dialog.buttons[button].pressed.emit()
	await _frames(2)
	check(not flow.is_dialog_open() and not world.ui_blocking and world.player.input_enabled, "dialog closed by '%s', walking restored" % button)

func _press_interact() -> void:
	var down := InputEventAction.new()
	down.action = &"interact"
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)

# --- критерий 7: зона киоска ---

func _check_kiosk_zone(world: DemoWorld) -> void:
	var zone = world.kiosk_zone
	world.player.place(Layout.VENDOR_WINDOW, 0.0)
	await _frames(3)
	check(zone.is_occupied(), "KioskZone sees Ilyusha on foot at the window")
	world.player.place(Layout.SPAWN, 0.0)
	await _frames(3)
	check(not zone.is_occupied(), "KioskZone is empty when Ilyusha leaves")
	var probe := CharacterBody3D.new()
	probe.collision_layer = 4
	probe.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 1.4, 4.1)
	shape.shape = box
	probe.add_child(shape)
	probe.position = Layout.ROUTE_DRIVE[-1] + Vector3(0, 0.7, 0)
	world.add_child(probe)
	await _frames(3)
	check(zone.is_occupied(), "KioskZone sees a body on the Car layer")
	probe.position = Layout.VENDOR_WINDOW + Vector3(1.0, 0.7, 0)
	await _frames(3)
	check(not zone.is_occupied(), "a car at the kiosk window is not an arrival (only the parking counts for the car)")
	probe.queue_free()
	await _frames(3)

# --- пробелы из независимого ревью ---

func _check_review_gaps(world: DemoWorld) -> void:
	# Коридор машины: каждый участок маршрута в 1 м от любых коробок (ширина «Лады» 1,7 м).
	var blocked := []
	for i in range(1, Layout.ROUTE_DRIVE.size()):
		var a := Layout.ROUTE_DRIVE[i - 1]
		var b := Layout.ROUTE_DRIVE[i]
		var steps := int(a.distance_to(b) / 0.5)
		for s in steps + 1:
			var hit := _solid_at(a.lerp(b, float(s) / maxf(steps, 1)), 1.0)
			if hit != "":
				blocked.append("%d:%s" % [i, hit])
				break
	check(blocked.is_empty(), "drive route segments keep 1 m clearance from solids %s" % [blocked])
	# Мышь: вправо — камера и ходьба вправо.
	var rig := world.camera_rig
	var player := world.player
	player.place(Layout.SPAWN, 0.0)
	rig.yaw = 0.0
	rig.apply_mouse(Vector2(400, 0))
	check(rig.yaw < -0.5, "mouse right turns the camera right (yaw %.2f)" % rig.yaw)
	await _frames(2)
	var start := player.global_position
	Input.action_press(&"move_forward")
	await _frames(30)
	Input.action_release(&"move_forward")
	await _frames(5)
	check(player.global_position.x - start.x > 1.0, "after mouse right, W walks to the east")
	rig.apply_mouse(Vector2(0, 10000))
	check(is_equal_approx(rig.pitch, CameraRig.PITCH_MIN), "pitch is clamped")
	rig.pitch = CameraRig.PROFILES[&"on_foot"]["pitch"]
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN: mouse capture modes need a window (run this test without --headless)")
	else:
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse captured in game")
		main.set_paused(true)
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse visible in pause")
		main.set_paused(false)
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse captured again after resume")
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(200, 0)
		var before := rig.yaw
		Input.parse_input_event(motion)
		await _frames(2)
		check(rig.yaw < before, "real mouse motion turns the camera while captured")
	# Илюша не проходит сквозь «Ладу».
	var car: Node3D = world.car
	player.place(car.global_position + Vector3(-3.0, 0, 0), 0.0)
	rig.yaw = -PI * 0.5  # смотреть на восток, на машину
	await _frames(2)
	Input.action_press(&"move_forward")
	await _frames(90)
	Input.action_release(&"move_forward")
	check(player.global_position.x < car.global_position.x - 0.85 - 0.3, "Ilyusha is blocked by the car (x %.2f, car %.2f)" % [player.global_position.x, car.global_position.x])
	# Выключенная зона не срабатывает даже при прямом вызове.
	var fired := [0]
	var zone: Interactable = world.babka.interactable
	var counter := func(_a): fired[0] += 1
	zone.interacted.connect(counter)
	zone.enabled = false
	zone.interact(player)
	check(fired[0] == 0, "disabled Interactable does not fire")
	zone.interacted.disconnect(counter)
	await _frames(2)

# --- критерий 3: маршрут пешком настоящим вводом ---

func _check_route(world: DemoWorld) -> void:
	var player := world.player
	player.place(Layout.ROUTE_WALK[0], 0.0)
	await _frames(2)
	var start_frame := Engine.get_physics_frames()
	var ok := true
	for i in range(1, Layout.ROUTE_WALK.size()):
		if not await _walk_to(world, Layout.ROUTE_WALK[i]):
			ok = false
			check(false, "walk route reaches point %d %s (stuck at %s)" % [i, Layout.ROUTE_WALK[i], player.global_position])
			break
	Input.action_release(&"move_forward")
	var seconds := (Engine.get_physics_frames() - start_frame) / 60.0
	print("INFO: walk spawn→kiosk %.1f s" % seconds)
	check(ok, "Ilyusha walks spawn → kiosk window by real input in %.1f s" % seconds)
	check(ok and seconds > 45.0 and seconds < 75.0, "walk time matches walking speed (%.1f s for ~255 m)" % seconds)
	check(ok and player.is_on_floor(), "Ilyusha is on the ground at the kiosk")

func _walk_to(world: DemoWorld, target: Vector3) -> bool:
	var player := world.player
	var best := INF
	var stalled := 0
	Input.action_press(&"move_forward")
	while true:
		var delta := target - player.global_position
		delta.y = 0.0
		var distance := delta.length()
		if distance < 0.8:
			return true
		world.camera_rig.yaw = atan2(-delta.x, -delta.z)
		await physics_frame
		if distance < best - 0.05:
			best = distance
			stalled = 0
		else:
			stalled += 1
			if stalled > 90:
				Input.action_release(&"move_forward")
				return false
	return false

# --- пауза и перезапуск ---

func _check_pause(world: DemoWorld) -> void:
	world.player.place(Layout.SPAWN, 0.0)
	world.camera_rig.yaw = 0.0
	await _frames(3)
	var pause := InputEventKey.new()
	pause.physical_keycode = KEY_ESCAPE
	pause.pressed = true
	Input.parse_input_event(pause)
	await _frames(2)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(release)
	await _frames(2)
	check(paused and main.pause_menu.visible, "physical Esc pauses the game and shows the pause menu")
	var before := world.player.global_position
	Input.action_press(&"move_forward")
	await _frames(30)
	Input.action_release(&"move_forward")
	check(world.player.global_position.distance_to(before) < 0.01, "Ilyusha does not move while paused")
	# PAUSE-01: сигнал GUI не должен возобновлять физику между flush_queries и step.
	await process_frame
	main.pause_menu.resume_requested.emit()
	await _frames(2)
	check(not paused and not main.pause_menu.visible, "ПРОДОЛЖИТЬ resumes")

func _check_restart(old_world: DemoWorld) -> void:
	main.set_paused(true)
	main.pause_menu.restart_requested.emit()
	await _frames(5)
	var world: DemoWorld = main.world
	check(not is_instance_valid(old_world), "НАЧАТЬ ЗАНОВО frees the old world")
	check(world != null and world.mission.state == MissionDirector.NOT_STARTED, "restart begins at NOT_STARTED")
	check(world != null and world.player.global_position.distance_to(Layout.SPAWN) < 0.3, "restart puts Ilyusha at spawn")
	check(not paused and not main.pause_menu.visible, "restart unpauses")
	main.set_paused(true)
	main.pause_menu.menu_requested.emit()
	await _frames(3)
	check(main.world == null and main.menu.visible and not paused, "В ГЛАВНОЕ МЕНЮ returns to the menu")
	main.menu.start_button.pressed.emit()
	await _frames(5)
	check(main.world != null and main.world.mission.state == MissionDirector.NOT_STARTED, "start from menu again begins at NOT_STARTED")

# --- служебное ---

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
	print("GREY01: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
