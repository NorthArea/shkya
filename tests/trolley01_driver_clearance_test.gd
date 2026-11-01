extends SceneTree
## Real skinned occupant geometry in the production cabin factory, without Main.
const Cabin = preload("res://game/vehicles/trolley_cabin.gd")
const Clearance = preload("res://tests/skinned_clearance.gd")
const REQUIRED_CENTRELINE_DISTANCE := 0.023
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
func bounds(actor: Node3D, reference: Node3D, head_only := false) -> AABB:
	var visual: Node = actor.uniform_visual
	var skeleton: Skeleton3D = visual.skeleton
	var mesh: MeshInstance3D = visual.uniform_mesh
	var low := Vector3.INF
	var high := -Vector3.INF
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			var head := false
			var point := Vector3.ZERO
			for influence in 4:
				var slot := index * 4 + influence
				if weights[slot] <= 0.0: continue
				var bind := bones[slot]
				var bone := mesh.skin.get_bind_bone(bind)
				point += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[index]) * weights[slot]
				head = head or (skeleton.get_bone_name(bone) == "head" and weights[slot] > 0.5)
			if head_only and not head: continue
			point = reference.to_local(mesh.to_global(point))
			low = low.min(point)
			high = high.max(point)
	return AABB(low, high - low)
func _run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	var a := Vector3(-1, -1, 0)
	var b := Vector3(1, -1, 0)
	var c := Vector3(0, 1, 0)
	check(Clearance.segment_triangle_distance(Vector3(0, 0, -1), Vector3(0, 0, 1), a, b, c) == 0.0, "oracle catches segment crossing the triangle interior")
	check(absf(Clearance.segment_triangle_distance(Vector3(0, 0, 2), Vector3(0, 0, 3), a, b, c) - 2.0) < 0.00001, "oracle measures endpoint to triangle interior")
	check(absf(Clearance.segment_triangle_distance(Vector3(-2, 0, 1), Vector3(2, 0, 1), a, b, c) - 1.0) < 0.00001, "oracle measures closest edge to segment despite distant endpoints")
	check(absf(Clearance.segment_triangle_distance(Vector3(0, 0, 2), Vector3(0, 0, 3), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO) - 2.0) < 0.00001, "oracle handles a degenerate triangle")
	var cabin := Cabin.new()
	root.add_child(cabin)
	var driver: Node3D = cabin.driver
	var head := bounds(driver, cabin, true)
	var body := bounds(driver, cabin)
	print("TROLLEY01_DRIVER head=", head, " body=", body)
	var measurement := Clearance.mesh_wheel_clearance(driver, cabin)
	print("TROLLEY01_MESH_WHEEL ", measurement)
	check(measurement.minimum_centreline_distance >= REQUIRED_CENTRELINE_DISTANCE, "full skinned head clears the original steering wheel tube by 5mm")
	check(head.end.z < -4.6, "full skinned head clears the rear partition")
	check(body.position.y >= 0.79 and body.position.y <= 0.81, "driver remains on the original cabin floor")
	check(head.end.y > 2.12 and head.end.y < 2.87, "driver remains visible in the original window band")
	for suffix: String in ["_l", "_r"]:
		var visual: Node = driver.uniform_visual
		var hand: int = visual.skeleton.find_bone("hand" + suffix)
		var palm: Vector3 = visual.skeleton.get_bone_global_pose(hand) * Vector3(0, -0.034, -0.008)
		palm = cabin.to_local(visual.model.to_global(palm))
		var target := Vector3(-0.38 if suffix == "_l" else -0.82, 1.97, -5.35)
		print("TROLLEY01_PALM ", suffix, "=", palm, " target=", target)
		check(palm.distance_to(target) <= 0.04, "driver " + suffix + " palm retains its original steering grip")
	var worst_clearance := INF
	var worst_grip := 0.0
	for index in 31:
		cabin._turn = Cabin.DRIVER_TURN_3D * float(index) / 30.0
		cabin.tick(0.0, true)
		var sample := Clearance.mesh_wheel_clearance(driver, cabin)
		worst_clearance = minf(worst_clearance, sample.minimum_centreline_distance)
		check(sample.minimum_centreline_distance >= REQUIRED_CENTRELINE_DISTANCE, "head turn %d keeps 5mm between every head triangle and original wheel tube" % index)
		check(bounds(driver, cabin, true).end.z < -4.6, "head turn %d clears original rear partition" % index)
		for suffix: String in ["_l", "_r"]:
			var visual: Node = driver.uniform_visual
			var hand: int = visual.skeleton.find_bone("hand" + suffix)
			var point: Vector3 = visual.skeleton.get_bone_global_pose(hand) * Vector3(0, -0.034, -0.008)
			point = cabin.to_local(visual.model.to_global(point))
			var target := Vector3(-0.38 if suffix == "_l" else -0.82, 1.97, -5.35)
			worst_grip = maxf(worst_grip, point.distance_to(target))
	check(worst_grip <= 0.04, "turning only the head leaves both original steering grips intact")
	print("TROLLEY01_SWEEP centreline=", worst_clearance, " grip_error=", worst_grip)
	for rider: Node3D in cabin.shown():
		var box := bounds(rider, cabin)
		check(absf(box.position.y - 0.80) < 0.015, rider.name + " retains original floor placement")
	cabin.free()
	print("TROLLEY01_DRIVER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
