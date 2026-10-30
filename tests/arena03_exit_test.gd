extends SceneTree
## Разработка ARENA-03: настоящий Resident/Life, наблюдаемый северный выход.
## Длительная натуральная сцена отдельно: tools/capture/arena03_exit.gd.

const Layout = preload("res://game/world/layout.gd")
var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var people: Node
var life

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(12)
	world = main.world
	people = world.get_node("LevelGeometry/Residents")
	life = people.life
	check(people.residents.size() == 64, "all 64 residents remain instantiated")
	for resident: Resident in people.residents:
		resident.set_physics_process(false)
		resident._act_stop()
	life.reset()
	var first: Resident = people.residents[34]
	var second: Resident = people.residents[42]
	var spot: Dictionary = life.spots[&"edge_d_n"]
	var approach: Vector2 = Layout.LIFE_NODES[&"dw_s"]
	world.player.place(Vector3(approach.x, 0.0, spot.pos.z + 3.0), 0.0)
	world.camera_rig.follow(world.player, &"on_foot")
	world.camera_rig.yaw = 0.0
	world.camera_rig.snap()
	await _frames(8)
	check(life.on_screen(spot.pos), "the test observes the actual exit with the game camera")
	first._show()
	first._met = true
	first.home = &"door_h11"
	first.plan = [&"edge_d_n", &"home"]
	first.plan_i = 0
	first.place(spot.pos)
	first._go_to(&"edge_d_n")
	check(life.reserved.get(&"edge_d_n", []).size() == 1, "one resident owns the approach and waiting place")
	check(life.choose(second, &"edge_d_n", second.home, second.rng) == &"", "another resident continues other errands instead of joining the same point")
	check(not life.reserve(&"edge_d_n", second), "a stale second intention cannot acquire the occupied exit")
	var previous := first.global_position
	var jumped := false
	var disappeared := false
	var max_stop := 0.0
	var stop := 0.0
	for frame in 1200:
		first._physics_process(1.0 / 60.0)
		var movement := previous.distance_to(first.global_position)
		jumped = jumped or movement > 0.1
		disappeared = disappeared or first.hidden
		stop = stop + 1.0 / 60.0 if movement < 0.0001 else 0.0
		max_stop = maxf(max_stop, stop)
		previous = first.global_position
	check(not disappeared, "an observed resident never disappears")
	check(not jumped, "waiting transitions into ordinary walking without a position jump")
	check(max_stop <= 10.0, "visible waiting is bounded before the next errand (%.2f s)" % max_stop)
	check(first.spot_id == &"door_h11" and first.global_position.distance_to(spot.pos) > 5.0, "the resident walks back toward the next real destination")
	check(not life.reserved.get(&"edge_d_n", []).has(first), "visible departure releases the exit reservation")
	var departure: Dictionary = life.path(spot.pos, &"door_h11", &"edge_d_n")
	var return_at: Vector2 = Layout.LIFE_NODES[&"dw_return"]
	check(departure.points.size() > 2 and departure.points[1].distance_to(Vector3(return_at.x, 0.0, return_at.y)) < 0.01, "the return uses the other side of the sidewalk")
	# Вне кадра остаётся прежняя причинная цепочка: уход, выдержка, возврат там же.
	first._act_stop()
	life.reset()
	first.plan_i = 0
	first.place(spot.pos)
	first._go_to(&"edge_d_n")
	var camera = life.camera
	life.camera = null
	first._tick_activity(1.0 / 60.0)
	check(first.hidden and first.state == &"away", "an unobserved exit still allows an actual away interval")
	check(not life.reserve(&"edge_d_n", second), "an away resident retains the return place")
	life.camera = camera
	first._wait = 0.0
	first._tick_hidden(1.0 / 60.0)
	check(first.hidden, "return waits while the camera observes the emergence point")
	life.camera = null
	first._wait = 0.0
	first._tick_hidden(1.0 / 60.0)
	check(not first.hidden and first.state == &"walk" and first.spot_id == &"door_h11", "an unobserved return resumes the next errand")
	life.camera = camera
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	main.queue_free()
	await _frames(6)
	life = null
	people = null
	world = null
	main = null
	preload("res://game/world/materials.gd").clear_cache()
	preload("res://game/vehicles/vehicle_mesh.gd").cache().clear()
	OS.delay_msec(100)
	await process_frame
	print("ARENA03_EXIT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok: failures.append(message)
	print("PASS: " if ok else "FAIL: ", message)
	return ok

func _frames(count: int) -> void:
	for frame in count: await physics_frame
