extends RefCounted
## Local plastic deformation. Cached provider meshes remain immutable.

const MIN_SPEED := 2.3
const RADIUS := 0.95
const MAX_DEPTH := 0.34
const ORIGINAL := &"vehicle_undamaged_mesh"

static func dent(visual: Node3D, world_contact: Vector3, inward_world: Vector3, closing_speed: float) -> bool:
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

static func reset(visual: Node3D) -> void:
	if not is_instance_valid(visual):
		return
	var part := visual.get_node_or_null("Body/BodyMesh") as MeshInstance3D
	if part and part.has_meta(ORIGINAL):
		part.mesh = part.get_meta(ORIGINAL)
		part.remove_meta(ORIGINAL)
	visual.set_meta("vehicle_dent_count", 0)
