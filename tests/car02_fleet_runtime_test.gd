extends SceneTree
## CAR-02: two existing parked cars consume the common Niva/Samara providers.
const Layout = preload("res://game/world/layout.gd")
const Niva = preload("res://game/vehicles/niva_visual.gd")
const Samara = preload("res://game/vehicles/samara_visual.gd")
const Impact = preload("res://game/vehicles/vehicle_impact.gd")
const OUT := "res://builds/checks/CAR-02/parking-runtime/result.json"
var checks := 0
var failures: Array[String] = []
var main: Node

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

func parking_case(breakables: Node, id: StringName, provider: Script, expected_size: Vector3) -> void:
	var found: Array = breakables.objects.filter(func(b): return b.id == id)
	if not check(found.size() == 1, "%s has its existing unique breakable owner" % id):
		return
	var parked: Node = found[0]
	var visual: Node3D = parked.parked_visual
	if not check(visual != null, "%s has its actual registered visual" % id):
		return
	var spec: Array = Layout.SOLIDS.filter(func(s): return s[0] == String(id))[0]
	check(spec[3] == expected_size and parked.size == expected_size, "%s C1 and Breakable use real oriented provider dimensions" % id)
	var collider: CollisionShape3D = parked.body.get_child(0)
	check(collider.shape is BoxShape3D and collider.shape.size == expected_size
		and is_equal_approx(collider.position.y, expected_size.y * 0.5), "%s active physics box follows the new envelope" % id)
	check(not collider.disabled and parked.body.collision_layer == 33, "%s keeps World/Breakable collision layers" % id)
	var adapter: Dictionary = parked.body.get_meta(Impact.META, {})
	check(adapter.get("visual") == visual and adapter.get("size") == expected_size
		and adapter.get("mass") == 1045.0, "%s keeps the existing finite-mass parked adapter" % id)
	var body := visual.get_node("Body/BodyMesh") as MeshInstance3D
	var shared: Dictionary = provider.body_meshes()
	check(body.mesh == shared.body and visual.get_node("Body/Glass").mesh == shared.glass
		and visual.get_node("Body/Interior").mesh == shared.interior, "%s actual Main consumes shared body/glass/interior" % id)
	check(absf(visual.global_position.y) < 0.001 and visual.global_position.distance_to(parked.global_ground()) < 0.001,
		"%s provider wheels are grounded at the original parking center" % id)
	var wheel_count := 0
	for child in visual.get_children():
		if str(child.name).begins_with("WheelPivot"):
			var wheel: MeshInstance3D = child.get_node("Wheel")
			check(wheel.mesh == provider.wheel_mesh() and child.position == provider.wheel_spots()[wheel_count],
				"%s keeps provider axle center and shared wheel %d" % [id, wheel_count])
			wheel_count += 1
	check(wheel_count == 4, "%s has four existing provider wheels" % id)
	var reference: Node3D = provider.build(Color(0.3, 0.5, 0.8), "", 0.1)
	var reference_body := reference.get_node("Body/BodyMesh") as MeshInstance3D
	var slots: Array = body.mesh.get_meta("slots", [])
	var paint := slots.find("paint")
	check(body.get_surface_override_material(paint) != reference_body.get_surface_override_material(paint),
		"%s paint remains private to this parked instance" % id)
	var amber := slots.find("lens_amber")
	var indicator := visual.get_meta("indicator_material", null) as StandardMaterial3D
	check(indicator != null and amber >= 0 and body.get_surface_override_material(amber) == indicator,
		"%s alarm controls the actual amber lens surface" % id)
	var original_transform: Transform3D = parked.body.global_transform
	var original_mesh: Mesh = body.mesh
	parked.receive_vehicle_impact(Vector3(0.15, 0, 0), 0.02,
		body.to_global(Vector3(provider.SIZE.x * 0.5, 0.8, 0)), -body.global_basis.x, 3.0, 8.0)
	check(body.mesh != original_mesh and reference_body.mesh == shared.body, "%s impact dents only the parked instance" % id)
	check(indicator != null and indicator.emission_energy_multiplier > 0.0, "%s actual impact illuminates alarm lenses" % id)
	check(parked.parked_velocity.length() > 0.0 and absf(parked.parked_yaw_velocity) > 0.0,
		"%s registered receiver retains physical translation and yaw response" % id)
	breakables.reset_positions()
	check(body.mesh == original_mesh and parked.parked_velocity == Vector3.ZERO and parked.parked_yaw_velocity == 0.0,
		"%s existing reset restores shared undamaged mesh and stops movement" % id)
	check(parked.body.global_transform.is_equal_approx(original_transform)
		and (indicator == null or indicator.emission_energy_multiplier == 0.0), "%s reset restores its parking location and ends alarm" % id)
	reference.free()

func run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await frames(3)
	main.start_game()
	await frames(10)
	var world: DemoWorld = main.world
	var breakables: Node = world.get_node("LevelGeometry/Breakables")
	var traffic: Node = world.get_node("LevelGeometry/Traffic")
	var residents: Node = world.get_node("LevelGeometry/Residents")
	check(traffic.cars.size() == 3 and traffic.vehicles.size() == 4, "Main keeps three traffic cars and one trolleybus")
	var kinds: Array = traffic.cars.map(func(c): return c.kind)
	check(kinds.has(&"zhiguli") and kinds.has(&"volga") and kinds.has(&"gazelle"), "all three accepted traffic kinds remain")
	check(residents.residents.size() == 64, "Main keeps all 64 residents")
	var parked: Array = breakables.objects.filter(func(b): return b.kind == &"parked")
	check(parked.size() == Layout.PARKED.size() + 2, "two replacements add no parked cars")
	parking_case(breakables, &"Zhiguli_A", Niva, Vector3(Niva.SIZE.z, Niva.SIZE.y, Niva.SIZE.x))
	parking_case(breakables, &"Zhiguli_B", Samara, Samara.SIZE)
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", kind, true, false):
			audio.stop()
	main.queue_free()
	main = null
	await frames(4)
	# Match Main-test teardown: fixed-fps frames do not advance the audio thread's wall clock.
	OS.delay_msec(100)
	await process_frame
	var report := {"checks": checks, "failures": failures,
		"scope": "actual Main parking provider/physics/alarm/damage/reset/population; visual/FPS and full C7/C8 separate",
		"input_sha256": {}}
	for path in ["res://game/world/layout.gd", "res://game/world/level_geometry.gd", "res://game/world/breakables.gd",
		"res://game/vehicles/niva_visual.gd", "res://game/vehicles/samara_visual.gd", "res://tests/car02_fleet_runtime_test.gd"]:
		report.input_sha256[path] = FileAccess.get_sha256(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CAR02_FLEET_RUNTIME: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
