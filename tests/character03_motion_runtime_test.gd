extends SceneTree
## Developer smoke of the real manager -> Resident -> physical root chain.
const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
var checks := 0
var failures: Array[String] = []
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(2))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/CHARACTER-03/dev-%d.json" % OS.get_process_id()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(90)
	var manager: Node = main.world.get_node("LevelGeometry/Residents")
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	for resident: Resident in manager.residents:
		resident._hide(&"inside")
		resident.set_physics_process(false)
	var a: Resident = manager.residents[0]
	var b: Resident = manager.residents[1]
	var west := Vector3(-40, 0, -109.5)
	var east := Vector3(-34, 0, -109.5)
	_prepare(a, west, east)
	_prepare(b, east, west)
	var minimum := INF
	var reacted := false
	for index in 720:
		await physics_frame
		minimum = minf(minimum, a.global_position.distance_to(b.global_position))
		reacted = reacted or a.motion.mode == &"dodge" or b.motion.mode == &"dodge"
	await process_frame
	check(reacted, "real residents perform a local physical reaction from a manager snapshot")
	check(minimum >= 0.69, "actual root positions keep capsule separation during the pass")
	check(a.global_position.distance_to(east) < 0.02 and b.global_position.distance_to(west) < 0.02,
		"both real residents reach their original canonical goals after yielding")
	check(a.route == [west, east] and b.route == [east, west], "local avoidance does not replace either route")
	var state: Dictionary = manager.motion_snapshot_state()
	check(int(state.frame) == Engine.get_physics_frames(), "manager exposes the current physical-frame observation")
	var obstacles: Array[Dictionary] = manager.motion_obstacles(a, 1.1)
	check(obstacles.all(func(record: Dictionary): return not record.has("actor") and not record.has("node")),
		"hazard records contain primitive observations without actor ownership")
	a.place(west)
	await _frames(2)
	check(a.motion.velocity == Vector3.ZERO and a.motion.mode == &"following", "placing a paused resident cancels its previous steering")
	await _finish()

func _prepare(resident: Resident, from: Vector3, to: Vector3) -> void:
	resident._act_stop()
	resident.errand = false
	resident.leader = null
	resident.follower = null
	resident.route = [from, to]
	resident.direction = 1
	resident.target_point = 1
	resident.state = &"walk"
	resident.pause_points = [1]
	resident.pause_seconds = 60.0
	resident.smoke_point = -1
	resident.wait_point = -1
	resident.rider = false
	resident.speed = 1.2
	resident._show()
	resident.place(from)
	resident.set_physics_process(true)

func _frames(count: int) -> void:
	for index in count:
		await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
	main.queue_free()
	await _frames(5)
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	OS.delay_msec(100)
	await process_frame
	print("CHARACTER03_MOTION_RUNTIME: %d checks, %d failures; full Life/KNOCK and visual acceptance NOT_RUN" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
