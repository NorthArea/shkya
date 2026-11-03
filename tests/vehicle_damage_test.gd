extends SceneTree
## Quality oracle against the pre-optimization deformation; renderer packing has a bounded tolerance.
const Damage = preload("res://game/vehicles/vehicle_damage.gd")
const Visual = preload("res://game/vehicles/lada_visual.gd")
const MIN_SPEED = Damage.MIN_SPEED
const RADIUS = Damage.RADIUS
const MAX_DEPTH = Damage.MAX_DEPTH
const ORIGINAL = Damage.ORIGINAL
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var actual := Visual.build()
	var reference := Visual.build()
	var untouched := Visual.build()
	root.add_child(actual)
	root.add_child(reference)
	root.add_child(untouched)
	var part := actual.get_node("Body/BodyMesh") as MeshInstance3D
	var ref_part := reference.get_node("Body/BodyMesh") as MeshInstance3D
	var shared := part.mesh
	var original_vertices: Array = []
	for surface in shared.get_surface_count():
		original_vertices.append(shared.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	_check(shared.has_meta(Damage.CPU_ARRAYS), "provider prepares impact arrays before first contact")
	for i in 3:
		var contact := Vector3(0.6, 0.65, -2.03) if i < 2 else Vector3(-0.7, 0.8, 1.8)
		_check(Damage.dent(actual, contact, Vector3.BACK, 12.0) == _legacy_dent(reference, contact, Vector3.BACK, 12.0), "same contact reach")
		_check(part.mesh.get_surface_count() == ref_part.mesh.get_surface_count(), "surface count")
		for s in part.mesh.get_surface_count():
			var aa := part.mesh.surface_get_arrays(s)
			var bb := ref_part.mesh.surface_get_arrays(s)
			for attribute in Mesh.ARRAY_MAX:
				_check(_same_attribute(aa[attribute], bb[attribute], attribute), "legacy attribute within packing precision %d surface %d hit %d" % [attribute, s, i])
			_check(part.mesh.surface_get_material(s) == shared.surface_get_material(s), "same material")
		_check(part.mesh.get_meta("slots") == shared.get_meta("slots"), "same slots")
	_check(untouched.get_node("Body/BodyMesh").mesh == shared, "other car remains shared")
	for surface in shared.get_surface_count():
		_check(shared.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] == original_vertices[surface], "shared source vertices remain immutable")
	_check(Damage.dent(untouched, Vector3(0.6, 0.65, -2.03), Vector3.BACK, 12.0), "second vehicle can deform independently")
	var other_damage: Mesh = untouched.get_node("Body/BodyMesh").mesh
	Damage.reset(actual)
	_check(untouched.get_node("Body/BodyMesh").mesh == other_damage, "reset does not affect another damaged car")
	_check(part.mesh == shared, "restore exact original")
	# Hot deformation must not create a temporary rendered mesh to read back normals.
	var code := FileAccess.get_file_as_string("res://game/vehicles/vehicle_damage.gd")
	_check(not code.get_slice("static func reset", 0).contains("surface_get_arrays")
		and not code.contains("tool.create_from(temporary")
		and not code.contains("normals_mesh.surface_get_arrays"),
		"hot deformation stays on CPU without renderer readbacks")
	actual.queue_free()
	reference.queue_free()
	untouched.queue_free()
	await process_frame
	print("VEHICLE_DAMAGE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
func _same_attribute(a: Variant, b: Variant, attribute: int) -> bool:
	if a == b:
		return true
	if a == null or b == null or a.size() != b.size():
		return false
	# Two omitted normal packing passes can differ by a few 16-bit steps.
	# Vertex positions and all other attributes retain strict precision.
	var maximum := 0.0
	if attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
		for i in a.size():
			maximum = maxf(maximum, a[i].distance_to(b[i]))
		
		return maximum < (0.00001 if attribute == Mesh.ARRAY_VERTEX else 0.0005)
	if attribute == Mesh.ARRAY_TANGENT:
		for i in a.size():
			maximum = maxf(maximum, absf(a[i]-b[i]))
		
		return maximum < 0.0005
	return false
func _legacy_dent(visual: Node3D, world_contact: Vector3, inward_world: Vector3, closing_speed: float) -> bool:
	if not is_instance_valid(visual) or closing_speed < MIN_SPEED:
		return false
	var part := visual.get_node_or_null("Body/BodyMesh") as MeshInstance3D
	if part == null or not (part.mesh is ArrayMesh) or inward_world.length_squared() < 0.001:
		return false
	if not part.has_meta(ORIGINAL):
		part.set_meta(ORIGINAL, part.mesh)
	var original := part.get_meta(ORIGINAL) as ArrayMesh
	var current := part.mesh as ArrayMesh
	var point := part.to_local(world_contact)
	var inward := (part.global_basis.inverse() * inward_world).normalized()
	var depth := clampf((closing_speed - MIN_SPEED) * 0.017 + 0.025, 0.025, 0.19)
	var replacement := ArrayMesh.new()
	var changed := false
	for s in current.get_surface_count():
		var arrays := current.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base_vertices: PackedVector3Array = original.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			# Original coordinates keep a second hit at the same body panel cumulative.
			var distance := base_vertices[i].distance_to(point)
			if distance >= RADIUS:
				continue
			var weight := pow(1.0 - distance / RADIUS, 2.0)
			var displacement := vertices[i] - base_vertices[i] + inward * depth * weight
			vertices[i] = base_vertices[i] + displacement.limit_length(MAX_DEPTH)
			changed = true
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var temporary := ArrayMesh.new()
		temporary.add_surface_from_arrays(current.surface_get_primitive_type(s), arrays)
		var tool := SurfaceTool.new()
		tool.create_from(temporary, 0)
		tool.generate_normals()
		var normals_mesh := tool.commit()
		var normals: PackedVector3Array = normals_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		# SurfaceTool preserves the provider's vertex order (these meshes are unindexed).
		if normals.size() == vertices.size():
			arrays[Mesh.ARRAY_NORMAL] = normals
		replacement.add_surface_from_arrays(current.surface_get_primitive_type(s), arrays)
		replacement.surface_set_material(s, current.surface_get_material(s))
	if not changed:
		return false
	replacement.set_meta("slots", current.get_meta("slots", []))
	part.mesh = replacement
	visual.set_meta("vehicle_dent_count", int(visual.get_meta("vehicle_dent_count", 0)) + 1)
	return true
