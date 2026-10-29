extends SceneTree
## DRIVE-03, прототип D: сценарий raycast-«Лады» (не в Makefile). Тот же сценарий без флага меряет нынешнюю аркаду —
## для сравнения по замерам. Флаги после «--»: --raycar — прототип; --capture — окно: 30 с проезда (кадр каждые 0,5 с)
## и 6 кадров манёвров в builds/screenshots/DRIVE-03/; --fps — окно: частота кадров на 30 с настоящего проезда.

const Layout = preload("res://game/world/layout.gd")
const SHOTS := "res://builds/screenshots/DRIVE-03"

var raycar := false
var capture := false
var fps_mode := false
var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var tag := "arcade"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	raycar = "--raycar" in args
	capture = "--capture" in args
	fps_mode = "--fps" in args
	tag = "raycar" if raycar else "arcade"
	call_deferred("_run")

func _run() -> void:
	create_timer(1800.0, true, false, true).timeout.connect(func():
		push_error("FAIL: drive03 exceeded 1800 simulated seconds")
		quit(2)
	)
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	node_added.connect(_on_node_added)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.start_game()
	await _frames(10)
	await _pass(true)
	if not capture and not fps_mode:
		# Второй проход в том же процессе — другой режим (скрипт «Лады» меняется до её _ready), для сравнения.
		force_script = load("res://game/vehicles/lada.gd" if raycar else "res://game/vehicles/lada_raycast.gd")
		main.start_game()
		await _frames(10)
		await _pass(false)
	_finish()

## Сменить скрипт новой «Лады» до её _ready (второй проход сценария).
var force_script: Script
func _on_node_added(node: Node) -> void:
	if force_script and node.name == &"Car" and node.get_parent() is DemoWorld and not node.is_node_ready() \
			and node.get_script() != force_script:
		node.set_script(force_script)

func _pass(first: bool) -> void:
	world = main.world
	# Круг по кольцу — про подвеску, не про пробки: транспорт кольца убран (троллейбус на остановке B (67; −62) стоял
	# поперёк полосы и останавливал обе машины). Свой набор — TRAFFIC.
	var traffic := world.get_node_or_null("LevelGeometry/Traffic")
	if traffic:
		traffic.free()
	var script_path: String = world.car.get_script().resource_path
	tag = "raycar" if script_path.ends_with("lada_raycast.gd") else "arcade"
	print("INFO: pass %s, car script %s" % [tag, script_path])
	if first:
		check(script_path.ends_with("lada_raycast.gd") == raycar, "car script matches the --raycar flag (%s)" % script_path)
	if fps_mode:
		await _fps_run()   # одно окно на часть: сначала замер, затем кадры (--capture) и сценарий
		if not capture:
			return
	await _check_enter_and_rest()
	if capture:
		await _capture_run()
	await _check_accel()
	await _check_brake()
	await _check_turn_roll()
	await _check_drift()
	await _check_radius()
	await _check_jump()
	await _check_bank()
	if not capture:
		await _check_ring()
	await _check_exit()

# --- вход, покой ---

func _check_enter_and_rest() -> void:
	var car := world.car
	var entered := [false]
	car.driver_entered.connect(func(_d): entered[0] = true)
	await _frames(60)
	print("INFO: [%s] at rest: wheels on ground %s, y %.3f, on floor %s" % [tag, car.get("wheels_on_ground"), car.global_position.y, car.is_on_floor()])
	check(car.global_position.distance_to(Layout.CAR_SPAWN) < 0.2, "car parked at CAR_SPAWN (%s)" % car.global_position)
	check(car.global_basis.y.dot(Vector3.UP) > 0.999, "parked car is level")
	check(car.is_on_floor() or car.global_position.y < 0.05, "parked car stands on the ground (y %.3f)" % car.global_position.y)
	world.player.place(car.global_position + Vector3(-2.2, 0, 0), 0.0)
	await _frames(4)
	check(world.get_hud_state()["prompt"] == "E — СЕСТЬ В МАШИНУ", "enter prompt next to the car")
	await _press(&"interact")
	check(world.control_mode == &"in_car" and entered[0], "E enters the car, driver_entered emitted")
	check(world.camera_rig.target == car and world.camera_rig.profile == &"in_car", "camera follows the car")
	await _press(&"interact")
	check(world.control_mode == &"on_foot", "E exits the car")
	await _ensure_in_car()

# --- разгон 0→100 ---

func _check_accel() -> void:
	var car := world.car
	await _place(Vector3(-90, 0, 32), -PI * 0.5)
	var marks := {36.0: -1.0, 72.0: -1.0, 100.0: -1.0}
	var squat := 0.0
	Input.action_press(&"move_forward")
	for frame in 600:
		await physics_frame
		var kmh := car.speed_kmh()
		squat = maxf(squat, _pitch())
		for mark in marks:
			if marks[mark] < 0.0 and kmh >= mark:
				marks[mark] = (frame + 1) / 60.0
		if marks[100.0] > 0.0:
			break
	Input.action_release(&"move_forward")
	print("INFO: [%s] accel 0→36 km/h %.2f s, 0→72 %.2f s, 0→100 %.2f s (−1 — not reached in 10 s); squat (nose up) %.1f°"
		% [tag, marks[36.0], marks[72.0], marks[100.0], squat])
	check(marks[100.0] > 0.0 and marks[100.0] <= 5.0, "0→100 km/h within 5 s (%.2f s)" % marks[100.0])
	await _frames(30)

# --- торможение 18→0 ---

func _check_brake() -> void:
	var car := world.car
	await _place(Vector3(-90, 0, 32), -PI * 0.5)
	Input.action_press(&"move_forward")
	for i in 600:
		if _speed() >= 18.0:
			break
		await physics_frame
	Input.action_release(&"move_forward")
	var start := car.global_position
	var dive := 0.0
	Input.action_press(&"move_back")
	var frames := 0
	while _speed() > 0.3 and frames < 300:
		await physics_frame
		frames += 1
		dive = minf(dive, _pitch())
		if frames == 12:
			await _shot("pitch_braking", 1.1)
	Input.action_release(&"move_back")
	var seconds := frames / 60.0
	print("INFO: [%s] brake 18→0 m/s %.2f s, %.1f m; nose dive %.1f°" % [tag, seconds, car.global_position.distance_to(start), dive])
	check(seconds <= 1.0, "18→0 m/s within 1 s (%.2f s)" % seconds)
	await _frames(60)
	print("INFO: [%s] after stop: pitch %.2f°, roll %.2f°" % [tag, _pitch(), _roll()])

# --- крен в повороте ---

func _check_turn_roll() -> void:
	await _place(Vector3(-90, 0, 32), -PI * 0.5)
	await _hold_speed(14.0, 200)
	var peak := 0.0
	Input.action_press(&"move_forward")
	Input.action_press(&"move_left")
	for i in 60:
		await physics_frame
		peak = maxf(peak, absf(_roll()))
		if i == 35:
			await _shot("roll_turn", 0.0)
	_release_all()
	print("INFO: [%s] body roll in a left turn at 14 m/s: peak %.1f°" % [tag, peak])
	await _frames(60)

# --- ручник: занос ---

func _check_drift() -> void:
	var car := world.car
	var results := []
	for hand in [false, true]:
		await _place(Vector3(-90, 0, 32), -PI * 0.5)
		await _hold_speed(14.0, 200)
		var yaw := car.global_rotation.y
		var peak := 0.0
		Input.action_press(&"move_left")
		if hand:
			Input.action_press(&"handbrake")
		for i in 45:
			await physics_frame
			peak = maxf(peak, car.lateral_speed)
			if hand and i == 30:
				await _shot("drift_handbrake", 0.0)
		var turned := rad_to_deg(absf(angle_difference(yaw, car.global_rotation.y)))
		_release_all()
		results.append([peak, turned])
		await _frames(60)
	print("INFO: [%s] lateral speed peak plain %.2f m/s (body %.0f°), handbrake %.2f m/s (body %.0f°)"
		% [tag, results[0][0], results[0][1], results[1][0], results[1][1]])
	check(results[1][0] > 2.0 and results[1][0] > results[0][0] * 1.5, "handbrake turn produces a drift")

# --- радиус поворота ---

func _check_radius() -> void:
	var slow := await _turn_radius(6.0)
	var fast := await _turn_radius(19.0)
	print("INFO: [%s] turn radius %.1f m at 6 m/s, %.1f m at 19 m/s" % [tag, slow, fast])
	check(fast > slow * 1.5, "turn radius grows with speed")

func _turn_radius(speed: float) -> float:
	var car := world.car
	await _place(Vector3(-60, 0, 32), -PI * 0.5)
	car.velocity = -car.global_basis.z * speed
	var yaw := car.global_rotation.y
	Input.action_press(&"move_left")
	var travelled := 0.0
	for i in 20:
		var before := car.global_position
		await physics_frame
		travelled += Vector2(before.x - car.global_position.x, before.z - car.global_position.z).length()
	_release_all()
	var turned := absf(angle_difference(yaw, car.global_rotation.y))
	await _frames(60)
	return travelled / maxf(turned, 0.0001)

# --- трамплин: прыжок и приземление ---

func _check_jump() -> void:
	var car := world.car
	var ramp := StaticBody3D.new()
	ramp.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 0.2, 4.0)
	shape.shape = box
	ramp.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	ramp.add_child(mesh)
	var angle := deg_to_rad(12.0)
	ramp.position = Vector3(10.0, 2.5 * sin(angle) - 0.1, 32.0)
	ramp.rotation.z = angle   # восточный край выше: въезд с запада
	world.add_child(ramp)
	await _place(Vector3(-40, 0, 32), -PI * 0.5)
	var air_frames := 0
	var max_y := 0.0
	var max_tilt := 0.0
	var landed_at := -1
	var was_air := false
	var shot_air := false
	for frame in 420:
		var x := car.global_position.x
		var wanted := 15.0 if x < 6.0 else 0.0
		Input.action_release(&"move_forward")
		if wanted > 0.0 and _speed() < wanted:
			Input.action_press(&"move_forward")
		await physics_frame
		var air := _airborne()
		if air and car.global_position.x > 8.0:
			air_frames += 1
			was_air = true
			if not shot_air and car.global_position.y > 0.9:
				shot_air = true
				await _shot("jump_air", 1.1)
		elif was_air and landed_at < 0:
			landed_at = frame
		if landed_at >= 0 and frame == landed_at + 4:
			await _shot("jump_landing", 1.1)
		max_y = maxf(max_y, car.global_position.y)
		max_tilt = maxf(max_tilt, _tilt())
		if landed_at >= 0 and frame > landed_at + 120:
			break
	_release_all()
	var upright := _up_dot()
	print("INFO: [%s] ramp 12° at 15 m/s: airborne %.2f s, peak y %.2f m, max body tilt %.1f°, upright after landing %.4f"
		% [tag, air_frames / 60.0, max_y, max_tilt, upright])
	check(air_frames > 6, "the ramp throws the car into the air (%.2f s)" % (air_frames / 60.0))
	check(max_tilt < 36.0 and upright > 0.98, "lands on its wheels without flipping (tilt %.1f°, up·Y %.3f)" % [max_tilt, upright])
	ramp.queue_free()
	await _frames(30)

# --- вал улицы A ---

func _check_bank() -> void:
	var car := world.car
	var snow_field := ResourceLoader.exists("res://game/world/snow_field.gd")
	await _place(Vector3(5, 0, 32), 0.0)   # на север: вал z = 24,4 (кусок x −10…16), за ним тротуар
	var max_y := 0.0
	var max_tilt := 0.0
	var shot := false
	for frame in 420:
		Input.action_release(&"move_forward")
		if _speed() < 8.0:
			Input.action_press(&"move_forward")
		await physics_frame
		max_y = maxf(max_y, car.global_position.y)
		max_tilt = maxf(max_tilt, _tilt())
		if not shot and car.global_position.z < 25.5:
			shot = true
			await _shot("on_bank", 1.0)
		if car.global_position.z < 19.0:
			break
	_release_all()
	var crossed := car.global_position.z < 21.0
	print("INFO: [%s] street A bank at 8 m/s: crossed %s (z %.1f), peak y %.2f m, max tilt %.1f°, SnowField %s"
		% [tag, crossed, car.global_position.z, max_y, max_tilt, "present" if snow_field else "absent — bank is a 0.9 m World box"])
	if snow_field:
		check(crossed, "car crosses the street A bank over SnowField")
	await _frames(30)

# --- круг по кольцу ---

func _check_ring() -> void:
	var car := world.car
	var lane := Layout.ring_lane(6.0, 6, true)
	var start := lane[0]
	var heading := lane[1] - lane[0]
	await _place(start, atan2(-heading.x, -heading.z))
	var t0 := Engine.get_physics_frames()
	var cpu := [0.0, 0]
	var probe := func() -> void:
		cpu[0] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		cpu[1] += 1
	physics_frame.connect(probe)
	var ok := true
	var peak_roll := 0.0
	# Прямые между дугами — точками через 10 м: водитель держит полосу, а не срезает к дальней точке (иначе цеплял
	# бортом «Жигули» у западного бордюра D (−65,9; −70) — в обоих режимах одинаково, первый прогон).
	var points: Array[Vector3] = []
	var closed := lane.duplicate()
	closed.append(lane[0])
	for i in range(1, closed.size()):
		var a: Vector3 = closed[i - 1]
		var b: Vector3 = closed[i]
		var steps := int(a.distance_to(b) / 10.0)
		for k in range(1, steps):
			points.append(a.lerp(b, float(k) / steps))
		points.append(b)
	for i in points.size():
		var next := points[i + 1] if i + 1 < points.size() else Vector3.INF
		var result: Dictionary = await _drive_to(points[i], i == points.size() - 1, next)
		peak_roll = maxf(peak_roll, result["roll"])
		if not result["ok"]:
			ok = false
			check(false, "ring lap reaches point %d %s (stuck at %s)" % [i, points[i], car.global_position])
			break
	_release_all()
	physics_frame.disconnect(probe)
	var seconds := (Engine.get_physics_frames() - t0) / 60.0
	print("INFO: [%s] ring lap %.1f s, peak body roll %.1f°, physics step (whole world) avg %.3f ms" % [tag, seconds, peak_roll,
		cpu[0] / maxf(cpu[1], 1) * 1000.0])
	check(ok, "full ring lap without getting stuck (%.1f s)" % seconds)
	await _frames(60)

func _drive_to(target: Vector3, final: bool, next: Vector3 = Vector3.INF) -> Dictionary:
	var car := world.car
	var corner := 0.0
	if next != Vector3.INF:
		var incoming := target - car.global_position
		incoming.y = 0.0
		corner = absf(incoming.normalized().signed_angle_to((next - target).normalized(), Vector3.UP))
	var best := INF
	var stalled := 0
	var roll := 0.0
	while true:
		var delta := target - car.global_position
		delta.y = 0.0
		var distance := delta.length()
		if distance < (3.0 if final else (8.0 if corner > 0.6 else 5.0)):
			return {"ok": true, "roll": roll}
		var forward := -car.global_basis.z
		forward.y = 0.0
		var error := forward.normalized().signed_angle_to(delta.normalized(), Vector3.UP)
		_steer(clampf(error * 2.5, -1.0, 1.0))
		var speed := _speed()
		var wanted := 20.0 if absf(error) < 0.25 else 8.0
		if corner > 0.6 and distance < 30.0:
			wanted = minf(wanted, 7.0)
		if final:
			wanted = minf(wanted, distance * 0.8 + 2.0)
		Input.action_release(&"move_forward")
		Input.action_release(&"move_back")
		if speed < wanted:
			Input.action_press(&"move_forward")
		elif speed > wanted + 2.0:
			Input.action_press(&"move_back")
		await physics_frame
		roll = maxf(roll, absf(_roll()))
		if distance < best - 0.05:
			best = distance
			stalled = 0
		else:
			stalled += 1
			if stalled > 240:
				_release_all()
				return {"ok": false, "roll": roll}
	return {"ok": false, "roll": roll}

func _steer(value: float) -> void:
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	if value > 0.02:
		Input.action_press(&"move_left", value)
	elif value < -0.02:
		Input.action_press(&"move_right", -value)

# --- выход, пустая машина стоит ---

func _check_exit() -> void:
	var car := world.car
	await _place(Vector3(0, 0, 32), -PI * 0.5)
	await _press(&"interact")
	await _frames(3)
	check(world.control_mode == &"on_foot" and world.player.visible, "E exits a stopped car")
	await _frames(120)
	check(car.speed_kmh() < 0.5 and _up_dot() > 0.999, "empty car stays still and level (%.2f km/h)" % car.speed_kmh())

# --- окно: 30 с проезда с кадрами, частота кадров ---

func _capture_run() -> void:
	var car := world.car
	await _place(Layout.ROUTE_DRIVE[0], Layout.CAR_SPAWN_YAW)
	var t0 := Engine.get_physics_frames()
	var shot_index := [0]
	var tick := func() -> void:
		var f := Engine.get_physics_frames() - t0
		if f % 30 == 0 and shot_index[0] < 60:
			shot_index[0] += 1
	var route := Layout.ROUTE_DRIVE
	for i in range(1, route.size()):
		var last := i == route.size() - 1
		var target := route[i]
		var next := Vector3.INF if last else route[i + 1]
		var corner := 0.0
		if next != Vector3.INF:
			var incoming := target - car.global_position
			incoming.y = 0.0
			corner = absf(incoming.normalized().signed_angle_to((next - target).normalized(), Vector3.UP))
		var stalled := 0
		var best := INF
		while Engine.get_physics_frames() - t0 < 1800:
			var delta := target - car.global_position
			delta.y = 0.0
			var distance := delta.length()
			if distance < (3.0 if last else (8.0 if corner > 0.6 else 5.0)):
				break
			var forward := -car.global_basis.z
			forward.y = 0.0
			var error := forward.normalized().signed_angle_to(delta.normalized(), Vector3.UP)
			_steer(clampf(error * 2.5, -1.0, 1.0))
			var wanted := 20.0 if absf(error) < 0.25 else 8.0
			if corner > 0.6 and distance < 30.0:
				wanted = minf(wanted, 7.0)
			if last:
				wanted = minf(wanted, distance * 0.8 + 2.0)
			Input.action_release(&"move_forward")
			Input.action_release(&"move_back")
			if _speed() < wanted:
				Input.action_press(&"move_forward")
			elif _speed() > wanted + 2.0:
				Input.action_press(&"move_back")
			await physics_frame
			var f := Engine.get_physics_frames() - t0
			if f % 30 == 0:
				shot_index[0] += 1
				await _shot("run_%02d" % shot_index[0], 0.0, false)
			if distance < best - 0.05:
				best = distance
				stalled = 0
			else:
				stalled += 1
				if stalled > 240:
					break
	_release_all()
	print("INFO: [%s] capture run: %d frames saved, %.1f s" % [tag, shot_index[0], (Engine.get_physics_frames() - t0) / 60.0])
	await _frames(30)

func _fps_run() -> void:
	await _ensure_in_car()
	var car := world.car
	await _place(Layout.ROUTE_DRIVE[0], Layout.CAR_SPAWN_YAW)
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	var route := Layout.ROUTE_DRIVE
	var segment := 1
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 30000:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1_000_000.0)
		last = now
		if segment >= route.size():
			_release_all()
			continue
		var delta := route[segment] - car.global_position
		delta.y = 0.0
		if delta.length() < 6.0:
			segment += 1
			continue
		var forward := -car.global_basis.z
		forward.y = 0.0
		var error := forward.normalized().signed_angle_to(delta.normalized(), Vector3.UP)
		_steer(clampf(error * 2.5, -1.0, 1.0))
		Input.action_release(&"move_forward")
		Input.action_release(&"move_back")
		var wanted := 16.0 if absf(error) < 0.25 else 7.0
		if _speed() < wanted:
			Input.action_press(&"move_forward")
		elif _speed() > wanted + 2.0:
			Input.action_press(&"move_back")
	_release_all()
	times = times.slice(90)
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	var worst := times.slice(int(times.size() * 0.99))
	var worst_total := 0.0
	for t in worst:
		worst_total += t
	print("FPS: [%s] average %.1f, median %.1f, 1%% low %.1f, frames %d, reached route point %d/%d" % [tag,
		times.size() / total, 1.0 / times[times.size() / 2], worst.size() / worst_total, times.size(), segment, route.size()])

# --- служебное ---

func _place(point: Vector3, yaw: float) -> void:
	_release_all()
	await _ensure_in_car()
	world.car.reset_to(point, yaw)
	await _frames(30)

func _hold_speed(speed: float, limit: int) -> void:
	Input.action_press(&"move_forward")
	for i in limit:
		if _speed() >= speed:
			break
		await physics_frame
	Input.action_release(&"move_forward")

func _speed() -> float:
	return Vector2(world.car.velocity.x, world.car.velocity.z).length()

## Наклон, который видит игрок, — по узлу кузова облика (у аркады это «видимая подвеска» Motion, у прототипа — тело).
func _body() -> Node3D:
	return world.car.visual.get_node("Body") as Node3D

func _roll() -> float:
	return rad_to_deg(asin(clampf(-_body().global_basis.x.normalized().y, -1.0, 1.0)))

func _pitch() -> float:
	return rad_to_deg(asin(clampf(-_body().global_basis.z.normalized().y, -1.0, 1.0)))

func _up_dot() -> float:
	return _body().global_basis.y.normalized().dot(Vector3.UP)

func _tilt() -> float:
	return rad_to_deg(acos(clampf(_up_dot(), -1.0, 1.0)))

func _airborne() -> bool:
	if tag == "raycar":
		return world.car.get("wheels_on_ground") == 0
	return not world.car.is_on_floor()

## Кадр в окне (--capture): камера на миг сбоку на side рад от курса машины (0 — обычная камера преследования).
func _shot(name: String, side: float, log := true) -> void:
	if not capture:
		return
	if side != 0.0:
		world.camera_rig.yaw = world.car.global_rotation.y + side
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("%s/%s_%s.png" % [SHOTS, tag, name])
	root.get_viewport().get_texture().get_image().save_png(path)
	if log:
		print("INFO: shot %s (roll %.1f°, pitch %.1f°, y %.2f m)" % [path, _roll(), _pitch(), world.car.global_position.y])

func _ensure_in_car() -> void:
	await _frames(2)
	if world.control_mode == &"on_foot":
		world.enter_car()
	await _frames(2)

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
	if tag == "arcade" and not label.begins_with("car script"):
		print("CMP [arcade] %s: %s" % ["yes" if condition else "no", label])   # сравнение, не приёмка аркады
		return
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	print("DRIVE03: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
