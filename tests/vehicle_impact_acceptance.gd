extends SceneTree
## Independent acceptance: real Main/Lada slide contacts against real traffic and parked adapters.
## Remote fixture changes only initial placement; all collision/impulse/deformation paths are production.
const Impact = preload("res://game/vehicles/vehicle_impact.gd")
const Traffic = preload("res://game/vehicles/traffic_car.gd")
const Materials = preload("res://game/world/materials.gd")
const EnvDress = preload("res://game/world/environment_dress.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
var main: Node
var world: DemoWorld
var failures: Array[String] = []
var checks := 0
var lane: PathVehicle.LanePath
var fixture := Vector3(-300, 0, -300)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/VEHICLE-01/independent-%d.json" % OS.get_process_id()
	root.add_child(main)
	await process_frame
	main.start_game()
	await frames(8)
	world = main.world
	for sensor in get_nodes_in_group(&"detection_sensors"): sensor.enabled = false
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(150, 0.5, 150)
	shape.shape = box
	floor_body.add_child(shape)
	world.add_child(floor_body)
	floor_body.global_position = fixture + Vector3.DOWN * 0.25
	lane = PathVehicle.LanePath.build([Vector3(-300,0,-270), Vector3(-300,0,-340), Vector3(-240,0,-340), Vector3(-240,0,-270)], 0, 4)
	world.enter_car()
	await frames(2)
	var slow := await traffic_case(&"zhiguli", 6, 0.5)
	var fast := await traffic_case(&"zhiguli", 15, 0.5)
	var heavy := await traffic_case(&"gazelle", 15, 0.5)
	check(fast["distance"] > slow["distance"], "stronger real slide impact displaces traffic farther")
	check(fast["velocity"] > heavy["velocity"], "same player impact accelerates lighter traffic more")
	await chain_case()
	await sliding_case()
	await wall_case()
	await parked_case()
	for type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player in main.find_children("*", type, true, false): player.stop()
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
	print("VEHICLE_INDEPENDENT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func traffic_case(kind: StringName, incoming: float, offcenter: float) -> Dictionary:
	var target: TrafficCar = Traffic.new()
	target.kind = kind
	target.cruise_speed = 0
	target.corner_speed = 0
	world.add_child(target)
	target.setup(lane, 20)
	var origin := target.global_transform
	var untouched: TrafficCar = Traffic.new()
	untouched.kind = kind
	untouched.cruise_speed = 0
	world.add_child(untouched)
	untouched.global_position = fixture + Vector3(30, 0, 0)
	var clean := target.visual.get_node("Body/BodyMesh").mesh as Mesh
	var second_clean := untouched.visual.get_node("Body/BodyMesh").mesh as Mesh
	await launch(target, target.size, incoming, offcenter)
	var displacement := target.global_position.distance_to(origin.origin)
	var received_speed := target.impact_velocity.length()
	var changed := target.visual.get_node("Body/BodyMesh").mesh as Mesh
	check(target.impact_active and displacement > 0.03, "%s %.1f: real slide moves target (%.3fm)" % [kind,incoming,displacement])
	check(absf(angle_difference(target.global_rotation.y, origin.basis.get_euler().y)) > 0.001, "%s: eccentric real impact rotates target" % kind)
	check(changed != clean and dent_delta(changed,clean) > 0.001, "%s: real contact deforms body vertices" % kind)
	check(untouched.visual.get_node("Body/BodyMesh").mesh == second_clean, "%s: other instance's shared provider stays pristine" % kind)
	if kind == &"zhiguli" and incoming > 10:
		var first_damage := dent_delta(changed, clean)
		target.impact_active = false
		target.impact_velocity = Vector3.ZERO
		target.impact_yaw = 0
		target._actual_velocity = Vector3.ZERO
		target.global_transform = origin
		await launch(target, target.size, incoming, offcenter)
		check(dent_delta(target.visual.get_node("Body/BodyMesh").mesh, clean) > first_damage, "second separate real collision accumulates a local dent")
		world.car.reset_to(fixture + Vector3(20,0,0), 0)
		check(world.car.visual.get_meta("vehicle_dent_count",0) == 0, "player reset clears collision dents")
		target.setup(lane, 20)
		check(target.visual.get_node("Body/BodyMesh").mesh == clean and not target.impact_active, "traffic reset restores shared undamaged body and path state")
		target.cruise_speed = 9
		await frames(100)
		check(target.distance_travelled > 0.1, "reset traffic resumes its production route")
	if kind == &"zhiguli" and incoming < 10:
		world.car.reset_to(fixture + Vector3(20,0,0),0)
		target.cruise_speed = 9
		await frames(480)
		check(not target.impact_active and target.distance_travelled > 0.1,"traffic naturally recovers to its route after impact without reset")
	target.queue_free()
	untouched.queue_free()
	await frames(2)
	return {"distance": displacement, "velocity": received_speed}

func launch(target: Node3D, size: Vector3, incoming: float, offcenter: float) -> void:
	world.car.reset_to(target.global_position + target.global_basis.z * (size.z * 0.5 + Lada.SIZE.z * 0.5 + 0.8) + target.global_basis.x * offcenter, target.global_rotation.y)
	await frames(2)
	world.car.velocity = -world.car.global_basis.z * incoming
	Input.action_press(&"car_gas")
	await frames(23)
	Input.action_release(&"car_gas")

func wall_case() -> void:
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20,4,0.3)
	collider.shape = box
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = fixture + Vector3(0,2,12)
	world.car.reset_to(fixture + Vector3(0,0,17), 0)
	await frames(2)
	world.car.velocity = Vector3(0,0,-26)
	Input.action_press(&"car_gas")
	var minimum := INF
	for i in 90:
		await frames(1)
		minimum = minf(minimum, world.car.global_position.z)
	Input.action_release(&"car_gas")
	check(minimum >= fixture.z + 12 + 0.15 + Lada.SIZE.z * 0.5 - 0.1, "maximum-speed real wall collision never tunnels through wall")
	check(world.car.visual.get_meta("vehicle_dent_count",0) > 0, "solid world collision dents player body")
	wall.queue_free()

func sliding_case() -> void:
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3,4,40)
	collider.shape = box
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = fixture + Vector3(-1.01,2,0)
	world.car.reset_to(fixture + Vector3(0,0,8),0)
	await frames(2)
	world.car.velocity = Vector3(-0.5,0,-15)
	var touched := false
	for i in 40:
		await frames(1)
		for j in world.car.get_slide_collision_count():
			if world.car.get_slide_collision(j).get_collider() == wall: touched = true
	check(touched,"grazing fixture actually reaches the real slide-contact boundary")
	check(world.car.visual.get_meta("vehicle_dent_count",0) == 0,"high tangent speed with sub-threshold normal motion produces no dent")
	wall.queue_free()
	await frames(2)

func parked_case() -> void:
	var breakables: Node = world.get_node("LevelGeometry/Breakables")
	var parked: Node
	for b in breakables.objects:
		if b.kind == &"parked" and b.parked_visual != null:
			parked = b
			break
	if not check(parked != null, "real Main contains registered parked-car adapter"): return
	var delta: Vector3 = fixture + Vector3(0,0,25) - parked.global_ground()
	parked.center += Vector2(delta.x,delta.z)
	for i in parked.env_node_xf.size(): parked.env_node_xf[i].origin += delta
	breakables._write(parked)
	await frames(2)
	var start: Transform3D = parked.body.global_transform
	var clean := parked.parked_visual.get_node("Body/BodyMesh").mesh as Mesh
	await launch(parked.body, parked.size, 15, 0.5)
	check(parked.body.global_position.distance_to(start.origin) > 0.03, "real parked collision displaces physical body")
	check(absf(angle_difference(parked.body.global_rotation.y,start.basis.get_euler().y)) > 0.001, "real parked collision rotates physical body")
	check(dent_delta(parked.parked_visual.get_node("Body/BodyMesh").mesh,clean) > 0.001, "real parked collision deforms its own body mesh")
	parked.reset()
	breakables._write(parked)
	check(parked.body.global_position.distance_to(start.origin) < 0.001 and parked.parked_visual.get_node("Body/BodyMesh").mesh == clean, "parked reset restores original location and undamaged mesh")

func chain_case() -> void:
	world.car.reset_to(fixture + Vector3(30,0,30),0)
	var cars: Array[TrafficCar] = []
	var origins: Array[Vector3] = []
	for i in 3:
		var target: TrafficCar = Traffic.new()
		target.kind = &"zhiguli"
		target.cruise_speed = 0
		target.corner_speed = 0
		world.add_child(target)
		target.setup(lane,20 + 4.35 * i)
		cars.append(target)
		origins.append(target.global_position)
	await launch(cars[0],cars[0].size,26,0.15)
	# Keep the player's front away after delivering the initial collision, so only the first car can push the next.
	world.car.reset_to(fixture + Vector3(30,0,30),0)
	await frames(45)
	for i in range(1,3):
		check(cars[i].global_position.distance_to(origins[i]) > 0.015,"pile-up transfers actual swept impulse to car %d without direct Lada contact" % (i+1))
		check(cars[i].visual.get_meta("vehicle_dent_count",0) > 0,"pile-up dents downstream car %d through a real vehicle contact" % (i+1))
	for target in cars: target.queue_free()
	await frames(2)

func dent_delta(mesh: Mesh, original: Mesh) -> float:
	var amount := 0.0
	for s in mesh.get_surface_count():
		var a: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array = original.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for i in a.size(): amount += a[i].distance_to(b[i])
	return amount

func frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool, text: String) -> bool:
	checks += 1
	print(("PASS " if ok else "FAIL ") + text)
	if not ok: failures.append(text)
	return ok
