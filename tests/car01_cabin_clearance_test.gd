extends SceneTree
## Tests rendered body-space geometry against the exterior shell, not a virtual floor.
const Clearance = preload("res://tests/skinned_clearance.gd")
const Lada = preload("res://game/vehicles/lada_visual.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	var car := Lada.build()
	root.add_child(car)
	var driver: Node = car.get_node("Body/Driver")
	var visual: Node = driver.uniform_visual
	visual.skeleton.force_update_all_bone_transforms()
	var low := Vector3.INF
	var high := -Vector3.INF
	var outside_width := 0
	for surface in visual.uniform_mesh.mesh.get_surface_count():
		var arrays: Array = visual.uniform_mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			var posed := Vector3.ZERO
			for influence in 4:
				var slot := index * 4 + influence
				var bind := bones[slot]
				var bone: int = visual.uniform_mesh.skin.get_bind_bone(bind)
				posed += (visual.skeleton.get_bone_global_pose(bone) * visual.uniform_mesh.skin.get_bind_pose(bind) * vertices[index]) * weights[slot]
			posed = car.get_node("Body").to_local(visual.uniform_mesh.to_global(posed))
			low = low.min(posed)
			high = high.max(posed)
			var side_limit := lerpf(0.76, 0.645, clampf((posed.y - 0.98) / (1.40 - 0.98), 0, 1))
			if absf(posed.x) > side_limit: outside_width += 1
	print("CAR01_DRIVER_BOUNDS ", low, " .. ", high)
	check(low.y >= 0.31, "every actual skinned vertex stays above the exterior underbody and footwell")
	check(high.y <= 1.355 and high.y >= 1.20, "driver retains visible head below the roof lining")
	check(outside_width == 0, "driver stays inside cabin width")
	var player_spec: Dictionary = Lada.SEDANS[Lada.PLAYER_MODEL]
	var windscreen_bottom: Vector2 = player_spec["ws"][0]
	var wheel_centre := Vector3(-0.36, float(player_spec["belt"]) + 0.13, windscreen_bottom.y + 0.30)
	var clearance := Clearance.mesh_wheel_clearance(driver, car.get_node("Body"), wheel_centre, Vector3(0, 0.87, -0.50), 0.18, 0.014)
	print("CAR01_HEAD_WHEEL ", clearance)
	check(clearance.head_triangles > 0 and clearance.minimum_centreline_distance >= 0.019, "full skinned Ilyusha head clears the original steering wheel tube by 5mm")
	for model: StringName in Lada.SEDANS:
		var spec: Dictionary = Lada.SEDANS[model]
		var body: Mesh = Lada.sedan_meshes(model)["body"]
		var slab_triangles := 0
		var roof_triangles := 0
		var hood_triangles := 0
		var boot_triangles := 0
		var interior_floor := INF
		for surface in body.get_surface_count():
			if body.get_meta("slots")[surface] != "paint":
				continue
			var vertices: PackedVector3Array = body.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for index in range(0, vertices.size(), 3):
				var a := vertices[index]
				var b := vertices[index + 1]
				var c := vertices[index + 2]
				var centre := (a + b + c) / 3.0
				if absf(centre.x) < 0.6 and absf(centre.z) < 0.6 and centre.y > 1.38:
					roof_triangles += 1
				if centre.z < -1.30 and centre.y > 0.85: hood_triangles += 1
				if centre.z > 1.30 and centre.y > 0.85: boot_triangles += 1
				if centre.z > -0.60 and centre.z < 0.60 and absf(centre.x) < 0.6 and centre.y > 0.90 and centre.y < 1.05:
					slab_triangles += 1
		check(slab_triangles == 0, String(model) + " has no painted lid through the middle of the cabin: %d" % slab_triangles)
		check(roof_triangles > 0 and hood_triangles > 0 and boot_triangles > 0, String(model) + " retains the roof, bonnet and boot around its open cabin")
		var interior: Mesh = Lada.sedan_meshes(model)["interior"]
		for surface in interior.get_surface_count():
			var vertices: PackedVector3Array = interior.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point in vertices:
				interior_floor = minf(interior_floor, point.y)
		check(interior_floor >= 0.30, String(model) + " cabin floor is inside the exterior body")
	car.free()
	print("CAR01_CABIN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
