extends SceneTree
## DRIVE-02: кадры «Лады» на сугробах и «вкуса» аркады. Вывод — первый пользовательский аргумент (после --).
const Layout = preload("res://game/world/layout.gd")
var main
var world
var car
var side: Camera3D
var out := ""
var x0 := -84.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "/Users/a.iuskasov/Workspace/shkya/builds/screenshots/DRIVE-02/"
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await physics_frame
	main.start_game()
	for i in 20: await physics_frame
	world = main.world
	car = world.car
	var traffic = world.get_node_or_null("LevelGeometry/Traffic")
	if traffic:
		traffic.free()
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false
	x0 = _clear_x()
	side = Camera3D.new()
	side.fov = 55.0
	root.add_child(side)
	world.enter_car()
	for i in 3: await physics_frame
	# 1. Вдоль вала: левые колёса на гребне — крен.
	car.reset_to(Vector3(x0 - 5.0, 0, 24.4 + 0.69), -PI * 0.5)
	world.camera_rig.snap()
	await _frames(2)
	car.velocity = -car.global_basis.z * 5.0
	Input.action_press(&"move_forward")
	await _frames(28)
	await _shot("01_bank_roll_chase", null)
	await _shot("02_bank_roll_front", [car.global_position + Vector3(7.5, 1.2, 1.5), car.global_position + Vector3(0, 0.6, 0)])
	Input.action_release(&"move_forward")
	await _brake()
	# 2. Въезд на вал наискось и съезд с пылью.
	car.reset_to(Vector3(x0 + 1.0, 0, 28.6), 0.3)
	world.camera_rig.yaw = 0.3
	world.camera_rig.snap()
	await _frames(2)
	car.velocity = -car.global_basis.z * 8.0
	var entry_done := false
	var down_done := false
	for f in 120:
		await physics_frame
		if not entry_done and car.snow_pitch > 0.18:
			entry_done = true
			await _shot("03_entry_chase", null)
			await _shot("04_entry_side", [car.global_position + Vector3(-7.0, 1.0, 0.5), car.global_position + Vector3(0, 0.7, 0)])
		if entry_done and not down_done and car.global_position.z < 23.0 and (car.airborne or car.snow_pitch < -0.1):
			down_done = true
			await _shot("05_descent_dust_side", [car.global_position + Vector3(-6.5, 1.0, -1.0), car.global_position + Vector3(0, 0.6, 0)])
			await _shot("06_descent_dust_chase", null)
		if down_done and car.global_position.z < 18.0:
			break
	await _brake()
	await _frames(20)
	await _shot("07_tracks_on_bank", [Vector3(x0 + 1.0, 4.5, 30.0), Vector3(x0 - 0.5, 0.3, 24.4)])
	# 3. Буксует у вала с 1 м/с.
	car.reset_to(Vector3(x0 + 4.0, 0, 25.0 + 0.6 + 1.21 + 0.05), 0.0)
	world.camera_rig.yaw = 0.0
	world.camera_rig.snap()
	await _frames(2)
	car.velocity = -car.global_basis.z * 1.0
	Input.action_press(&"move_forward")
	await _frames(70)
	await _shot("08_spinning_chase", null)
	Input.action_release(&"move_forward")
	await _brake()
	# 4. Перенос веса: торможение, поворот; занос с дымом и следами.
	car.reset_to(Vector3(-60, 0, 32), -PI * 0.5)
	world.camera_rig.yaw = -PI * 0.5
	world.camera_rig.snap()
	await _frames(2)
	car.velocity = -car.global_basis.z * 16.0
	Input.action_press(&"move_back")
	await _frames(9)
	await _shot("09_brake_dive_side", [car.global_position + Vector3(1.0, 1.0, -7.0), car.global_position + Vector3(0, 0.6, 0)])
	Input.action_release(&"move_back")
	await _brake()
	car.reset_to(Vector3(-60, 0, 32), -PI * 0.5)
	world.camera_rig.yaw = -PI * 0.5
	world.camera_rig.snap()
	await _frames(2)
	car.velocity = -car.global_basis.z * 15.0
	Input.action_press(&"move_forward")
	Input.action_press(&"move_left")
	await _frames(25)
	await _shot("10_turn_roll_chase", null)
	_release()
	await _brake()
	car.reset_to(Vector3(-60, 0, 32), -PI * 0.5)
	world.camera_rig.yaw = -PI * 0.5
	world.camera_rig.snap()
	await _frames(2)
	car.velocity = -car.global_basis.z * 17.0
	Input.action_press(&"handbrake")
	Input.action_press(&"move_left")
	await _frames(22)
	await _shot("11_skid_smoke_chase", null)
	_release()
	await _brake()
	await _frames(30)
	await _shot("12_skid_marks", [car.global_position + Vector3(4.0, 5.0, 5.0), car.global_position + Vector3(-6.0, 0, 0)])
	main.queue_free()
	for i in 5: await process_frame
	quit(0)

func _clear_x() -> float:
	for b in Layout.snow_banks():
		var c: Vector2 = b[0]
		if absf(c.y - 24.4) > 0.1:
			continue
		var half: float = b[1].x * 0.5
		for x10 in range(int((c.x - half + 6.5) * 10.0), int((c.x + half - 6.5) * 10.0), 5):
			var x := x10 / 10.0
			var clear := true
			for spec in Layout.all_solids():
				if spec[1] == "snow_bank":
					continue
				var p: Vector2 = spec[2]
				var s: Vector3 = spec[3]
				var r := maxf(s.x, s.z) * 0.5
				if p.x + r > x - 4.0 and p.x - r < x + 4.0 and p.y + r > 21.0 and p.y - r < 31.0:
					clear = false
					break
			if clear:
				return x
	return 3.0

## view == null — игровая камера за машиной; иначе [откуда, куда] — боковая камера.
func _shot(name: String, view) -> void:
	if view == null:
		world.camera_rig.camera.make_current()
	else:
		side.global_position = view[0]
		side.look_at(view[1])
		side.make_current()
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("FRAME: ", name, " lift %.2f pitch %.3f roll %.3f susp %.3f/%.3f skid %s" % [car.snow_lift, car.snow_pitch, car.snow_roll, car.susp_pitch, car.susp_roll, car.skidding])
	world.camera_rig.camera.make_current()

func _brake() -> void:
	_release()
	for f in 150:
		if car.speed_kmh() < 1.0 and not car.airborne:
			break
		Input.action_press(&"handbrake")
		await physics_frame
	_release()
	await _frames(3)

func _release() -> void:
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"handbrake"]:
		Input.action_release(a)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
