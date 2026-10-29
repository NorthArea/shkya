extends SceneTree
## CITY-02 E: одно окно на часть — кадры с тех же точек, что city02e_frames.gd, затем замер FPS как tools/fps_probe.gd
## дважды: с узлами части E (Environment, Skyline) и со скрытыми (для разницы стоимости). Аргументы после --:
## каталог кадров, режим ("all" | "frames" | "fps").
const Layout = preload("res://game/world/layout.gd")
const SPEED := 14.0
const WARMUP_FRAMES := 90

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/Users/a.iuskasov/Workspace/shkya/builds/screenshots/CITY-02/e/after/"
	var mode: String = args[1] if args.size() > 1 else "all"
	if mode != "fps":
		await _frames(out)
	if mode != "frames":
		# Окно идёт в фоне через `open -g`: вывод движка не всегда доходит — итог пишется в файл рядом с логами.
		var lines := []
		lines.append("FPS_E_ON: " + await _fps(true))
		lines.append("FPS_E_OFF: " + await _fps(false))
		lines.append("FPS_E_ON2: " + await _fps(true))
		var f := FileAccess.open("/Users/a.iuskasov/Workspace/shkya/builds/checks/CITY-02/e/fps_after.txt", FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("\n".join(lines))
	quit(0)

func _frames(out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await physics_frame
	main.menu.start_button.pressed.emit()
	for i in 30: await physics_frame
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	var t0 := Time.get_ticks_msec()
	for s in _shots():
		main.set_paused(false)   # окно в фоне: случайный Esc не должен попасть в кадр
		cam.global_position = s[1]
		cam.look_at(s[2])
		for i in 8: await physics_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out + s[0] + ".png")
	print("FRAMES: %d in %d ms" % [_shots().size(), Time.get_ticks_msec() - t0])
	cam.queue_free()
	main.queue_free()
	for i in 5: await process_frame

func _shots() -> Array:
	return [
		["01_yard", Vector3(-30, 2.0, 96), Vector3(-60, 2.5, 80)],
		["02_a_x_b", Vector3(60, 2.2, 44), Vector3(80, 5, 10)],
		["03_kiosk_stop", Vector3(67, 1.8, -52), Vector3(56, 2, -77)],
		["04_street_d_night", Vector3(-60, 1.8, 16), Vector3(-60, 3, -60)],
		["05_pano_c_north", Vector3(0, 1.8, -99), Vector3(0, 14, -260)],
		["06_pano_a_south", Vector3(0, 1.8, 34), Vector3(0, 16, 220)],
		["07_kiosk_close", Vector3(62.5, 1.7, -72.5), Vector3(55, 1.8, -77)],
		["08_garages_c", Vector3(-12, 1.7, -105), Vector3(-12, 1.4, -117)],
		["09_playground", Vector3(-51, 2.2, 73.5), Vector3(-60, 0.6, 80)],
		["10_bank_3m", Vector3(8, 1.3, 27.6), Vector3(8, 0.3, 24.4)],
		["11_poplar_close", Vector3(-5, 1.6, 21.5), Vector3(-5, 9, 17)],
		["12_pano_b_north", Vector3(70, 1.8, 22), Vector3(70, 16, -250)],
		["13_wires_a", Vector3(-20, 1.8, 30), Vector3(40, 7, 32)],
		["14_shop24", Vector3(-53, 1.8, -34), Vector3(-46, 1.8, -40)],
		["15_billboard", Vector3(-66, 1.8, -99), Vector3(-78, 8, -117)],
		["16_bus_stop_a", Vector3(-27, 1.7, 27), Vector3(-30, 1.3, 21)],
		["17_pano_d_west", Vector3(-62, 1.8, -40), Vector3(-260, 14, -40)],
		["18_pano_a_east", Vector3(97, 1.8, 30), Vector3(260, 14, 30)],
	]

## Как tools/fps_probe.gd: «Лада» по ROUTE_DRIVE 14 м/с, камера преследования; show — узлы части E видимы.
func _fps(show: bool) -> String:
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 5: await process_frame
	var world: DemoWorld = main.world
	for n in ["LevelGeometry/Environment", "LevelGeometry/Skyline"]:
		var node := world.get_node_or_null(n)
		if node:
			node.visible = show
	world.enter_car()
	var car: Lada = world.car
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
		world.camera_rig.yaw = yaw
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	var count := times.size()
	var worst := times.slice(int(count * 0.99))
	var worst_total := 0.0
	for t in worst:
		worst_total += t
	main.queue_free()
	for i in 5: await process_frame
	return "average %.1f, median %.1f, 1%% low %.1f, frames %d" % [count / total, 1.0 / times[count / 2], worst.size() / worst_total, count]
