extends SceneTree
## Замер FPS: машина проезжает ROUTE_DRIVE со скоростью ~50 км/ч, камера преследования, полный рендер.
## make fps → среднее, медиана, 1% худших кадров. Результат печатается строкой FPS:.

const Layout = preload("res://game/world/layout.gd")
const SPEED := 14.0
const WARMUP_FRAMES := 90

var _env_fixture: Array = []
var _original_fixture: Array = []

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
	var break_env := "--break-env" in OS.get_cmdline_user_args()
	if break_env and not await _prepare_break_env(world):
		await _abort_setup(main)
		return
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
	if break_env and not _verify_break_env(world):
		await _abort_setup(main)
		return
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

## Optional controlled scene composition; the ordinary route/warmup/measurement remain unchanged.
## Destruction transients finish before measurement; restore_left pins this fixture during the route.
func _prepare_break_env(world: DemoWorld) -> bool:
	var owner: Node = world.get_node_or_null("LevelGeometry/Breakables")
	if owner == null or not owner.has_method("env_at_index"):
		return _setup_failed("BREAK-03 runtime is not present")
	var catalogue: Array = Layout.env_breakables()
	var objects: Array = owner.get("env_objects")
	if catalogue.is_empty() or objects.size() != catalogue.size():
		return _setup_failed("ENV catalogue/runtime count mismatch or empty ENV")
	var solids := Layout.all_solids()
	var constants: Dictionary = owner.get_script().get_script_constant_map()
	var modes: Dictionary = constants["ENV_MODE"]
	var seen := {}
	for spec: Array in catalogue:
		var source: Array = solids[spec[6]]
		if source[1] in ["panel", "panel_low", "garage", "kiosk", "snow", "snow_bank"] \
			or source[0] in ["DogHouse", "KioskPavilion", "KioskBins"]:
			return _setup_failed("protected solid was included in ENV: " + String(spec[0]))
		var object: Variant = owner.get_by_id(spec[0])
		if object == null or seen.has(spec[0]) or not objects.has(object) or object.env_index != spec[6] \
			or object.kind != spec[1] or object.mode != modes.get(spec[1], &"shatter") \
			or object.mode not in [&"topple", &"shatter", &"dent"]:
			return _setup_failed("invalid ENV owner/mode: " + String(spec[0]))
		seen[spec[0]] = true
		_env_fixture.append(object)
	for spec: Array in Layout.BREAKABLES:
		var object: Variant = owner.get_by_id(spec[0])
		if object == null or _env_fixture.has(object):
			return _setup_failed("original breakable missing or incorrectly included in ENV")
		_original_fixture.append([object, object.state, object.blocks(), object.body.collision_layer])
	var coins_before: int = owner.coins_dropped
	for object: Variant in _env_fixture:
		object.smash(&"fps_setup", Vector3.RIGHT)
		object.restore_left = 1.0e9
	if owner.coins_dropped != coins_before:
		return _setup_failed("controlled setup unexpectedly awarded coins")
	# Fall/sink and car alarms finish on real physics time; no world/NPC/physics processing is disabled.
	var settle_seconds: float = maxf(float(constants["FALL_SECONDS"]) + float(constants["LIE_SECONDS"]) \
		+ float(constants["SINK_SECONDS"]), float(constants["ALARM_SECONDS"])) + 1.0
	var ready_frame := Engine.get_physics_frames() + ceili(settle_seconds * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < ready_frame:
		await process_frame
	if owner.debris_count() != 0 or not _verify_break_env(world):
		return _setup_failed("ENV did not reach a steady broken/dent composition")
	var counts := {"topple": 0, "shatter": 0, "dent": 0}
	for object: Variant in _env_fixture:
		counts[String(object.mode)] += 1
	var people: Node = world.get_node("LevelGeometry/Residents")
	print("FPS_BREAK_ENV_SETUP: ", JSON.stringify({"status": "READY", "broken_env": _env_fixture.size(),
		"catalogue_env": catalogue.size(), "modes": counts, "original_breakables_preserved": _original_fixture.size(),
		"residents": people.residents.size(), "traffic_vehicles": get_nodes_in_group(&"traffic_vehicles").size(),
		"settle_physics_seconds_min": settle_seconds, "restore_pin_seconds": 1.0e9,
		"scope": "steady already-broken scene; excludes simultaneous destruction performance and manual feel acceptance",
		"route": "unchanged Layout.ROUTE_DRIVE scripted reset_to", "warmup_frames": WARMUP_FRAMES,
		"rendering_method": RenderingServer.get_current_rendering_method(), "physics_hz": Engine.physics_ticks_per_second}))
	return true

func _verify_break_env(world: DemoWorld) -> bool:
	if paused or not world.can_process():
		return _setup_failed("world was paused or disabled")
	var owner: Node = world.get_node("LevelGeometry/Breakables")
	if not owner.is_physics_processing() or not owner.can_process():
		return _setup_failed("Breakables physics processing was disabled")
	var vehicles: Array = get_nodes_in_group(&"traffic_vehicles")
	if vehicles.size() != Layout.TRAFFIC_CARS + 1:
		return _setup_failed("ring traffic composition changed")
	vehicles.append(world.get_node("LevelGeometry/Patrols/CityVan"))
	for vehicle: Node in vehicles:
		if not vehicle.is_physics_processing() or not vehicle.can_process():
			return _setup_failed("transport processing was disabled")
	var people: Node = world.get_node("LevelGeometry/Residents")
	if people.residents.size() < 64 or not people.is_physics_processing():
		return _setup_failed("64 active residents are required")
	for resident: Node in people.residents:
		if not resident.is_physics_processing() or not resident.can_process():
			return _setup_failed("resident processing was disabled")
	for object: Variant in _env_fixture:
		if not is_instance_valid(object) or not is_instance_valid(object.body):
			return _setup_failed("ENV owner/body disappeared")
		var dent: bool = object.mode == &"dent"
		var shape: CollisionShape3D = object.body.get_child(0)
		if object.state != &"broken" or object.is_intact() or object.blocks() != dent or object.restore_left <= 0.0 \
			or object.body.collision_layer != (33 if dent else 0) or shape.disabled != (not dent) \
			or object.env_hidden() != (not dent):
			return _setup_failed("ENV actual state/mode/collision differs from fixture: " + String(object.id))
	for original: Array in _original_fixture:
		var object: Variant = original[0]
		if object.state != original[1] or object.blocks() != original[2] or object.body.collision_layer != original[3]:
			return _setup_failed("original breakable changed: " + String(object.id))
	return true

func _setup_failed(reason: String) -> bool:
	push_error("FPS_BREAK_ENV_SETUP FAILED: " + reason)
	return false

func _abort_setup(main: Node) -> void:
	main.queue_free()
	for i in 5:
		await process_frame
	quit(2)
