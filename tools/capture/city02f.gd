extends SceneTree
## CITY-02 F: кадры «до | после» с точек независимой сверки (review_city02.gd) и замер FPS как tools/fps_probe.gd —
## в одном окне (запуск в фоне через `open -g`). Аргументы после --: каталог кадров, режим ("all" | "frames" | "fps"
## | "probe"), файл итога FPS.
const Layout = preload("res://game/world/layout.gd")
const SPEED := 14.0
const WARMUP_FRAMES := 90

var main
var world
var cam: Camera3D
var out := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://builds/screenshots/CITY-02/f/after/")
	var mode: String = args[1] if args.size() > 1 else "all"
	var fps_file: String = args[2] if args.size() > 2 else ProjectSettings.globalize_path("res://builds/checks/CITY-02/f/fps.txt")
	if mode == "probe":
		await _probe()
		quit(0)
		return
	if mode == "all" or mode == "frames":
		await _frames()
	if mode == "all" or mode == "fps":
		var lines := []
		lines.append("FPS1: " + await _fps())
		lines.append("FPS2: " + await _fps())
		DirAccess.make_dir_recursive_absolute(fps_file.get_base_dir())
		var f := FileAccess.open(fps_file, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("\n".join(lines))
	quit(0)

func _start() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await physics_frame
	main.start_game()
	for i in 40: await physics_frame
	world = main.world

func _frames() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	await _start()
	world.camera_rig.snap()
	for i in 20: await physics_frame
	await _save("g01_spawn_gamecam")
	world.player.global_position = Vector3(64, 0, -60)
	world.camera_rig.yaw = atan2(64 - 58.0, -60 + 77.0)
	world.camera_rig.snap()
	for i in 30: await physics_frame
	await _save("g02_kiosk_gamecam")
	world.player.global_position = Vector3(62, 0, 36)
	world.camera_rig.yaw = PI * 0.5
	world.camera_rig.snap()
	for i in 30: await physics_frame
	await _save("g03_a_x_b_gamecam")
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	var car_p: Vector3 = world.car.global_position
	var shots := [
		["01_yard", Vector3(-30, 2.0, 96), Vector3(-60, 2.5, 80)],
		["02_a_x_b", Vector3(60, 2.2, 44), Vector3(80, 5, 10)],
		["03_kiosk_stop", Vector3(67, 1.8, -52), Vector3(56, 2, -77)],
		["04_street_d", Vector3(-60, 1.8, 16), Vector3(-60, 3, -60)],
		["05_pano_c_north", Vector3(0, 1.8, -99), Vector3(0, 14, -260)],
		["06_pano_a_south", Vector3(0, 1.8, 34), Vector3(0, 16, 220)],
		["07_kiosk_close", Vector3(62.5, 1.7, -72.5), Vector3(55, 1.8, -77)],
		["08_kiosk_square", Vector3(74, 4.5, -58), Vector3(58, 0.5, -82)],
		["09_garages_c", Vector3(-12, 1.7, -105), Vector3(-12, 1.4, -117)],
		["10_playground", Vector3(-51, 2.2, 73.5), Vector3(-60, 0.6, 80)],
		["12_pano_b_north", Vector3(70, 1.8, 22), Vector3(70, 16, -250)],
		["13_pano_d_west", Vector3(-62, 1.8, -40), Vector3(-260, 14, -40)],
		["14_pano_a_east", Vector3(97, 1.8, 30), Vector3(260, 14, 30)],
		["16_lada_close", car_p + Vector3(3.5, 1.4, -4.0), car_p + Vector3(0, 0.7, 0)],
		["18_yard_wide", Vector3(-10, 6, 70), Vector3(-45, 4, 100)],
		["19_street_b_south", Vector3(72, 1.8, -40), Vector3(72, 4, 30)],
		["22_bank_close", Vector3(8, 1.3, 27.6), Vector3(8, 0.3, 24.4)],
		["23_yard_paths", Vector3(-20, 12, 66), Vector3(-45, 0, 92)],
		["24_yard_west", Vector3(-40, 8, 70), Vector3(-75, 0, 85)],
		["25_yard_ground", Vector3(-45, 1.7, 62), Vector3(-70, 0.5, 75)],
		["26_trail_top", Vector3(-53.3, 9, 66.5), Vector3(-53.3, 0, 66.4)],
	]
	for s in shots:
		await _shot(s[0], s[1], s[2])
	var traffic = world.get_node_or_null("LevelGeometry/Traffic")
	if traffic and traffic.trolleybus:
		var tb = traffic.trolleybus
		var waited := 0
		while not tb.doors_open and waited < 5400:
			await physics_frame
			waited += 1
		var p: Vector3 = tb.global_position
		var fwd: Vector3 = -tb.global_basis.z
		var right: Vector3 = tb.global_basis.x
		await _shot("20_trolley_stop", p + right * 7.0 + fwd * 8.0 + Vector3(0, 1.7, 0), p + Vector3(0, 1.6, 0))
		await _shot("21_trolley_side", p + right * 9.0 - fwd * 2.0 + Vector3(0, 1.7, 0), p + Vector3(0, 1.8, 0))
	world.enter_car()
	for i in 3: await physics_frame
	var car = world.car
	car.reset_to(Vector3(0, 0, 32), -PI * 0.5)
	world.camera_rig.yaw = -PI * 0.5
	world.camera_rig.snap()
	await physics_frame
	cam.current = false
	for c in world.camera_rig.find_children("*", "Camera3D", true, false):
		(c as Camera3D).make_current()
	car.velocity = -car.global_basis.z * 6.0
	Input.action_press(&"move_forward")
	for i in 150: await physics_frame
	await _save("g04_lada_drive_a")
	for i in 70: await physics_frame
	await _save("g05_lada_drive_a2")
	Input.action_release(&"move_forward")
	main.queue_free()
	for i in 5: await process_frame

func _shot(name: String, from: Vector3, to: Vector3) -> void:
	main.set_paused(false)
	cam.make_current()
	cam.global_position = from
	cam.look_at(to)
	for i in 8: await physics_frame
	await _save(name)

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + name + ".png")

## Что стоит в продолжении улицы A на восток (узкие вертикальные плиты в g05).
func _probe() -> void:
	await _start()
	var zone := AABB(Vector3(96, 3, 10), Vector3(500, 80, 44))
	print("PROBE start ", world, " ", world.find_children("*", "GeometryInstance3D", true, false).size())
	for n in world.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var local := mm.mesh.get_aabb()
			for i in mm.instance_count:
				var box: AABB = (g.global_transform * mm.get_instance_transform(i)) * local
				if box.intersects(zone) and box.size.y > 10.0 and minf(box.size.x, box.size.z) < 6.0:
					print("MM ", g.get_path(), " #", i, " ", box)
		else:
			var box2: AABB = g.global_transform * g.get_aabb()
			if box2.intersects(zone) and box2.size.y > 6.0:
				print("MI ", g.get_path(), " ", box2)

func _fps() -> String:
	var m: Node = load("res://game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.start_game()
	for i in 5: await process_frame
	var w: DemoWorld = m.world
	w.enter_car()
	var car: Lada = w.car
	var times: Array[float] = []
	var route := Layout.ROUTE_DRIVE
	var segment := 1
	var position := route[0]
	var frame := 0
	var last := Time.get_ticks_usec()
	while segment < route.size():
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1_000_000.0
		last = now
		frame += 1
		if frame > WARMUP_FRAMES:
			times.append(dt)
		var target := route[segment]
		var step := SPEED * minf(dt, 0.05)
		var to_target := target - position
		if to_target.length() <= step:
			position = target
			segment += 1
		else:
			position += to_target.normalized() * step
		var yaw := atan2(-to_target.x, -to_target.z)
		car.reset_to(position, yaw)
		w.camera_rig.yaw = yaw
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	var count := times.size()
	var worst := times.slice(int(count * 0.99))
	var worst_total := 0.0
	for t in worst:
		worst_total += t
	m.queue_free()
	for i in 5: await process_frame
	return "average %.1f, median %.1f, 1%% low %.1f, frames %d" % [count / total, 1.0 / times[count / 2], worst.size() / worst_total, count]
