extends SceneTree
## DRIVE-02 (C10): «Лада» по сугробам — SnowField, слой 7 «SnowBank», физика на валу, эффекты; «вкус» аркады
## (DRIVE-03, вариант A): перенос веса, дым и следы заноса, отскок с тряской камеры, скрип. Настоящий main.tscn,
## ввод через Input. Транспорт кольца убран (едет по той же улице A), жители — только в своей проверке.

const Layout = preload("res://game/world/layout.gd")

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var car: Lada
var bank_a: Array   # [центр, размер] северного вала улицы A
var cross_x := 0.0  # x свободного места на валу A (без столбов и деревьев рядом)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(600.0, true, false, true).timeout.connect(func():
		push_error("FAIL: drive02 exceeded 600 simulated seconds")
		quit(2)
	)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.start_game()
	await _frames(10)
	world = main.world
	car = world.car
	_check_field()
	_check_layers()
	await _check_residents()
	var traffic := world.get_node_or_null("LevelGeometry/Traffic")
	if traffic:
		traffic.free()
	var residents := world.get_node_or_null("LevelGeometry/Residents")
	if residents:
		residents.free()
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false
	_pick_bank_a()
	await _check_walker()
	world.enter_car()
	await _frames(3)
	await _check_cross_fast()
	await _check_slow_spin()
	await _check_along_bank()
	await _check_exit_on_bank()
	await _check_weight_transfer()
	await _check_skid()
	await _check_bounce()
	_finish()

# --- SnowField: одна форма ---

func _check_field() -> void:
	var boxes := SnowField.boxes()
	var expected := 0
	for spec in Layout.all_solids():
		if spec[1] == "snow" or spec[1] == "snow_bank":
			expected += 1
	check(boxes.size() == expected and expected > 20, "SnowField covers every snow/snow_bank box (%d of %d)" % [boxes.size(), expected])
	var top := 0.0
	var outside_zero := true
	var inside_snow := true
	for b in boxes:
		var c: Vector2 = b[0]
		var size: Vector2 = b[1]
		var h := SnowField.height_at(c.x, c.y)
		top = maxf(top, h)
		inside_snow = inside_snow and h > float(b[2]) * 0.5
		# За коробкой + MARGIN снега нет (по оси короткой стороны, вне соседних коробок).
		var short_x := size.x < size.y
		var probe := c + (Vector2(size.x * 0.5 + SnowField.MARGIN + 0.01, 0) if short_x else Vector2(0, size.y * 0.5 + SnowField.MARGIN + 0.01))
		var near_other := false
		for o in boxes:
			if o != b and _in_rect(probe, o[0], o[1] * 0.5 + Vector2.ONE * (SnowField.MARGIN + 0.05)):
				near_other = true
		if not near_other and SnowField.height_at(probe.x, probe.y) != 0.0:
			outside_zero = false
		for k in 40:
			var p := c + Vector2((k % 8 - 3.5) / 8.0 * size.x, (k / 8 - 2.0) / 5.0 * size.y)
			top = maxf(top, SnowField.height_at(p.x, p.y))
	print("INFO: SnowField %d boxes, highest snow %.2f m" % [boxes.size(), top])
	check(inside_snow, "snow at every box center is above half its height")
	check(outside_zero, "no snow beyond box + %.1f m" % SnowField.MARGIN)
	check(top < Layout.ROOF_HEIGHT, "banks stay below the roof rule height (%.2f < %.1f m)" % [top, Layout.ROOF_HEIGHT])
	check(SnowField.height_at(0, 32) == 0.0 and SnowField.normal_at(0, 32).is_equal_approx(Vector3.UP), "street A axis has no snow, flat normal")
	var a := SnowField.height_at(3.3, 24.6)
	check(a == SnowField.height_at(3.3, 24.6), "height_at is deterministic")
	var n := SnowField.normal_at(3.0, 24.9)
	check(n.z > 0.2, "bank normal leans away from the ridge (%s)" % n)

func _in_rect(p: Vector2, c: Vector2, half: Vector2) -> bool:
	return absf(p.x - c.x) <= half.x and absf(p.y - c.y) <= half.y

func _check_layers() -> void:
	var banks := 0
	var wrong := []
	for node in world.get_node("LevelGeometry").get_children():
		var n := String(node.name)
		if node is StaticBody3D and (n.begins_with("SnowBank") or n.begins_with("Snow_")):
			banks += 1
			if (node as StaticBody3D).collision_layer != 64:
				wrong.append(n)
	check(banks > 20 and wrong.is_empty(), "snow boxes on layer 7 SnowBank (%d boxes, wrong %s)" % [banks, wrong.slice(0, 3)])
	check(car.collision_mask & 64 == 0, "Lada does not collide with SnowBank")
	check(world.player.collision_mask & 64 != 0, "Ilyusha collides with SnowBank")
	check(DetectionSensor.WORLD_MASK & 64 != 0, "stealth rays are blocked by banks as before")
	check(ProjectSettings.get_setting("layer_names/3d_physics/layer_7") == "SnowBank", "layer 7 named SnowBank")

## Жители идут по своим путям и в коробки валов не заходят (их тела не двигаются физикой — путь задан точками).
func _check_residents() -> void:
	var root_node := world.get_node_or_null("LevelGeometry/Residents")
	if root_node == null:
		check(false, "residents present")
		return
	var inside := []
	var samples := 0
	for f in 900:
		await physics_frame
		if f % 6 != 0:
			continue
		for r in root_node.residents:
			var p: Vector3 = r.global_position
			samples += 1
			for b in SnowField.boxes():
				if _in_rect(Vector2(p.x, p.z), b[0], b[1] * 0.5 - Vector2.ONE * 0.05) and inside.size() < 5:
					inside.append("(%.1f,%.1f)" % [p.x, p.z])
	check(samples > 100 and inside.is_empty(), "residents never walk into a snow bank in 15 s (%d samples, inside %s)" % [samples, inside])

## Свободное место на северном валу улицы A: x ± 6 м внутри одного куска вала, в полосе x ± 4 м, z 21…31 нет других
## коробок (фонари, опоры, павильон, разрушаемые) — проезд наискось и вдоль вала ни во что не упирается.
func _pick_bank_a() -> void:
	var extra: Array = (Layout as Script).get_script_constant_map().get("BREAKABLES", [])
	for b in Layout.snow_banks():
		var c: Vector2 = b[0]
		if absf(c.y - 24.4) > 0.1 or cross_x != 0.0:
			continue
		var half: float = b[1].x * 0.5
		for x10 in range(int((c.x - half + 6.5) * 10.0), int((c.x + half - 6.5) * 10.0), 5):
			var x := x10 / 10.0
			var clear := true
			for spec in Layout.all_solids() + extra:
				if spec[1] == "snow_bank":
					continue
				var p: Vector2 = spec[2]
				var s: Vector3 = spec[3]
				var r := maxf(s.x, s.z) * 0.5
				if p.x + r > x - 4.0 and p.x - r < x + 4.0 and p.y + r > 21.0 and p.y - r < 31.0:
					clear = false
					break
			if clear:
				cross_x = x
				bank_a = b
				break
	print("INFO: bank A %s, crossing at x = %.1f" % [bank_a, cross_x])
	check(cross_x != 0.0, "found a clear stretch of bank A")

# --- пешеходы: вал — стена ---

func _check_walker() -> void:
	var player := world.player
	player.place(Vector3(cross_x, 0, 27.0), 0.0)
	world.camera_rig.yaw = 0.0   # на север, в вал
	await _frames(2)
	Input.action_press(&"move_forward")
	await _frames(90)
	Input.action_release(&"move_forward")
	var z := player.global_position.z
	check(z > 25.0 + 0.2 and player.global_position.y < 0.3, "Ilyusha stops at bank A, does not walk into it (z %.2f, y %.2f)" % [z, player.global_position.y])

# --- «Лада» на валу ---

func _check_cross_fast() -> void:
	var yaw := 0.3   # наискось на север-северо-запад: колёса въезжают по очереди — крен
	car.reset_to(Vector3(cross_x + 1.0, 0, 27.8), yaw)
	await _frames(2)
	car.velocity = -car.global_basis.z * 8.0   # накатом с 8 м/с, без газа
	var entry := -1.0
	var low := INF
	var lift_top := 0.0
	var roll_top := 0.0
	var pitch_top := 0.0
	var worst := 0.0
	var air := false
	var dust := false
	var snow_sound := 0
	var tracks_before: int = car.fx.snow_tracks.count
	var crossed_at := -1
	for f in 150:
		await physics_frame
		var speed := Vector2(car.velocity.x, car.velocity.z).length()
		if car.snow_lift > 0.05 and entry < 0.0:
			entry = speed
		if entry >= 0.0 and crossed_at < 0:
			low = minf(low, speed)
		lift_top = maxf(lift_top, car.snow_lift)
		roll_top = maxf(roll_top, absf(car.snow_roll))
		pitch_top = maxf(pitch_top, absf(car.snow_pitch))
		if not car.airborne:
			worst = maxf(worst, absf(car.visual.position.y - car.heave - car.snow_ride_target()))
		air = air or car.airborne
		for e in car.fx.dust:
			dust = dust or e.emitting
		if crossed_at < 0 and car.global_position.z < 24.4 - 3.5:
			crossed_at = f
		if crossed_at >= 0 and f > crossed_at + 20:
			break
	var sd = world.get_node_or_null("SoundDirector")
	if sd:
		snow_sound = sd.played.get("snow_drive", 0)
	print("INFO: cross bank A at 8 m/s — entry %.1f m/s, lowest %.1f, lift %.2f m, roll %.3f, pitch %.3f rad, worst gap %.3f m, airborne %s, landings %d, max air %.2f m" % [
		entry, low, lift_top, roll_top, pitch_top, worst, air, car.landings, car.max_air])
	check(entry > 7.0 and lift_top > 0.5, "Lada climbs bank A from 8 m/s (lift %.2f m)" % lift_top)
	check(worst <= 0.1, "body height follows SnowField ride height within 0.1 m on the snow (%.3f m)" % worst)
	check(roll_top > 0.05 and pitch_top > 0.15, "body rolls and pitches over the wheels (roll %.3f, pitch %.3f rad)" % [roll_top, pitch_top])
	check(low < entry - 0.8, "speed drops in the snow (%.1f → %.1f m/s)" % [entry, low])
	check(crossed_at >= 0, "Lada crosses the bank and drives off the far side (z %.1f)" % car.global_position.z)
	check(air and car.max_air > 0.05, "Lada hops when the snow drops away (max %.2f m)" % car.max_air)
	check(car.snow_lift < 0.01 and absf(car.snow_pitch) < 0.05, "back on the ground after the bank (lift %.3f)" % car.snow_lift)
	check(dust, "snow dust flies from the wheels on the bank")
	check(car.fx.snow_tracks.count > tracks_before + 4, "wheel tracks left on the bank (%d)" % (car.fx.snow_tracks.count - tracks_before))
	check(snow_sound > 0, "snow crunch loop plays in the snow")
	await _brake()

func _check_slow_spin() -> void:
	# Нос на север, передние колёса — у кромки профиля (вал до z 25, снег до 25,6).
	car.reset_to(Vector3(cross_x, 0, 25.0 + SnowField.MARGIN + Lada.WHEEL_AXLE + 0.05), 0.0)
	await _frames(2)
	car.velocity = -car.global_basis.z * 1.0
	Input.action_press(&"move_forward")
	var spun := 0
	var lift_top := 0.0
	var dust := false
	var stall := INF
	for f in 180:
		await physics_frame
		if car.spinning:
			spun += 1
			stall = minf(stall, Vector2(car.velocity.x, car.velocity.z).length())
		lift_top = maxf(lift_top, car.snow_lift)
		for e in car.fx.dust:
			dust = dust or (car.spinning and e.emitting)
	var z := car.global_position.z
	var speed := Vector2(car.velocity.x, car.velocity.z).length()
	Input.action_release(&"move_forward")
	print("INFO: 1 m/s into the bank, 3 s of throttle — spinning %d frames, slowest %.2f m/s while spinning, lift %.2f m, z %.2f, speed %.2f m/s" % [spun, stall, lift_top, z, speed])
	check(spun >= 10, "from 1 m/s on the steep bank face the Lada spins (%d frames)" % spun)
	check(stall < 0.6, "speed drops while spinning before the wheels dig in (%.2f of 1 m/s)" % stall)
	check(dust, "wheels throw snow while spinning")
	var start := car.global_position
	Input.action_press(&"move_back")
	await _frames(120)
	Input.action_release(&"move_back")
	check(car.global_position.distance_to(start) > 1.5, "Lada backs off the bank face without getting stuck (%.1f m)" % car.global_position.distance_to(start))
	await _brake()
	# Карман между валом и стеной (STUCK, H2_West у южного вала A): носом в стену, задом к валу — выезд назад через вал.
	start = Vector3(-92.8, 0, 42.1)
	car.reset_to(start, PI)
	await _frames(2)
	Input.action_press(&"move_back")
	await _frames(90)
	Input.action_release(&"move_back")
	var out := Vector2(car.global_position.x - start.x, car.global_position.z - start.z).length()
	check(out >= 1.5, "from the pocket between bank A and the H2 wall the Lada digs out backwards (%.1f m in 1.5 s)" % out)
	await _brake()

## Левые колёса по гребню вала, правые по дороге: крен, глубина, сопротивление, камера поднимается.
func _check_along_bank() -> void:
	var clean := await _run_east(Vector3(cross_x - 5.0, 0, 32.0))
	await _brake()
	var start := Vector3(cross_x - 5.0, 0, 24.4 + Lada.WHEEL_TRACK)
	car.reset_to(start, -PI * 0.5)
	await _frames(2)
	car.velocity = -car.global_basis.z * 6.0
	Input.action_press(&"move_forward")
	var roll := 0.0
	var depth := 0.0
	var lift := 0.0
	var cam := 0.0
	var worst := 0.0
	for f in 60:
		await physics_frame
		if f > 20:
			roll = maxf(roll, absf(car.snow_roll))
			depth = maxf(depth, car.snow_depth)
			lift = maxf(lift, car.snow_lift)
			cam = maxf(cam, world.camera_rig.camera.v_offset)
			if not car.airborne:
				worst = maxf(worst, absf(car.visual.position.y - car.heave - car.snow_ride_target()))
	var speed := Vector2(car.velocity.x, car.velocity.z).length()
	Input.action_release(&"move_forward")
	print("INFO: along bank A with the left wheels on the ridge — roll %.3f rad, depth %.2f m, lift %.2f m, camera +%.2f m, speed %.1f vs %.1f m/s on the road" % [
		roll, depth, lift, cam, speed, clean])
	check(roll > 0.1, "body rolls with one side on the bank (%.3f rad)" % roll)
	check(depth > 0.05 and speed < clean - 1.0, "deep snow slows the Lada (%.1f vs %.1f m/s)" % [speed, clean])
	check(worst <= 0.1, "body height follows SnowField along the bank within 0.1 m (%.3f)" % worst)
	check(cam > lift * 0.5, "camera rises with the car on the snow (+%.2f m)" % cam)
	await _brake()

func _run_east(from: Vector3) -> float:
	car.reset_to(from, -PI * 0.5)
	await _frames(2)
	car.velocity = -car.global_basis.z * 6.0
	Input.action_press(&"move_forward")
	await _frames(60)
	Input.action_release(&"move_forward")
	return Vector2(car.velocity.x, car.velocity.z).length()

## Стоим поперёк вала: выход — не внутрь коробки вала, лучи датчиков целят в поднятый кузов.
func _check_exit_on_bank() -> void:
	car.reset_to(Vector3(cross_x, 0, 24.4), 0.0)
	await _frames(10)
	var targets := DetectionSensor.car_targets(car)
	check(targets[0].y > DetectionSensor.CAR_TARGET_HEIGHT + 0.3, "stealth aims at the lifted body on a bank (y %.2f)" % targets[0].y)
	var exited := world.exit_car()
	await _frames(10)
	var p := world.player.global_position
	var inside := false
	for b in SnowField.boxes():
		inside = inside or _in_rect(Vector2(p.x, p.z), b[0], b[1] * 0.5)
	check(exited and world.control_mode == &"on_foot" and not inside, "exit from a car on a bank lands outside the bank box (%s)" % p)
	world.enter_car()
	await _frames(3)

# --- «вкус» аркады: перенос веса, занос, отскок ---

func _check_weight_transfer() -> void:
	car.reset_to(Vector3(-60, 0, 32), -PI * 0.5)   # на восток по улице A
	await _frames(3)
	Input.action_press(&"move_forward")
	var squat := 0.0
	for f in 90:
		await physics_frame
		squat = maxf(squat, car.susp_pitch)
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")
	var dive := 0.0
	for f in 40:
		await physics_frame
		dive = minf(dive, car.susp_pitch)
	Input.action_release(&"move_back")
	await _brake()
	car.reset_to(Vector3(-60, 0, 32), -PI * 0.5)
	await _frames(2)
	car.velocity = -car.global_basis.z * 14.0
	Input.action_press(&"move_forward")
	Input.action_press(&"move_left")
	var roll := 0.0
	for f in 40:
		await physics_frame
		roll = minf(roll, car.susp_roll)
	_release_all()
	print("INFO: weight transfer — squat %.3f rad on throttle, dive %.3f on brake, roll %.3f in a left turn" % [squat, dive, roll])
	check(squat > 0.01, "rear squats on throttle (nose up %.3f rad)" % squat)
	check(dive < -0.03, "nose dives on braking (%.3f rad)" % dive)
	check(roll < -0.02, "body rolls outward in a left turn (%.3f rad)" % roll)
	check(absf(car.global_basis.y.dot(Vector3.UP) - 1.0) < 0.0001, "only Visual tilts, the body stays upright")
	await _brake()

func _check_skid() -> void:
	car.reset_to(Vector3(-60, 0, 32), -PI * 0.5)
	await _frames(2)
	car.velocity = -car.global_basis.z * 16.0
	var marks: int = car.fx.skid_tracks.count
	Input.action_press(&"handbrake")
	Input.action_press(&"move_left")
	var skid := false
	var smoke := false
	for f in 45:
		await physics_frame
		skid = skid or car.skidding
		smoke = smoke or car.fx.smoke[0].emitting
	_release_all()
	var sd = world.get_node_or_null("SoundDirector")
	var squeak: int = sd.played.get("skid_squeak", 0) if sd else 0
	check(skid and smoke, "handbrake slide smokes from the rear wheels")
	check(car.fx.skid_tracks.count > marks + 4, "skid marks on the road (%d)" % (car.fx.skid_tracks.count - marks))
	check(squeak > 0, "tyre squeak plays in the slide")
	await _brake()
	check(not car.fx.smoke[0].emitting, "no smoke once stopped")

func _check_bounce() -> void:
	var wall := StaticBody3D.new()
	wall.name = "ParkedCar_drive02"
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 1.4, 4.1)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(-40, 0.7, 32)
	world.add_child(wall)
	car.reset_to(Vector3(-52, 0, 32), -PI * 0.5)
	await _frames(2)
	car.velocity = -car.global_basis.z * 9.0
	var hits := car.impacts
	var back := 0.0
	var shake := 0.0
	Input.action_press(&"move_forward")
	for f in 90:
		await physics_frame
		back = minf(back, Vector3(car.velocity.x, 0, car.velocity.z).dot(-car.global_basis.z))
		shake = maxf(shake, car.shake_left())
	Input.action_release(&"move_forward")
	print("INFO: bounce off a parked car at 9 m/s — impacts %d, rebound %.1f m/s, shake %.2f s" % [car.impacts - hits, back, shake])
	check(car.impacts > hits and back < -1.0, "Lada bounces back off a parked car (%.1f m/s)" % back)
	check(shake > 0.1, "camera shakes on the impact")
	wall.queue_free()
	await _brake()
	# Стена дома — без отскока (PLAY-02: упор, не мяч).
	car.reset_to(Vector3(-51, 0, 63), 0.0)
	await _frames(2)
	car.velocity = -car.global_basis.z * 6.0
	hits = car.impacts
	Input.action_press(&"move_forward")
	await _frames(60)
	Input.action_release(&"move_forward")
	check(car.impacts == hits, "a house wall stops the Lada without a bounce")
	await _brake()

# --- помощники ---

func _brake() -> void:
	_release_all()
	for f in 150:
		if car.speed_kmh() < 1.0 and not car.airborne:
			break
		Input.action_press(&"handbrake")
		await physics_frame
	_release_all()
	await _frames(3)

func _release_all() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"handbrake", &"interact"]:
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
	print("DRIVE02: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	for i in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)
