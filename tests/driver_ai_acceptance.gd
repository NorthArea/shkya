extends SceneTree
## Independent DRIVER-01 oracle, fixed before reading DriverAI/DriverRoute implementation.
## Requirements: ordinary C8 remains default; explicit pursue/evade/race use real road connectivity;
## closure detours, occluded observation, curvature/braking, pedestrian clearance, bounded recovery;
## actual TrafficCar movement respects published physical bounds without teleport/speed overrides.
## Published contract: DriverAI.attach/set_mode/clear/tick, TrafficCar.start_driving/stop_driving/driver_ai;
## public route.configure/plan/block_edge_at/points/position_at/length and observation telemetry.
const Layout = preload("res://game/world/layout.gd")
const Traffic = preload("res://game/vehicles/traffic_car.gd")
const Materials = preload("res://game/world/materials.gd")
const EnvDress = preload("res://game/world/environment_dress.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const DT := 1.0 / 60.0
const MAX_SPEED := 11.0
const ACCEL := 2.2
const REVERSE_SPEED := 1.6
const REVERSE_ATTEMPTS := 3
var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var lane: PathVehicle.LanePath

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/DRIVER-01/independent-%d.json" % OS.get_process_id()
	root.add_child(main)
	await process_frame
	main.start_game()
	await frames(8)
	world = main.world
	for sensor in get_nodes_in_group(&"detection_sensors"): sensor.enabled = false
	lane = PathVehicle.LanePath.build(Layout.CAR_RING,Layout.RING_LANE,PathVehicle.CAR_TURN_RADIUS)
	var traffic: Node = world.get_node("LevelGeometry/Traffic")
	# Existing traffic remains present but cannot interfere with explicitly arranged independent fixtures.
	for body in traffic.vehicles:
		body.set_physics_process(false)
		body.collision_layer = 0
	world.car.set_physics_process(false)
	world.car.reset_to(Vector3(-80,0,32),0)
	var probe := make_car(Vector3(73,0,-30))
	if not check(probe.has_method("start_driving") and probe.has_method("stop_driving"),"actual TrafficCar exposes explicit driver-mode integration"):
		probe.queue_free()
		await finish()
		return
	await default_and_api(probe)
	await graph_contract(probe)
	probe.queue_free()
	await frames(2)
	await perception()
	await pursuit_and_evade()
	await race_and_corner()
	await pedestrians()
	await displaced_reverse()
	await bounded_stuck()
	await actual_closure()
	await finish()

func make_car(at: Vector3) -> TrafficCar:
	var car: TrafficCar = Traffic.new()
	car.kind = &"zhiguli"
	world.add_child(car)
	car.setup(lane,lane.offset_of(at))
	return car

func default_and_api(car: TrafficCar) -> void:
	var origin := car.global_transform
	check(car.get("driver_ai") != null and not car.driver_ai.is_active(),"fresh ordinary driver starts with AI modes off")
	await frames(60)
	check(car.global_position.distance_to(origin.origin) > 0.2 and car.speed <= car.cruise_speed + 0.01,"ordinary C8 transport still follows its normal speed-limited lane")
	check(not car.start_driving(&"invalid") and not car.start_driving(&"pursue") and not car.start_driving(&"race",null,[]),"unknown/missing-target/empty-race commands are rejected")
	check(not car.driver_ai.is_active(),"invalid commands cannot accidentally enable hostile driving")
	car.set_physics_process(false)
	world.car.reset_to(lane.position_at(car.s + 18),car.global_rotation.y)
	check(car.start_driving(&"pursue",world.car),"pursuit requires and accepts an explicit real target")
	var pose := car.global_transform
	var speed := car.speed
	var command: Dictionary = car.driver_ai.tick(DT)
	check(car.global_transform == pose and car.speed == speed,"planner/controller tick never mutates authoritative vehicle pose or speed")
	check(command.has("target_speed") and command.has("steering") and command.has("reverse") and command.has("target_visible"),"published command exposes actual consumer inputs and observation result")
	check(float(command.get("target_speed",-1)) >= 0 and absf(float(command.get("steering",2))) <= 1,"controller command remains within throttle/steering contract")
	car.stop_driving()
	check(not car.driver_ai.is_active(),"stop explicitly returns control to safe ordinary traffic")
	car.set_physics_process(true)
	world.car.reset_to(Vector3(-80,0,32),0)

func graph_contract(car: TrafficCar) -> void:
	car.set_physics_process(false)
	car.start_driving(&"race",null,[Vector3(0,0,32)])
	var route: RefCounted = car.driver_ai.route
	route.configure(lane,car.size)
	var from := Vector3(70,0,-100)
	var goal := Vector3(0,0,32)
	check(route.plan(from,Vector3.BACK,goal),"road graph connects north-east junction to Lenin street")
	var direct: PackedVector3Array = route.points.duplicate()
	check(direct.size() > 2,"road plan contains a real traversable trajectory")
	route.block_edge_at(Vector3(67,0,Layout.CLOSURE_Z))
	check(route.plan(from,Vector3.BACK,goal),"blocking southbound Trolleynaya leaves a legal alternate road route")
	var west := false
	var crossed := false
	var offroad := false
	for step in range(ceili(float(route.length)) + 1):
		var point: Vector3 = route.position_at(float(step))
		west = west or point.x < -50
		crossed = crossed or (absf(point.z - Layout.CLOSURE_Z) < 2 and point.x > Layout.CLOSURE_X.x and point.x < Layout.CLOSURE_X.y)
		offroad = offroad or road_distance(point) > 9
	check(west and not crossed,"closure plan actually uses Vybornaya/Bogatkova rather than crossing the blocked street")
	check(not offroad,"alternate route stays on existing road/courtyard connections rather than cutting across buildings")
	check(route.points != direct,"a blocked directed edge materially changes the selected route")
	route.clear_blocks()
	car.stop_driving()
	car.set_physics_process(true)

func perception() -> void:
	var car := make_car(Vector3(73,0,-30))
	car.set_physics_process(false)
	world.car.reset_to(Vector3(73,0,-48),0)
	await frames(2)
	car.start_driving(&"pursue",world.car)
	car.driver_ai.tick(DT)
	check(car.driver_ai.target_visible,"unobstructed target on the same road is actually observed")
	var known: Vector3 = car.driver_ai.target_last_seen
	var wall := wall_at(Vector3(73,1.5,-39),Vector3(12,3,0.4))
	world.car.reset_to(Vector3(73,0,-57),0)
	await frames(2)
	var command: Dictionary = car.driver_ai.tick(DT)
	check(not command.get("target_visible",true) and not car.driver_ai.target_visible,"a real static wall blocks pursuit line of sight")
	check(car.driver_ai.target_last_seen.distance_to(known) < 0.01,"unseen target movement cannot update the last observed location")
	for i in 1800: car.driver_ai.tick(DT)
	check(not car.driver_ai.target_visible and car.driver_ai.target_last_seen.distance_to(known) < 0.01,"long occlusion never restores omniscient target tracking")
	check(float(car.driver_ai.observation_age) >= 20,"observation age advances while the target remains hidden")
	wall.queue_free()
	car.queue_free()
	world.car.reset_to(Vector3(-80,0,32),0)
	await frames(2)

func pursuit_and_evade() -> void:
	var car := make_car(Vector3(73,0,-30))
	world.car.reset_to(lane.position_at(car.s + 24),car.global_rotation.y)
	await frames(2)
	var before := car.global_position.distance_to(world.car.global_position)
	check(car.start_driving(&"pursue",world.car),"real TrafficCar accepts pursuit")
	var metrics := await motion(car,180)
	check(car.global_position.distance_to(world.car.global_position) < before - 2,"explicit pursuing NPC really closes distance to player car")
	physical_bounds(metrics,"pursuit")
	car.stop_driving()
	car.queue_free()
	await frames(2)
	car = make_car(Vector3(73,0,-45))
	world.car.reset_to(lane.position_at(car.s - 14),car.global_rotation.y)
	await frames(2)
	before = car.global_position.distance_to(world.car.global_position)
	check(car.start_driving(&"evade",world.car),"NPC can explicitly evade a player pursuing it")
	metrics = await motion(car,180)
	check(car.global_position.distance_to(world.car.global_position) > before + 2,"evading NPC really increases distance along a legal road")
	physical_bounds(metrics,"evade")
	car.queue_free()
	world.car.reset_to(Vector3(-80,0,32),0)
	await frames(2)

func race_and_corner() -> void:
	var car := make_car(Vector3(73,0,-20))
	var first := lane.position_at(car.s + 26)
	var second := lane.position_at(car.s + 106)
	check(car.start_driving(&"race",null,[first,second]),"racing NPC receives explicit ordered road checkpoints")
	var saw_first := false
	var saw_second := false
	var corner_speed := 0.0
	var straight_speed := 0.0
	var max_step := 0.0
	var last := car.global_position
	for i in 1200:
		await frames(1)
		max_step = maxf(max_step,car.global_position.distance_to(last))
		last = car.global_position
		if car.global_position.distance_to(first) < 8: saw_first = true
		if car.global_position.distance_to(second) < 8:
			saw_second = true
			break
		var projected := lane.offset_of(car.global_position)
		if lane.in_arc(projected): corner_speed = maxf(corner_speed,absf(car.speed))
		elif car.global_position.distance_to(first) > 10: straight_speed = maxf(straight_speed,absf(car.speed))
	check(saw_first and saw_second,"actual racing body reaches first and then second checkpoint around a city corner")
	check(corner_speed > 0 and straight_speed > corner_speed + 0.2,"racing car slows for actual road curvature instead of taking every turn at full speed")
	check(max_step <= MAX_SPEED * DT + 0.06,"race never snaps between checkpoints or boosts beyond the physical displacement cap")
	car.queue_free()
	await frames(2)

func pedestrians() -> void:
	var car := make_car(Vector3(73,0,-30))
	var person_at := lane.position_at(car.s + 17)
	world.player.place(person_at,0)
	world.player.set_physics_process(false)
	await frames(2)
	car.start_driving(&"race",null,[lane.position_at(car.s + 65)])
	var metrics := await motion(car,360,world.player)
	check(float(metrics["pedestrian_gap"]) > car.size.z * 0.5 + 0.35,"racing driver keeps physical pedestrian clearance")
	check(world.player.global_position.distance_to(person_at) < 0.05,"AI driver does not shove the pedestrian while waiting")
	check(absf(car.speed) < 0.1,"driver stops for a persistent pedestrian obstacle")
	physical_bounds(metrics,"pedestrian braking")
	world.player.place(Layout.SPAWN,Layout.SPAWN_YAW)
	world.player.set_physics_process(true)
	await frames(180)
	check(car.speed > 1,"explicit driver resumes after pedestrian clears its route")
	car.queue_free()
	await frames(2)

func displaced_reverse() -> void:
	var car := make_car(Vector3(73,0,-30))
	# A possible post-impact pose: across the real road, with enough clear pavement behind it.
	# Hold ordinary lane following until the explicit controller receives this initial pose.
	car.set_physics_process(false)
	car.global_position = Vector3(74,0,-30)
	car.global_rotation.y = -PI * 0.5
	await frames(2)
	check(car.global_position.distance_to(Vector3(74,0,-30)) < 0.001 and (-car.global_basis.z).dot(Vector3.RIGHT) > 0.999,"recovery fixture really remains side-on at the instant of activation")
	var displaced_pose := car.global_transform
	check(car.start_driving(&"race",null,[Vector3(73,0,-75)]),"displaced driver accepts its reachable road goal without resetting pose")
	check(car.global_transform == displaced_pose,"activating the explicit driver preserves the displaced physical pose")
	car.set_physics_process(true)
	var reversed := false
	var retried := false
	var last := car.global_position
	var forward := -car.global_basis.z
	var max_backward_speed := 0.0
	var max_reverse_distance := 0.0
	var reverse_distance := 0.0
	var idle := 0
	for i in 1500:
		await frames(1)
		var moved := car.global_position - last
		var backward := -moved.dot(forward)
		max_backward_speed = maxf(max_backward_speed,backward/DT)
		if backward > 0.0001:
			reversed = true
			idle = 0
			reverse_distance += moved.length()
			max_reverse_distance = maxf(max_reverse_distance,reverse_distance)
		else:
			idle += 1
			if idle > 45: reverse_distance = 0.0
		if reversed and car.driver_ai.state != &"reversing" and moved.dot(forward) > 0.005: retried = true
		last = car.global_position
		forward = -car.global_basis.z
	check(reversed,"real side-on displaced car actually backs through a clear rear corridor")
	check(retried,"bounded reverse finishes and the real consumer attempts forward driving again")
	check(max_backward_speed <= REVERSE_SPEED + 0.05,"physical reverse motion obeys the published reverse speed cap")
	# Include the finite stopping distance after the controller finishes its reverse command.
	check(max_reverse_distance <= 2.5 + REVERSE_SPEED*REVERSE_SPEED/(2*3.2) + 0.1,"each actual reverse maneuver remains bounded including braking distance")
	check(car.driver_ai.reverse_attempts <= REVERSE_ATTEMPTS,"displaced recovery never exceeds its finite attempt budget")
	car.queue_free()
	await frames(2)

func bounded_stuck() -> void:
	var car := make_car(Vector3(73,0,-30))
	var origin := car.global_position
	var walls: Array[StaticBody3D] = [wall_at(origin + Vector3(0,1.5,-5),Vector3(12,3,0.4)),wall_at(origin + Vector3(0,1.5,5),Vector3(12,3,0.4)),wall_at(origin + Vector3(-4,1.5,0),Vector3(0.4,3,10)),wall_at(origin + Vector3(4,1.5,0),Vector3(0.4,3,10))]
	await frames(2)
	car.start_driving(&"race",null,[lane.position_at(car.s + 50)])
	var metrics := await motion(car,1500)
	check(int(car.driver_ai.reverse_attempts) <= REVERSE_ATTEMPTS,"boxed-in driver has a finite reverse-attempt budget")
	check(float(metrics["reverse_speed"]) <= REVERSE_SPEED + 0.05,"recovery reverse obeys its physical speed cap")
	check(absf(car.global_position.x - origin.x) < 4 and absf(car.global_position.z-origin.z) < 5,"unreachable goal never teleports a car through the containing walls")
	check(int(metrics["overlaps"]) == 0,"bounded recovery never penetrates solid obstruction geometry")
	car.set_physics_process(false)
	var settled: Dictionary = car.driver_ai.tick(DT)
	check(absf(car.speed) < 0.1 and float(settled.get("target_speed",MAX_SPEED)) < 0.1,"fully blocked driver reaches a finite waiting/exhausted state without endless throttle")
	physical_bounds(metrics,"stuck recovery")
	for wall in walls: wall.queue_free()
	car.queue_free()
	await frames(2)

func actual_closure() -> void:
	world.player.place(Vector3(-20,0,-88),0)
	world.mission.interact(&"babka")
	world.mission.accept()
	world.mission.notify_entered_car()
	world.mission.notify_arrived_kiosk()
	world.mission.add_money(MissionDirector.BREAD_PRICE)
	check(world.mission.buy_bread(),"actual mission purchase produces the real road closure")
	var closure: Node = world.get_node("LevelGeometry/Patrols/RoadClosure")
	for i in 2700:
		if closure.is_blocking(): break
		await frames(1)
	if not check(closure.is_blocking(),"real closure fence and vehicle gap are physically closed"): return
	# Mid-street waiting may be necessary; observing the obstruction must still update the road graph.
	var detector := make_car(Vector3(73,0,-14))
	detector.set_physics_process(false)
	detector.global_position = Vector3(67,0,-14)
	detector.global_rotation.y = PI
	await frames(2)
	detector.start_driving(&"race",null,[Vector3(0,0,35)])
	detector.driver_ai.tick(DT)
	var learned: RefCounted = detector.driver_ai.route
	check(learned.plan(Vector3(70,0,-100),Vector3.BACK,Vector3(0,0,35)),"road graph remains routable after the real closure is observed")
	var observed_detour := false
	for point: Vector3 in learned.points: observed_detour = observed_detour or point.x < -50
	check(observed_detour,"actual RoadClosure collision shapes teach the controller its blocked edge without reading mission state")
	detector.queue_free()
	await frames(2)
	var car := make_car(Vector3(73,0,-50))
	car.start_driving(&"race",null,[Vector3(0,0,35)])
	var crossed := false
	var west := false
	var arrived := false
	for i in 3600:
		await frames(1)
		var p := car.global_position
		crossed = crossed or (absf(p.z - Layout.CLOSURE_Z) < car.size.z * 0.5 and p.x > Layout.CLOSURE_X.x and p.x < Layout.CLOSURE_X.y)
		west = west or p.x < -50
		if p.distance_to(Vector3(0,0,35)) < 8:
			arrived = true
			break
	check(arrived and west,"explicit racing driver follows the real Vybornaya/Bogatkova detour to Lenin street")
	check(not crossed and closure.is_blocking(),"detour never clips through closure or waits for its timeout to disappear")
	car.queue_free()
	await frames(2)

func motion(car: TrafficCar,count: int,person: Node3D = null) -> Dictionary:
	var metrics := {"max_step":0.0,"max_speed":0.0,"max_accel":0.0,"reverse_speed":0.0,"pedestrian_gap":INF,"overlaps":0}
	var last := car.global_position
	var speed := car.speed
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = car.size - Vector3(0.1,0.1,0.1)
	query.shape = box
	query.collision_mask = 1
	query.exclude = [car.get_rid()]
	for i in count:
		await frames(1)
		metrics["max_step"] = maxf(metrics["max_step"],car.global_position.distance_to(last))
		metrics["max_speed"] = maxf(metrics["max_speed"],absf(car.speed))
		metrics["max_accel"] = maxf(metrics["max_accel"],(car.speed-speed)/DT)
		metrics["reverse_speed"] = maxf(metrics["reverse_speed"],-car.speed)
		if person: metrics["pedestrian_gap"] = minf(metrics["pedestrian_gap"],car.global_position.distance_to(person.global_position))
		query.transform = car.global_transform.translated_local(Vector3.UP * car.size.y * 0.5)
		if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): metrics["overlaps"] += 1
		last = car.global_position
		speed = car.speed
	return metrics

func physical_bounds(metrics: Dictionary,label: String) -> void:
	check(float(metrics["max_speed"]) <= MAX_SPEED + 0.05,label + ": no speed boost beyond the published physical cap")
	check(float(metrics["max_step"]) <= MAX_SPEED * DT + 0.06,label + ": no per-frame teleport or transform catch-up")
	check(float(metrics["max_accel"]) <= ACCEL + 0.1,label + ": acceleration obeys the shared controller budget")

func road_distance(point: Vector3) -> float:
	var distance := INF
	for i in Layout.RING.size():
		distance = minf(distance,point.distance_to(Geometry3D.get_closest_point_to_segment(point,Layout.RING[i],Layout.RING[(i+1)%Layout.RING.size()])))
	for i in Layout.ROUTE_DRIVE.size()-1:
		distance = minf(distance,point.distance_to(Geometry3D.get_closest_point_to_segment(point,Layout.ROUTE_DRIVE[i],Layout.ROUTE_DRIVE[i+1])))
	return distance

func wall_at(at: Vector3,size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = at
	return wall

func frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool,text: String) -> bool:
	checks += 1
	print(("PASS " if ok else "FAIL ") + text)
	if not ok: failures.append(text)
	return ok

func finish() -> void:
	for type in ["AudioStreamPlayer","AudioStreamPlayer3D"]:
		for player in main.find_children("*",type,true,false): player.stop()
	main.queue_free()
	await frames(3)
	main = null
	world = null
	lane = null
	Materials.clear_cache()
	EnvDress.clear_cache()
	VehicleMesh.cache().clear()
	OS.delay_msec(100)
	await process_frame
	print("DRIVER_ACCEPTANCE: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
