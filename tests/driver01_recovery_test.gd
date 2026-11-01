extends SceneTree
## Developer regression for the post-impact Gazelle pose recorded by the independent composition oracle.
const Layout = preload("res://game/world/layout.gd")
const Traffic = preload("res://game/vehicles/traffic_car.gd")
const AI = preload("res://game/vehicles/driver_ai.gd")
const Meshes = preload("res://game/vehicles/vehicle_mesh.gd")
var failures: Array[String] = []
var checks := 0
var car: TrafficCar
var bank: StaticBody3D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func obstacle(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)
	body.global_position = at
	return body

func run() -> void:
	var lane := PathVehicle.LanePath.build(Layout.CAR_RING, Layout.RING_LANE, PathVehicle.CAR_TURN_RADIUS)
	car = Traffic.new()
	car.kind = &"gazelle"
	root.add_child(car)
	car.setup(lane, lane.offset_of(Vector3(73, 0, -35)))
	car.set_physics_process(false)
	car.global_position = Vector3(72.9745178, 0, -34.8646698)
	car.global_rotation.y = 0.6938788
	for spec in Layout.all_solids():
		if spec[1] == "snow_bank" and spec[2].x > 76 and absf(spec[2].y - car.global_position.z) < spec[3].z * 0.5:
			bank = obstacle(Vector3(spec[2].x, spec[3].y * 0.5, spec[2].y), spec[3], 64)
			break
	check(bank != null, "recorded pose has its canonical roadside snow bank")
	await physics_frame
	await physics_frame
	var forward := -car.global_basis.z
	check(not car.test_move(car.global_transform, forward * 0.6), "actual body has a collision-free forward sweep away from the bank")
	check(car.start_driving(&"race", null, [Vector3(73, 0, -80)]), "recorded pose accepts a reachable northbound checkpoint")
	check(not car.driver_ai._query_at(car.global_position, forward).is_empty(), "inflated sensor detects the existing rear-corner safety-margin overlap")
	check(car.driver_ai._query_at(car.global_position + forward * 0.6, forward).is_empty(), "forward swept sensor clears that margin on accessible pavement")
	var command: Dictionary = car.driver_ai.tick(1.0 / 60.0)
	print("DIAGNOSTIC " + str(command) + " blocks=" + str(car.driver_ai.route.get("_blocks")))
	check(float(command.target_speed) > 0.1, "receding roadside margin does not deadlock forward motion")
	check(car.driver_ai.route.get("_blocks").is_empty(), "roadside margin does not mark the accessible street as closed")
	var origin := car.global_position
	car.set_physics_process(true)
	for frame in 360: await physics_frame
	check(car.global_position.distance_to(origin) > 3.0, "actual consumer makes finite progress from the recorded pose")
	check(car.driver_ai.reverse_attempts <= AI.MAX_REVERSE_ATTEMPTS, "recovery keeps its finite reverse-attempt budget")
	car.set_physics_process(false)
	car.queue_free()
	bank.queue_free()
	await physics_frame
	await physics_frame
	car = null
	bank = null
	Meshes.cache().clear()
	print("DRIVER01_RECOVERY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
