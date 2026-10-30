extends SceneTree
## CROSS-01: зебра совпадает с настоящим маршрутом жителя; перед ней он ждёт «Ладу» и транспорт кольца.

const Layout = preload("res://game/world/layout.gd")

var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var crossing_node: Node3D
var resident: Resident
var life
var camera: Camera3D
var traffic_car: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	crossing_node = world.get_node_or_null("LevelGeometry/Crosswalks")
	if not check(crossing_node != null, "zebra crossings are connected to the playable city"):
		await _finish()
		return
	var plans: Array = crossing_node.crossings()
	var expected := Layout.LIFE_EDGES.filter(func(edge): return edge.size() > 2 and edge[2] == &"cross")
	check(plans.size() == expected.size(), "every existing pedestrian road crossing has a zebra")
	check(crossing_node.find_children("*", "CollisionObject3D", true, false).is_empty(), "paint adds no obstacles for residents, traffic, hero or stealth")
	check(crossing_node.find_children("*", "CanvasLayer", true, false).is_empty(), "crossings live in the world, below the HUD")
	var stripe_count := 0
	for plan: Dictionary in plans:
		_geometry(plan)
		stripe_count += plan.stripes.size()
	check(crossing_node.get_node("Stripes").multimesh.instance_count == stripe_count, "all planned stripes are drawn by one bounded batch")
	var residents_node: Node = world.get_node("LevelGeometry/Residents")
	life = residents_node.life
	for actor: Resident in residents_node.residents:
		actor.set_physics_process(false)
		actor.hide()
	resident = residents_node.residents[0]
	resident.leader = null
	resident.follower = null
	resident.player = world.player
	resident.lada = world.car
	resident.errand = true
	resident.hidden = false
	resident._acting = false
	resident.knock_phase = &""
	resident.visual.position = Vector3.ZERO
	resident.show()
	for vehicle: Node3D in life.vehicles:
		vehicle.set_physics_process(false)
		vehicle.global_position = Vector3(1000, 0, 1000)
	traffic_car = life.vehicles[0]
	world.player.set_physics_process(false)
	world.car.set_physics_process(false)
	world.camera_rig.set_physics_process(false)
	world.camera_rig.set_process(false)
	camera = root.get_camera_3d()
	life.camera = camera
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	world.enter_car()
	for plan: Dictionary in plans:
		_cross_in_direction(plan, plan.from, plan.to)
		_cross_in_direction(plan, plan.to, plan.from)
	await _finish()

func _geometry(plan: Dictionary) -> void:
	var edge_found := false
	for edge in Layout.LIFE_EDGES:
		if edge.size() > 2 and edge[2] == &"cross" and edge[0] == plan.edge[0] and edge[1] == plan.edge[1]:
			edge_found = true
	check(edge_found, "%s derives from an actual Life crossing" % [plan.edge])
	var source_from: Vector2 = Layout.LIFE_NODES[plan.edge[0]]
	var source_to: Vector2 = Layout.LIFE_NODES[plan.edge[1]]
	check(plan.from.is_equal_approx(Vector3(source_from.x, 0, source_from.y)) and plan.to.is_equal_approx(Vector3(source_to.x, 0, source_to.y)), "%s keeps the NPC route endpoints" % [plan.edge])
	var contained := true
	for transform: Transform3D in plan.stripes:
		for x: float in [-0.5, 0.5]:
			for z: float in [-0.5, 0.5]:
				var corner := transform * Vector3(x, 0, z)
				contained = contained and plan.road_rect.has_point(Vector2(corner.x, corner.z))
	check(contained and plan.stripes.size() >= 8, "%s has readable stripes entirely on the road" % [plan.edge])
	check(not plan.road_rect.has_point(source_from) and not plan.road_rect.has_point(source_to), "%s leaves both sidewalk approaches unpainted" % [plan.edge])

func _cross_in_direction(plan: Dictionary, from: Vector3, to: Vector3) -> void:
	var route := _route_from_life(from, to)
	if not check(not route.is_empty(), "%s has a real Life.path from %s to the other side" % [plan.edge, from]):
		return
	resident.route = route.points
	resident.route_flags = route.flags
	resident.spot_id = route.goal
	resident.global_position = from
	resident.target_point = route.index + 1
	resident.direction = 1
	resident.state = &"walk"
	resident._cross_ok = -1
	resident._on_start_leg = false
	resident._acting = false
	resident.hidden = false
	resident.show()
	var middle := from.lerp(to, 0.5)
	camera.global_position = middle + Vector3(0, 8, 12)
	camera.look_at(middle)
	world.car.reset_to(middle, atan2(-(plan.road_to.z - plan.road_from.z), plan.road_to.x - plan.road_from.x))
	for i in 20:
		resident._physics_process(1.0 / 60.0)
	check(resident.state == &"wait_cross" and resident.global_position.distance_to(from) < 0.05, "%s waits at this curb while the driven Lada occupies the crossing" % [plan.edge])
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	traffic_car.global_position = middle
	for i in 20:
		resident._physics_process(1.0 / 60.0)
	check(resident.state == &"wait_cross" and resident.global_position.distance_to(from) < 0.05, "%s still waits for a real ring vehicle" % [plan.edge])
	traffic_car.global_position = Vector3(1000, 0, 1000)
	var on_paint := true
	var entered_road := false
	var limit := ceili(from.distance_to(to) / resident.speed * 60.0) + 180
	for i in limit:
		resident._physics_process(1.0 / 60.0)
		var point: Vector2 = Vector2(resident.global_position.x, resident.global_position.z)
		if plan.road_rect.has_point(point):
			entered_road = true
			var closest := Geometry2D.get_closest_point_to_segment(point, Vector2(plan.road_from.x, plan.road_from.z), Vector2(plan.road_to.x, plan.road_to.z))
			on_paint = on_paint and point.distance_to(closest) < float(plan.width) * 0.5
		if resident.global_position.distance_to(to) < 0.05:
			break
	check(entered_road and on_paint, "%s follows the painted crossing after traffic clears" % [plan.edge])
	check(resident.global_position.distance_to(to) < 0.05, "%s reaches the opposite sidewalk without teleporting" % [plan.edge])

func _route_from_life(from: Vector3, to: Vector3) -> Dictionary:
	for goal in life.spots:
		var path: Dictionary = life.path(from, goal)
		for i in path.flags.size():
			if path.flags[i] == &"cross" and path.points[i].distance_to(from) < 0.05 and path.points[i + 1].distance_to(to) < 0.05:
				return {"points": path.points, "flags": path.flags, "index": i, "goal": goal}
	return {}

func _frames(count: int) -> void:
	for i in count: await physics_frame

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _finish() -> void:
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	main = null
	world = null
	life = null
	resident = null
	preload("res://game/world/materials.gd").clear_cache()
	preload("res://game/vehicles/vehicle_mesh.gd").cache().clear()
	print("CROSS01: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
