extends SceneTree
## Real skinned occupant geometry in the production cabin factory, without Main.
const Cabin = preload("res://game/vehicles/trolley_cabin.gd")
const Clearance = preload("res://tests/skinned_clearance.gd")
const Driver = preload("res://game/vehicles/lada_driver.gd")
const Trolley = preload("res://game/vehicles/trolleybus.gd")
const REQUIRED_CENTRELINE_DISTANCE := 0.023
# ЗиУ-682Б primary technical description: floor720mm, clear interior2008mm.
# https://djvu.online/jpg/G/1/X/G1Xtg92LGghnn/007.webp
# Actual factory test; the separate CHAR07 .80m passenger is a synthetic fixture.
const FLOOR_M := 0.720
const CEILING_M := FLOOR_M + 2.008
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
	_actual_steering_ring()
	var driver: Node3D = cabin.driver
	var head := bounds(driver, cabin, true)
	var body := bounds(driver, cabin)
	print("TROLLEY01_DRIVER head=", head, " body=", body)
	var measurement := Clearance.mesh_wheel_clearance(driver, cabin, Driver.TROLLEY_STEERING_AT)
	print("TROLLEY01_MESH_WHEEL ", measurement)
	check(measurement.minimum_centreline_distance >= REQUIRED_CENTRELINE_DISTANCE, "full skinned head clears the original steering wheel tube by 5mm")
	check(head.end.z < -4.6, "full skinned head clears the rear partition")
	check(absf(body.position.y - FLOOR_M) <= 0.01, "driver remains on the sourced actual cabin floor")
	check(head.end.y > 2.12 and head.end.y < CEILING_M, "driver remains visible below the sourced actual ceiling")
	for suffix: String in ["_l", "_r"]:
		var visual: Node = driver.uniform_visual
		var hand: int = visual.skeleton.find_bone("hand" + suffix)
		var palm: Vector3 = visual.skeleton.get_bone_global_pose(hand) * Vector3(0, -0.034, -0.008)
		palm = cabin.to_local(visual.model.to_global(palm))
		var target: Vector3 = Driver.TROLLEY_GRIPS[0 if suffix == "_l" else 1]
		print("TROLLEY01_PALM ", suffix, "=", palm, " target=", target)
		check(palm.distance_to(target) <= 0.04, "driver " + suffix + " palm retains its original steering grip")
	var worst_clearance := INF
	var worst_grip := 0.0
	for index in 31:
		cabin._turn = Cabin.DRIVER_TURN_3D * float(index) / 30.0
		cabin.tick(0.0, true)
		var sample := Clearance.mesh_wheel_clearance(driver, cabin, Driver.TROLLEY_STEERING_AT)
		worst_clearance = minf(worst_clearance, sample.minimum_centreline_distance)
		check(sample.minimum_centreline_distance >= REQUIRED_CENTRELINE_DISTANCE, "head turn %d keeps 5mm between every head triangle and original wheel tube" % index)
		check(bounds(driver, cabin, true).end.z < -4.6, "head turn %d clears original rear partition" % index)
		for suffix: String in ["_l", "_r"]:
			var visual: Node = driver.uniform_visual
			var hand: int = visual.skeleton.find_bone("hand" + suffix)
			var point: Vector3 = visual.skeleton.get_bone_global_pose(hand) * Vector3(0, -0.034, -0.008)
			point = cabin.to_local(visual.model.to_global(point))
			var target: Vector3 = Driver.TROLLEY_GRIPS[0 if suffix == "_l" else 1]
			worst_grip = maxf(worst_grip, point.distance_to(target))
	check(worst_grip <= 0.04, "turning only the head leaves both original steering grips intact")
	print("TROLLEY01_SWEEP centreline=", worst_clearance, " grip_error=", worst_grip)
	for rider: Node3D in cabin.shown():
		var box := bounds(rider, cabin)
		check(absf(box.position.y - FLOOR_M) < 0.015, rider.name + " retains sourced actual floor placement")
	cabin.free()
	print("TROLLEY01_DRIVER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _actual_steering_ring() -> void:
	# Location follows the accepted cabin contract; shape and physical presence
	# are checked against the actual full bus factory, not a virtual test ring.
	var factory := Trolley.new()
	var mesh: Mesh = factory._meshes()["interior"]
	var vertices := PackedVector3Array()
	for surface in mesh.get_surface_count():
		if mesh.get_meta("slots")[surface] != "dark": continue
		vertices.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	var present := true
	for index in 12:
		var angle := TAU * index / 12.0
		var centreline := Driver.TROLLEY_STEERING_AT + (Vector3.RIGHT * cos(angle) + Vector3(0, .35, -.94) * sin(angle)) * .24
		var nearest := INF
		for point in vertices: nearest = minf(nearest, point.distance_to(centreline))
		present = present and nearest <= .019
	check(present, "actual full bus mesh retains all12 ring sections at the accepted steering location with original18mm tube")
	factory.free()
