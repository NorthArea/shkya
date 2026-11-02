extends SceneTree
## Independent CAR-02 provider oracle. Run only by the integrator.
## Reads generated vertices, not declared SIZE/AABB alone. This does not accept game-world routes.
const GAZ = preload("res://game/vehicles/gaz3110_visual.gd")
const SAMARA = preload("res://game/vehicles/samara_visual.gd")
const Traffic = preload("res://game/vehicles/traffic_car.gd")
const OUT := "res://builds/checks/CAR-02/families/result.json"
const EPS := 0.00001
const DIM_EPS := 0.012 # mesh detail allowance, metres; mirrors measured separately
const TRI_CROSS_SQ_MIN := 1.0e-20
var checks := 0
var failures: Array[String] = []
var report := {}
var inspected := {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: ", message)

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func mesh_check(mesh: ArrayMesh, label: String) -> void:
	if inspected.has(mesh.get_instance_id()):
		return
	inspected[mesh.get_instance_id()] = true
	var stats := {"vertices": 0, "triangles": 0, "bad_vertices": 0, "bad_normals": 0,
		"bad_uv": 0, "bad_indices": 0, "degenerate": 0, "non_triangles": 0}
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			stats.non_triangles += 1
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		stats.vertices += vertices.size()
		for v in vertices:
			if not v.is_finite():
				stats.bad_vertices += 1
			else:
				low = low.min(v)
				high = high.max(v)
		if arrays[Mesh.ARRAY_NORMAL] != null:
			for normal in arrays[Mesh.ARRAY_NORMAL]:
				if not normal.is_finite() or normal.length_squared() < 0.25:
					stats.bad_normals += 1
		for channel in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			if arrays[channel] != null:
				for uv in arrays[channel]:
					if not uv.is_finite():
						stats.bad_uv += 1
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		if indices.size() % 3 != 0:
			stats.bad_indices += 1
		for i in range(0, indices.size() - 2, 3):
			var valid := true
			for j in 3:
				valid = valid and indices[i + j] >= 0 and indices[i + j] < vertices.size()
			if not valid:
				stats.bad_indices += 1
				continue
			var a: Vector3 = vertices[indices[i]]
			var b: Vector3 = vertices[indices[i + 1]]
			var c: Vector3 = vertices[indices[i + 2]]
			if (b - a).cross(c - a).length_squared() <= TRI_CROSS_SQ_MIN:
				stats.degenerate += 1
			stats.triangles += 1
	check(stats.vertices > 0 and stats.triangles > 0, label + ": real triangle geometry exists")
	check(stats.bad_vertices == 0 and stats.bad_normals == 0 and stats.bad_uv == 0, label + ": finite positions/normals/UVs with nonzero normals")
	check(stats.bad_indices == 0 and stats.degenerate == 0 and stats.non_triangles == 0, label + ": valid indices and no degenerate triangles")
	check(mesh.get_aabb().position.distance_to(low) < EPS and mesh.get_aabb().end.distance_to(high) < EPS,
		label + ": declared AABB agrees with all actual vertices")
	stats["min"] = vec(low)
	stats["max"] = vec(high)
	report[label] = stats

func collect(node: Node, parent_transform: Transform3D, points: Array[Vector3], label: String) -> void:
	check(not (node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D), label + ": visual has no hidden physics at " + str(node.name))
	check(node.get_script() == null, label + ": returned visual node has no hidden script at " + str(node.name))
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * node.transform
	if node is MeshInstance3D:
		check(node.mesh is ArrayMesh, label + ": mesh is inspectable ArrayMesh")
		if node.mesh is ArrayMesh:
			mesh_check(node.mesh, label + "/" + str(node.name))
			for surface in node.mesh.get_surface_count():
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				for point in arrays[Mesh.ARRAY_VERTEX]:
					points.append(transform * point)
	for child in node.get_children():
		collect(child, transform, points, label)

func bounds(points: Array[Vector3]) -> Dictionary:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for p in points:
		low = low.min(p)
		high = high.max(p)
	return {"min": low, "max": high, "size": high - low}

func provider_check(provider: Script, name_: String, expected: Vector3, base: float, front_track: float, rear_track: float, radius: float) -> void:
	var color_a := Color(0.8, 0.2, 0.12)
	var color_b := Color(0.1, 0.3, 0.6)
	var a: Node3D = provider.build(color_a, "", 0.0)
	var b: Node3D = provider.build(color_b, "", 0.0)
	var c: Node3D = provider.build(color_a, "", 0.0)
	var snowy: Node3D = provider.build(color_b, "", 0.08)
	var points: Array[Vector3] = []
	collect(a, Transform3D.IDENTITY, points, name_)
	var full := bounds(points)
	check(absf(full.size.z - expected.z) <= DIM_EPS, name_ + ": actual full length matches dimension table")
	check(absf(full.min.y) <= EPS and absf(full.max.y - expected.y) <= DIM_EPS, name_ + ": tyres touch zero and full unsnowed height matches dimension table")
	check(full.size.x > expected.x and full.size.x < expected.x + 0.4, name_ + ": mirrors included in full measured width")
	var paint_points: Array[Vector3] = []
	var body_a := a.get_node("Body/BodyMesh") as MeshInstance3D
	var body_b := b.get_node("Body/BodyMesh") as MeshInstance3D
	var body_c := c.get_node("Body/BodyMesh") as MeshInstance3D
	var slots: Array = body_a.mesh.get_meta("slots", [])
	var paint_slot := slots.find("paint")
	check(paint_slot >= 0, name_ + ": named paint slot exists")
	if paint_slot >= 0:
		var arrays: Array = body_a.mesh.surface_get_arrays(paint_slot)
		for point in arrays[Mesh.ARRAY_VERTEX]:
			paint_points.append(body_a.transform * point)
		var painted := bounds(paint_points)
		check(absf(painted.size.x - expected.x) <= DIM_EPS, name_ + ": real painted envelope width excludes mirrors and matches table")
		var ma := body_a.get_surface_override_material(paint_slot) as ShaderMaterial
		var mb := body_b.get_surface_override_material(paint_slot) as ShaderMaterial
		var mc := body_c.get_surface_override_material(paint_slot) as ShaderMaterial
		check(ma != null and mb != null and mc != null and ma != mb and ma != mc and mb != mc,
			name_ + ": paint materials isolated even for equal paint inputs")
		if ma and mb and mc:
			var old_b: Color = mb.get_shader_parameter("paint")
			var old_c: Color = mc.get_shader_parameter("paint")
			var base_material := body_a.mesh.surface_get_material(paint_slot) as ShaderMaterial
			var old_base: Color = base_material.get_shader_parameter("paint")
			ma.set_shader_parameter("paint", Color(1, 0, 1))
			check(mb.get_shader_parameter("paint") == old_b and mc.get_shader_parameter("paint") == old_c
				and base_material.get_shader_parameter("paint") == old_base,
				name_ + ": mutating paint does not recolour other instances or cached mesh")
			ma.set_shader_parameter("paint", color_a)
	for part in ["BodyMesh", "Glass", "Interior"]:
		check(a.get_node("Body/" + part).mesh == b.get_node("Body/" + part).mesh
			and a.get_node("Body/" + part).mesh == c.get_node("Body/" + part).mesh
			and a.get_node("Body/" + part).mesh == snowy.get_node("Body/" + part).mesh,
			name_ + ": cache shares " + part + " across colours and snow")
	var wheel_nodes: Array[Node3D] = []
	for child in a.get_children():
		if str(child.name).begins_with("WheelPivot"):
			wheel_nodes.append(child)
	check(wheel_nodes.size() == 4, name_ + ": four native wheel pivots")
	var centres: Array[Vector3] = []
	for pivot in wheel_nodes:
		centres.append(pivot.position)
		var wheel := pivot.get_node("Wheel") as MeshInstance3D
		check(wheel.mesh == provider.wheel_mesh(), name_ + ": each wheel shares provider cached mesh")
		check(absf(absf(wheel.basis.y.dot(Vector3.RIGHT)) - 1.0) < EPS, name_ + ": local UP spin axis is transverse")
		var radial_max := 0.0
		for surface in wheel.mesh.get_surface_count():
			var arrays: Array = wheel.mesh.surface_get_arrays(surface)
			for v in arrays[Mesh.ARRAY_VERTEX]:
				radial_max = maxf(radial_max, Vector2(v.x, v.z).length())
		check(absf(radial_max - radius) < EPS and absf(pivot.position.y - radial_max) < EPS,
			name_ + ": actual tyre radius and centre height match the tyre size")
		var before := pivot.position
		wheel.rotate_object_local(Vector3.UP, 0.6)
		check(pivot.position == before and wheel.position == Vector3.ZERO,
			name_ + ": native local-UP rotation spins at fixed axle centre")
	if centres.size() == 4:
		centres.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.z < q.z if absf(p.z - q.z) > EPS else p.x < q.x)
		check(absf(centres[2].z - centres[0].z - base) < EPS, name_ + ": actual wheelbase matches table")
		check(absf(centres[1].x - centres[0].x - front_track) < EPS
			and absf(centres[3].x - centres[2].x - rear_track) < EPS, name_ + ": both actual tracks match table")
	var snow_points: Array[Vector3] = []
	collect(snowy, Transform3D.IDENTITY, snow_points, name_ + "_snow")
	var snow_bounds := bounds(snow_points)
	report[name_ + "_bounds"] = {"full_min": vec(full.min), "full_max": vec(full.max), "full_size": vec(full.size),
		"nominal_size": vec(expected), "wheel_centres": centres.map(func(p: Vector3) -> Array: return vec(p)),
		"snow_full_size": vec(snow_bounds.size), "body_mesh_id": body_a.mesh.get_instance_id()}
	a.free()
	b.free()
	c.free()
	snowy.free()

func traffic_assembly_check() -> void:
	var car := Traffic.new()
	car.kind = &"volga"
	root.add_child(car)
	car.set_physics_process(false)
	var body := car.visual.get_node("Body/BodyMesh") as MeshInstance3D
	var slots: Array = body.mesh.get_meta("slots", [])
	check(body.mesh == GAZ.body_meshes()["body"], "traffic volga: actual initialized consumer uses common GAZ body")
	check(slots.has("head") and slots.has("tail"), "traffic volga: actual head/tail slot names exist")
	if slots.has("head") and slots.has("tail"):
		check(body.get_surface_override_material(slots.find("head")) is StandardMaterial3D,
			"traffic volga: head lamp override attached")
		check(body.get_surface_override_material(slots.find("tail")) == car.get("_tail"),
			"traffic volga: rear override is the PathVehicle braking material")
	var wheels: Array = car.get("_wheels")
	check(wheels.size() == 4, "traffic volga: PathVehicle registers all four wheel meshes")
	for wheel in wheels:
		check(wheel is MeshInstance3D and wheel.mesh == GAZ.wheel_mesh()
			and absf(absf(wheel.basis.y.dot(Vector3.RIGHT)) - 1.0) < EPS,
			"traffic volga: registered wheel has shared mesh and local-UP transverse axle")
	report["traffic_assembly_scope"] = "real TrafficCar._ready composition only; no route, braking-in-motion, render or game-world acceptance"
	car.free()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	provider_check(GAZ, "gaz3110", Vector3(1.8, 1.455, 4.88), 2.8, 1.5, 1.444, 0.31725)
	provider_check(SAMARA, "samara", Vector3(1.65, 1.402, 4.006), 2.46, 1.4, 1.37, 0.2876)
	traffic_assembly_check()
	report["engine"] = Engine.get_version_info()
	report["checks"] = checks
	report["failures"] = failures
	report["scope"] = "generated geometry, shared resources, isolated paint, wheel frames and initialized traffic assembly; no game-world motion acceptance"
	var hashes := {}
	for path in ["res://game/vehicles/gaz3110_visual.gd", "res://game/vehicles/samara_visual.gd", "res://game/vehicles/traffic_car.gd", "res://game/vehicles/path_vehicle.gd", "res://game/vehicles/vehicle_mesh.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	report["input_sha256"] = hashes
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CAR02_INDEPENDENT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
