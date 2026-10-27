extends SceneTree
## Замер FPS: машина проезжает ROUTE_DRIVE со скоростью ~50 км/ч, камера преследования, полный рендер.
## make fps → среднее, медиана, 1% худших кадров. Результат печатается строкой FPS:.

const Layout = preload("res://game/world/layout.gd")
const SPEED := 14.0
const WARMUP_FRAMES := 90

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 5:
		await process_frame
	var world: DemoWorld = main.world
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
	var average := count / total
	var median := 1.0 / times[count / 2]
	var worst := times.slice(int(count * 0.99))
	var worst_total := 0.0
	for t in worst:
		worst_total += t
	var low := worst.size() / worst_total
	var size := root.get_visible_rect().size
	print("FPS: average %.1f, median %.1f, 1%% low %.1f, frames %d, viewport %dx%d, %s, %s" % [average, median, low, count, size.x, size.y, RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()])
	main.queue_free()
	for i in 5:
		await process_frame
	quit(0)
