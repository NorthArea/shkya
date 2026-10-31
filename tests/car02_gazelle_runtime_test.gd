extends SceneTree
## CAR-02: common 2705 in the existing Main traffic; full C8 remains traffic_test.gd.
const Gazelle = preload("res://game/vehicles/gazelle_visual.gd")
const Traffic = preload("res://game/vehicles/traffic_car.gd")
const Impact = preload("res://game/vehicles/vehicle_impact.gd")
const OUT := "res://builds/checks/CAR-02/gazelle-runtime/result.json"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: ", message)
	return ok

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func():
		check(false, "runtime oracle exceeded 90 simulated seconds")
		finish())
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await frames(3)
	main.start_game()
	await frames(10)
	var world: DemoWorld = main.world
	var traffic: Node3D = world.get_node_or_null("LevelGeometry/Traffic")
	if not check(traffic != null, "actual Main constructs Traffic without test fallback"):
		finish()
		return
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	check(traffic.cars.size() == 3 and traffic.vehicles.size() == 4, "existing three cars and trolleybus, no added traffic")
	var matches: Array = traffic.cars.filter(func(car): return car.kind == &"gazelle")
	if not check(matches.size() == 1, "exactly one existing gazelle kind"):
		finish()
		return
	var car: TrafficCar = matches[0]
	check(car.size == Gazelle.SIZE and car.wheelbase == Gazelle.WHEELBASE and car.wheel_radius == Gazelle.WHEEL_RADIUS,
		"actual 2705 chassis dimensions and rolling radius follow common provider")
	var collider: CollisionShape3D = car.get_node("CollisionShape3D")
	check(collider.shape is BoxShape3D and collider.shape.size == Gazelle.SIZE
		and is_equal_approx(collider.position.y, Gazelle.SIZE.y * 0.5), "real collision box matches 2705 size and ground")
	check(car.path == traffic.car_path and car.path != traffic.path and car.cruise_speed == 9.0 and car.can_yield,
		"C8 keeps counterflow car lane, 9 m/s and yielding")
	check(car.peers == traffic.cars and not car.driver_ai.is_active(), "C8 retains existing peers and default lane driving")
	var body := car.visual.get_node("Body/BodyMesh") as MeshInstance3D
	var shared := Gazelle.body_meshes(Gazelle.CARGO)
	check(body.mesh == shared.body and car.visual.get_node("Body/Glass").mesh == shared.glass
		and car.visual.get_node("Body/Interior").mesh == shared.interior, "actual Main uses common cargo 2705 body/glass/interior")
	var reference := Gazelle.build(Color(0.9, 0.8, 0.2), "", 0.1)
	world.add_child(reference)
	reference.position = Vector3(1000, 0, 1000)
	var reference_body := reference.get_node("Body/BodyMesh") as MeshInstance3D
	var second := Traffic.new()
	second.kind = &"gazelle"
	second.position = Vector3(1100, 0, 1100)
	world.add_child(second)
	var second_body := second.visual.get_node("Body/BodyMesh") as MeshInstance3D
	var slots: Array = body.mesh.get_meta("slots", [])
	for slot in ["paint", "head", "tail", "lens_amber"]:
		var surface := slots.find(slot)
		if not check(surface >= 0, "runtime material slot " + slot):
			continue
		var material := body.get_surface_override_material(surface)
		check(material != null and material != second_body.get_surface_override_material(surface)
			and material != body.mesh.surface_get_material(surface), "runtime owns mutable " + slot + " material")
		if slot == "head":
			check(material is StandardMaterial3D and material.emission_enabled and material.emission_energy_multiplier > 1.0,
				"actual front lamps emit")
		elif slot == "tail":
			check(material == car._tail, "brake controller owns real rear lamp surface")
	var wheel_count := 0
	for child in car.visual.get_children():
		if not str(child.name).begins_with("WheelPivot"):
			continue
		var wheel := child.get_node("Wheel") as MeshInstance3D
		check(child.position == Gazelle.wheel_spots()[wheel_count], "actual wheel axle center %d" % wheel_count)
		check(wheel.mesh == Gazelle.wheel_mesh() and wheel in car._wheels, "shared wheel registered for motion %d" % wheel_count)
		check(absf(absf(wheel.basis.y.dot(Vector3.RIGHT)) - 1.0) < 0.00001, "wheel local UP is transverse spin axis %d" % wheel_count)
		wheel_count += 1
	check(wheel_count == 6 and car._wheels.size() == 6, "front pair and rear twins: all six wheels animate")
	var exhaust := car.visual.get_node_or_null("Exhaust") as CPUParticles3D
	check(exhaust != null and exhaust.emitting and not exhaust.local_coords, "world-space cold exhaust remains active")
	if exhaust != null:
		check(exhaust.position.distance_to(Vector3(-0.95, 0.255, 0.72)) < 0.08,
			"exhaust originates at actual common 2705 left-side pipe outlet")
		check(exhaust.direction.normalized().dot(Vector3(-0.25, 0.0, 0.12).normalized()) > 0.7,
			"exhaust flows outward along side pipe, away from vehicle")
	var adapter: Dictionary = car.get_meta(Impact.META, {})
	check(adapter.get("mass", 0.0) == 2100.0 and adapter.get("size", Vector3.ZERO) == Gazelle.SIZE
		and adapter.get("visual") == car.visual, "finite-mass adapter keeps 2100 kg with actual visual and new envelope")
	var previous_s := car.s
	var wheel_bases: Array[Basis] = []
	for wheel in car._wheels:
		wheel_bases.append(wheel.basis)
	await frames(120)
	check(car.global_transform.is_finite() and car.vehicle_velocity().is_finite() and car.distance_travelled > 1.0
		and absf(car.s - previous_s) > 1.0, "actual traffic advances on C8 route with finite motion")
	for i in car._wheels.size():
		check(not car._wheels[i].basis.is_equal_approx(wheel_bases[i]), "actual route movement spins wheel %d" % i)
	car.cruise_speed = 0.0
	await frames(180)
	check(car.speed < 0.05 and car._tail.emission_energy_multiplier > 3.0, "actual stop brightens rear brake lights")
	check(second._tail.emission_energy_multiplier < 1.0, "braking does not brighten another gazelle")
	car.cruise_speed = 9.0
	var original: ArrayMesh = body.mesh
	car.receive_vehicle_impact(Vector3(0.2, 0, 0), 0.02,
		body.to_global(Vector3(1.04, 0.95, 0.45)), -body.global_basis.x, 6.0, 8.0)
	check(car.impact_active and car.vehicle_velocity().is_finite() and is_finite(car.vehicle_yaw()),
		"actual traffic impact receiver enters finite physical response")
	check(body.mesh != original and reference_body.mesh == shared.body and second_body.mesh == original,
		"impact deforms only struck instance and leaves shared/provider meshes unchanged")
	check(body.mesh.get_meta("slots", []) == slots, "runtime dent preserves lamp slots")
	car.setup(traffic.car_path, previous_s)
	check(body.mesh == original and not car.impact_active and car.vehicle_velocity() == Vector3.ZERO,
		"existing setup resets physical response and restores shared undamaged body")
	check(traffic.cars.size() == 3 and traffic.vehicles.size() == 4, "integration preserves traffic population")
	reference.free()
	second.free()
	finish()

func finish() -> void:
	var report := {"checks": checks, "failures": failures,
		"scope": "actual Main 2705 provider/chassis/materials/wheels/route motion/impact-reset; full C8 uses traffic_test.gd; native review and FPS separate",
		"input_sha256": {}}
	for path in ["res://game/vehicles/traffic_car.gd", "res://game/vehicles/gazelle_visual.gd", "res://game/vehicles/path_vehicle.gd",
		"res://game/vehicles/vehicle_impact.gd", "res://game/vehicles/vehicle_damage.gd", "res://tests/car02_gazelle_runtime_test.gd"]:
		report.input_sha256[path] = FileAccess.get_sha256(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write GAZelle runtime report")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CAR02_GAZELLE_RUNTIME: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
