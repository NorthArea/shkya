extends SceneTree
## Developer oracle for the common GAZelle provider; no traffic/mission/render acceptance.
const Gazelle = preload("res://game/vehicles/gazelle_visual.gd")
const Damage = preload("res://game/vehicles/vehicle_damage.gd")
const OUT := "res://builds/checks/CAR-02/gazelle-stand/developer_result.json"
const EPS := 0.00001
var checks := 0
var failures: Array[String] = []
var report := {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: ", message)

func points(mesh: ArrayMesh, surface: int = -1) -> PackedVector3Array:
	var result := PackedVector3Array()
	for s in mesh.get_surface_count():
		if surface >= 0 and surface != s:
			continue
		result.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	return result

func bounds(vertices: PackedVector3Array) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for p in vertices:
		low = low.min(p)
		high = high.max(p)
	return AABB(low, high - low)

func all_points(node: Node3D, into: PackedVector3Array, parent := Transform3D.IDENTITY) -> void:
	var xf: Transform3D = parent * node.transform
	if node is MeshInstance3D:
		for v in points(node.mesh):
			into.append(xf * v)
	for child in node.get_children():
		if child is Node3D:
			all_points(child, into, xf)

func mesh_check(mesh: ArrayMesh, label: String) -> void:
	var invalid := 0
	var degenerate := 0
	var total := 0
	for s in mesh.get_surface_count():
		check(mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES, label + ": triangle surface")
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in vertices:
			if not v.is_finite():
				invalid += 1
		for n in arrays[Mesh.ARRAY_NORMAL]:
			if not n.is_finite() or n.length_squared() < 0.25:
				invalid += 1
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		check(indices.size() % 3 == 0, label + ": complete triangles")
		for i in range(0, indices.size() - 2, 3):
			var a := indices[i]
			var b := indices[i + 1]
			var c := indices[i + 2]
			if mini(a, mini(b, c)) < 0 or maxi(a, maxi(b, c)) >= vertices.size():
				invalid += 1
				continue
			if (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length_squared() <= 1.0e-20:
				degenerate += 1
			total += 1
	check(total > 0 and invalid == 0 and degenerate == 0, label + ": real finite geometry, nonzero normals, valid triangles")
	var actual := bounds(points(mesh))
	check(mesh.get_aabb().position.distance_to(actual.position) < EPS and mesh.get_aabb().end.distance_to(actual.end) < EPS,
		label + ": measured vertices equal mesh bounds")

func intersects(mesh: ArrayMesh, from: Vector3, to: Vector3) -> bool:
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		for i in range(0, indices.size() - 2, 3):
			if Geometry3D.segment_intersects_triangle(from, to,
				vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]]) != null:
				return true
	return false

func provider_check(model: StringName) -> void:
	var name_ := "GAZ-" + str(model)
	var a := Gazelle.build(Color(0.75, 0.22, 0.18), "", 0.0, model)
	var b := Gazelle.build(Color(0.15, 0.35, 0.55), "", 0.0, model)
	var equal_paint := Gazelle.build(Color(0.75, 0.22, 0.18), "", 0.0, model)
	var snowy := Gazelle.build(Color(0.75, 0.22, 0.18), "", 0.08, model)
	root.add_child(a)
	root.add_child(b)
	root.add_child(equal_paint)
	root.add_child(snowy)
	var body := a.get_node("Body/BodyMesh") as MeshInstance3D
	var body_b := b.get_node("Body/BodyMesh") as MeshInstance3D
	var body_equal := equal_paint.get_node("Body/BodyMesh") as MeshInstance3D
	for part in ["BodyMesh", "Glass", "Interior"]:
		check(a.get_node("Body/" + part).mesh == b.get_node("Body/" + part).mesh
			and a.get_node("Body/" + part).mesh == equal_paint.get_node("Body/" + part).mesh
			and a.get_node("Body/" + part).mesh == snowy.get_node("Body/" + part).mesh,
			name_ + ": geometry cached across paint/snow " + part)
		mesh_check(a.get_node("Body/" + part).mesh, name_ + "/" + part)
	var slots: Array = body.mesh.get_meta("slots", [])
	for slot in ["paint", "head", "tail", "lens_amber"]:
		var index := slots.find(slot)
		check(index >= 0, name_ + ": real surface slot " + slot)
		if index < 0:
			continue
		var material := body.get_surface_override_material(index)
		check(material != null and material != body_b.get_surface_override_material(index)
			and material != body_equal.get_surface_override_material(index)
			and material != body.mesh.surface_get_material(index), name_ + ": per-instance mutable material " + slot)
		var envelope := bounds(points(body.mesh, index))
		if slot == "head":
			check(envelope.end.z < -2.60 and envelope.position.y > 0.8 and envelope.end.y < 1.08,
				name_ + ": head slot belongs to actual front lamps")
		elif slot == "tail":
			check(envelope.position.z > 2.62 and envelope.position.y > 0.4 and envelope.end.y < 1.28,
				name_ + ": tail slot belongs to actual rear lamps")
		elif slot == "lens_amber":
			check(envelope.position.z < -2.60 and envelope.end.z > 2.64,
				name_ + ": amber slot contains both front and rear signals")
		elif slot == "paint":
			check(absf(envelope.size.x - 2.075) < 0.025, name_ + ": measured metal width excludes mirrors")
			var paint := material as ShaderMaterial
			var other_paint := body_b.get_surface_override_material(index) as ShaderMaterial
			var same_paint := body_equal.get_surface_override_material(index) as ShaderMaterial
			var untouched: Color = other_paint.get_shader_parameter("paint")
			var same_untouched: Color = same_paint.get_shader_parameter("paint")
			paint.set_shader_parameter("paint", Color.MAGENTA)
			check(other_paint.get_shader_parameter("paint") == untouched
				and same_paint.get_shader_parameter("paint") == same_untouched,
				name_ + ": mutating paint leaves next vehicle unchanged")
	var vertices := PackedVector3Array()
	all_points(a, vertices)
	var full := bounds(vertices)
	check(absf(full.position.y) < EPS and absf(full.end.y - 2.2) < 0.012, name_ + ": ground contact and real unsnowed roof height")
	check(absf(full.size.z - 5.47) < 0.012, name_ + ": actual bumper-to-bumper length")
	check(full.size.x > 2.075 and full.size.x < 2.5, name_ + ": full measured width includes mirrors")
	var spots: Array[Vector3] = []
	for child in a.get_children():
		if not str(child.name).begins_with("WheelPivot"):
			continue
		spots.append(child.position)
		var wheel := child.get_node("Wheel") as MeshInstance3D
		check(wheel.mesh == Gazelle.wheel_mesh(), name_ + ": cached tyre/rim mesh")
		check(absf(absf(wheel.basis.y.dot(Vector3.RIGHT)) - 1.0) < EPS, name_ + ": wheel spin axis transverse")
		var radius := 0.0
		for v in points(wheel.mesh):
			radius = maxf(radius, Vector2(v.x, v.z).length())
		check(absf(radius - 0.34195) < EPS and absf(child.position.y - radius) < EPS,
			name_ + ": actual 185/75 R16C radius and contact height")
		var centre: Vector3 = child.position
		wheel.rotate_object_local(Vector3.UP, 0.73)
		check(child.position == centre and wheel.position == Vector3.ZERO, name_ + ": local spin preserves axle centre")
	check(spots.size() == 6 and spots == Gazelle.wheel_spots(), name_ + ": two front tyres and four rear tyres use public spots")
	if spots.size() == 6:
		check(absf(spots[1].x - spots[0].x - 1.7) < EPS, name_ + ": measured front track")
		check(absf(spots[2].z - spots[0].z - 2.9) < EPS, name_ + ": measured wheelbase")
		check(absf((spots[4].x + spots[5].x - spots[2].x - spots[3].x) * 0.5 - 1.56) < EPS,
			name_ + ": rear track measured between paired-tyre midpoints")
		check(absf(absf(spots[3].x - spots[2].x) - 0.204) < EPS, name_ + ": rear twins separate tyre sidewalls")
	for side in [-1.0, 1.0]:
		for z in [0.205, 1.30, 2.15]:
			check(intersects(body.mesh, Vector3(side * 1.4, 1.665, z), Vector3(side * 0.88, 1.665, z)) == (model == Gazelle.CARGO),
				name_ + ": metal cargo side / true passenger opening at " + str(Vector2(side, z)))
	# Rays cross the seat volume below the windows. A closed lower hull adds a
	# painted, snow-receiving lid here even though window-opening tests pass.
	for x in [-0.60, 0.0, 0.60]:
		for z in [-1.30, -1.0, -0.75]:
			check(not intersects(body.mesh, Vector3(x, 1.30, z), Vector3(x, 1.09, z)),
				name_ + ": no painted shelf through cabin seats at " + str(Vector2(x, z)))
		for z in [-2.30, -2.08]:
			check(intersects(body.mesh, Vector3(x, 1.50, z), Vector3(x, 0.90, z)),
				name_ + ": removing cabin lid preserves closed hood at " + str(Vector2(x, z)))
	for side in [-1.0, 1.0]:
		for z in [-1.0, -0.75]:
			check(intersects(body.mesh, Vector3(side * 1.20, 0.95, z), Vector3(side * 0.85, 0.95, z)),
				name_ + ": removing cabin lid preserves lower door skin at " + str(Vector2(side, z)))
	check(a.get_node_or_null("Body/Snow") == null and snowy.get_node_or_null("Body/Snow") != null,
		name_ + ": snow is optional separate geometry")
	var original := body.mesh as ArrayMesh
	var before := points(original)
	check(Damage.dent(a, Vector3(1.04, 0.95, 0.45), Vector3.LEFT, 12.0), name_ + ": shared deformation API changes struck panel")
	check(body.mesh != original and body_b.mesh == original and points(original) == before,
		name_ + ": dent duplicates only hit instance, cached vertices immutable")
	check(body.mesh.get_meta("slots", []) == slots, name_ + ": deformation preserves material/lamp slots")
	var after := points(body.mesh)
	var largest := 0.0
	for i in before.size():
		largest = maxf(largest, before[i].distance_to(after[i]))
	check(largest > 0.001 and largest <= Damage.MAX_DEPTH + EPS, name_ + ": measurable bounded deformation")
	Damage.reset(a)
	check(body.mesh == original, name_ + ": reset restores shared original mesh")
	report[str(model)] = {"bounds": str(full), "wheel_centres": str(spots), "slots": slots, "max_dent": largest}
	a.free()
	b.free()
	equal_paint.free()
	snowy.free()

func door_state_check() -> void:
	var closed := Gazelle.body_meshes(Gazelle.PASSENGER)
	var opened := Gazelle.body_meshes(Gazelle.PASSENGER, true)
	check(Gazelle.body_meshes(Gazelle.PASSENGER).body == closed.body,
		"opening passenger door leaves default closed shared mesh untouched")
	check(opened.body != closed.body and opened.glass != closed.glass and opened.interior == closed.interior,
		"door state changes shell/glass, preserves shared cabin")
	check(Gazelle.body_meshes(Gazelle.PASSENGER, true).body == opened.body,
		"open passenger door state is cached across vehicles")
	mesh_check(opened.body, "32213 open door body")
	mesh_check(opened.glass, "32213 open door glass")
	for y in [0.92, 1.0, 1.23, 1.35, 1.6, 1.7, 1.9]:
		for z in [-0.2, 0.1, 0.3, 0.5, 0.65]:
			var from := Vector3(1.30, y, z)
			var to := Vector3(Gazelle.HALF_WIDTH - 0.16, y, z)
			check(not intersects(opened.body, from, to) and not intersects(opened.glass, from, to),
				"open side door has actual clear shell/glass aperture at %.2f/%.2f" % [y, z])
			check(intersects(closed.body, from, to) or intersects(closed.glass, from, to),
				"same ray reaches closed passenger door at %.2f/%.2f" % [y, z])
	check(intersects(opened.body, Vector3(1.30, 1.23, 1.7), Vector3(1.02, 1.23, 1.7)),
		"opened metal panel remains present, slid rearward outside right side")
	check(intersects(opened.glass, Vector3(1.30, 1.6, 1.7), Vector3(1.02, 1.6, 1.7)),
		"opened glass moves with the actual door")
	check(intersects(opened.glass, Vector3(-1.30, 1.6, 0.3), Vector3(-0.955, 1.6, 0.3)),
		"left passenger window remains closed")

func run() -> void:
	door_state_check()
	for model in [Gazelle.CARGO, Gazelle.PASSENGER, Gazelle.AMBULANCE]:
		provider_check(model)
	mesh_check(Gazelle.wheel_mesh(), "shared six tyres")
	var bus := Gazelle.body_meshes(Gazelle.PASSENGER)
	var medical := Gazelle.body_meshes(Gazelle.AMBULANCE)
	check(bus.body == medical.body and bus.glass == medical.glass and bus.interior != medical.interior,
		"ordinary 32214 shares standard windowed body/glass, with medical interior")
	check(Gazelle.body_meshes().body != bus.body, "2705 solid side and 32213 windowed shell are different real body variants")
	report["scope"] = "developer geometry/cache/material/deformation oracle; traffic, mission door, visual review and FPS require integrator acceptance"
	report["checks"] = checks
	report["failures"] = failures
	report["input_sha256"] = {}
	for path in ["res://game/vehicles/gazelle_visual.gd", "res://game/vehicles/vehicle_mesh.gd", "res://game/vehicles/vehicle_damage.gd", "res://tests/car02_gazelle_test.gd"]:
		report.input_sha256[path] = FileAccess.get_sha256(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write GAZelle developer report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CAR02_GAZELLE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
