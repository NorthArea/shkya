extends SceneTree
## Developer checks: impulse conservation and immutable shared vehicle geometry.

const Impact = preload("res://game/vehicles/vehicle_impact.gd")
const Damage = preload("res://game/vehicles/vehicle_damage.gd")
const Visual = preload("res://game/vehicles/lada_visual.gd")
const SIZE := Vector3(1.7, 1.4, 4.1)
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ma := 1000.0
	var mb := 2000.0
	var v := Vector3(12.0, 0.0, 0.0)
	var hit := Impact.solve(v, Vector3.ZERO, Vector3.LEFT, ma, mb, Vector3.ZERO, Vector3.ZERO, SIZE, SIZE)
	var after_a: Vector3 = v + hit["velocity_a"]
	var after_b: Vector3 = hit["velocity_b"]
	check((after_a * ma + after_b * mb).distance_to(v * ma) < 0.01, "finite-mass pair conserves linear momentum")
	check(after_a.length_squared() * ma + after_b.length_squared() * mb <= v.length_squared() * ma, "contact does not create kinetic energy")
	check(after_b.x > 0.0 and after_b.x < v.x, "heavy receiver accelerates in impact direction")
	var tangent := Impact.solve(Vector3(0, 0, 20), Vector3.ZERO, Vector3.LEFT, ma, mb, Vector3.ZERO, Vector3.ZERO, SIZE, SIZE)
	check(tangent["impulse"] == 0.0, "pure tangential motion has no impulse")
	var convoy := Impact.solve(v, v, Vector3.LEFT, ma, mb, Vector3.ZERO, Vector3.ZERO, SIZE, SIZE)
	check(convoy["impulse"] == 0.0, "matched velocity has no impact")
	var separating := Impact.solve(-v, Vector3.ZERO, Vector3.LEFT, ma, mb, Vector3.ZERO, Vector3.ZERO, SIZE, SIZE)
	check(separating["impulse"] == 0.0, "separating contact cannot add force")
	var offcenter := Impact.solve(v, Vector3.ZERO, Vector3.LEFT, ma, mb, Vector3(0, 0, 1.4), Vector3(0, 0, 1.4), SIZE, SIZE)
	check(absf(offcenter["yaw_a"]) > 0.05 and signf(offcenter["yaw_a"]) != signf(offcenter["yaw_b"]), "off-centre contact gives opposite angular impulses")
	var wall := Impact.solve(v, Vector3.ZERO, Vector3.LEFT, ma, 0.0, Vector3.ZERO, Vector3.ZERO, SIZE, SIZE)
	check((wall["velocity_b"] as Vector3).is_zero_approx() and (v + wall["velocity_a"]).x < 0.0, "fixed world stays fixed and car rebounds")
	var gentle := Impact.solve(Vector3(0.4, 0, 0), Vector3.ZERO, Vector3.LEFT, ma, mb, Vector3.ZERO, Vector3.ZERO, SIZE, SIZE)
	check(gentle["impulse"] > 0.0 and (gentle["velocity_b"] as Vector3).x > 0.0, "gentle approaching contact transfers momentum below cosmetic speed threshold")

	var first := Visual.build()
	var second := Visual.build()
	root.add_child(first)
	root.add_child(second)
	var first_part := first.get_node("Body/BodyMesh") as MeshInstance3D
	var second_part := second.get_node("Body/BodyMesh") as MeshInstance3D
	var shared := first_part.mesh
	check(shared == second_part.mesh, "undamaged instances use shared cached provider mesh")
	var front := Vector3(0.6, 0.65, -2.03)
	check(not Damage.dent(first, front, Vector3.BACK, gentle["impulse"] / Impact.DAMAGE_REFERENCE_MASS) and first_part.mesh == shared,
		"gentle solved impulse moves the finite receiver without deforming its shared body")
	check(not Damage.dent(first, front, Vector3.BACK, 1.0) and first_part.mesh == shared, "slow contact does not allocate or dent")
	check(Damage.dent(first, front, Vector3.BACK, 12.0), "front-quarter contact reaches body vertices")
	check(first_part.mesh != shared and second_part.mesh == shared, "damage mesh is private to impacted vehicle")
	var once := _displacement(first_part.mesh, shared)
	check(once > 0.01, "impact creates measurable vertex displacement")
	Damage.dent(first, front, Vector3.BACK, 12.0)
	var twice := _displacement(first_part.mesh, shared)
	check(twice > once, "second contact adds deformation at same panel")
	for i in 8:
		Damage.dent(first, front, Vector3.BACK, 28.0)
	check(_displacement(first_part.mesh, shared) <= Damage.MAX_DEPTH + 0.0001, "repeated dents stay within plastic depth bound")
	Damage.reset(first)
	check(first_part.mesh == shared and first.get_meta("vehicle_dent_count") == 0, "reset restores original mesh and damage counter")
	first.queue_free()
	second.queue_free()
	await process_frame
	print("VEHICLE_IMPACT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _displacement(mesh: Mesh, original: Mesh) -> float:
	var maximum := 0.0
	for s in mesh.get_surface_count():
		var a: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array = original.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for i in a.size():
			maximum = maxf(maximum, a[i].distance_to(b[i]))
	return maximum

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)
