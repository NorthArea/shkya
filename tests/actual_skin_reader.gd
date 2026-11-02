extends RefCounted
## Independent CPU oracle: Skin bind indices are not Skeleton bone indices.
## Inverse binds map mesh vertices to bone space; skeleton world space therefore
## supplies the final frame, including the complete imported node hierarchy.
signal final_pose_captured
var mesh_instance: MeshInstance3D
var skeleton: Skeleton3D
var surfaces: Array[Dictionary] = []
var bind_bones := PackedInt32Array()
var inverse_binds: Array[Transform3D] = []
var issues: Array[String] = []
var vertex_count := 0
var triangle_count := 0
var referenced_vertices := PackedInt32Array()
var use_final_pose := false
var final_pose_serial := 0
var final_pose_frame := -1
var final_global_poses: Array[Transform3D] = []
var snapshot_reference: Node3D
var snapshot_metadata: Callable
var final_metadata := {}
var final_skeleton_world := Transform3D.IDENTITY
var final_skeleton_presented := Transform3D.IDENTITY
var final_reference_world := Transform3D.IDENTITY
var final_reference_presented := Transform3D.IDENTITY
var final_physics_frame := -1
var final_interpolation_fraction := 0.0
var final_time_usec := 0

func prepare(instance: MeshInstance3D, moving_reference: Node3D = null) -> void:
	if skeleton != null and skeleton.skeleton_updated.is_connected(_cache_final_pose): skeleton.skeleton_updated.disconnect(_cache_final_pose)
	mesh_instance = instance
	snapshot_reference = moving_reference
	surfaces.clear()
	bind_bones.clear()
	inverse_binds.clear()
	issues.clear()
	vertex_count = 0
	triangle_count = 0
	referenced_vertices.clear()
	final_pose_serial = 0
	final_pose_frame = -1
	final_global_poses.clear()
	final_metadata.clear()
	skeleton = instance.get_node_or_null(instance.skeleton) as Skeleton3D
	if skeleton == null or instance.skin == null or instance.mesh == null:
		issues.append("actual mesh needs a resolved Skeleton3D and Skin")
		return
	skeleton.skeleton_updated.connect(_cache_final_pose)
	for bind in instance.skin.get_bind_count():
		var name_ := instance.skin.get_bind_name(bind)
		var bone := skeleton.find_bone(name_) if not name_.is_empty() else instance.skin.get_bind_bone(bind)
		if bone < 0 or bone >= skeleton.get_bone_count():
			issues.append("unresolved Skin bind %d/%s" % [bind, name_])
		bind_bones.append(bone)
		inverse_binds.append(instance.skin.get_bind_pose(bind))
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var influences := 8 if instance.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for vertex in raw.size(): indices.append(vertex)
		if instance.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES or indices.size() % 3 != 0:
			issues.append("surface %d is not complete triangle geometry" % surface)
		if bones.size() != raw.size() * influences or weights.size() != bones.size():
			issues.append("surface %d skin array lengths disagree" % surface)
			continue
		var owners := PackedInt32Array()
		var names: Array[String] = []
		for vertex in raw.size():
			var total := 0.0
			var strongest := -1.0
			var owner := -1
			for influence in influences:
				var offset := vertex * influences + influence
				var weight := weights[offset]
				if not is_finite(weight) or weight < 0.0:
					issues.append("surface %d has invalid skin weight" % surface)
				if weight <= 0.0: continue
				var bind := bones[offset]
				if bind < 0 or bind >= bind_bones.size():
					issues.append("surface %d vertex %d references absent bind" % [surface, vertex])
					continue
				total += weight
				if weight > strongest:
					strongest = weight
					owner = bind_bones[bind]
			if absf(total - 1.0) > 0.0001: issues.append("surface %d vertex %d weight sum %.6f" % [surface, vertex, total])
			owners.append(owner)
			names.append(String(skeleton.get_bone_name(owner)) if owner >= 0 else "")
		for index in indices:
			if index < 0 or index >= raw.size(): issues.append("surface %d invalid triangle index" % surface)
		var used_indices := {}
		for index in indices: used_indices[index] = true
		for index in used_indices: referenced_vertices.append(vertex_count + int(index))
		var material := instance.mesh.surface_get_material(surface)
		surfaces.append({"raw": raw, "bones": bones, "weights": weights, "indices": indices,
			"influences": influences, "owners": owners, "names": names, "offset": vertex_count,
			"material": material.resource_name if material != null else "", "surface": surface, "referenced": used_indices.keys()})
		vertex_count += raw.size()
		triangle_count += indices.size() / 3

func transforms(rest := false) -> Array[Transform3D]:
	if not use_final_pose: skeleton.force_update_all_bone_transforms()
	var result: Array[Transform3D] = []
	for bind in bind_bones.size():
		var pose := skeleton.get_bone_global_rest(bind_bones[bind]) if rest else bone_global_pose(bind_bones[bind])
		result.append(pose * inverse_binds[bind])
	return result

func output_frame(rest := false, reference: Node3D = null, interpolated := false) -> Transform3D:
	var frame := skeleton.get_global_transform_interpolated() if interpolated else skeleton.global_transform
	if use_final_pose and not rest: frame = final_skeleton_presented if interpolated else final_skeleton_world
	if reference != null:
		var reference_frame := reference.get_global_transform_interpolated() if interpolated else reference.global_transform
		if use_final_pose and not rest and reference == snapshot_reference: reference_frame = final_reference_presented if interpolated else final_reference_world
		frame = reference_frame.affine_inverse() * frame
	return frame

func _cache_final_pose() -> void:
	# Native SkeletonModifier3D restores the animation input after rendering.
	# This signal is the public boundary exposing final matrices used by Skin.
	final_global_poses.clear()
	for bone in skeleton.get_bone_count(): final_global_poses.append(skeleton.get_bone_global_pose(bone))
	final_skeleton_world = skeleton.global_transform
	final_skeleton_presented = skeleton.get_global_transform_interpolated()
	if snapshot_reference != null:
		final_reference_world = snapshot_reference.global_transform
		final_reference_presented = snapshot_reference.get_global_transform_interpolated()
	final_metadata = snapshot_metadata.call() if snapshot_metadata.is_valid() else {}
	final_pose_serial += 1
	final_pose_frame = Engine.get_process_frames()
	final_physics_frame = Engine.get_physics_frames()
	final_interpolation_fraction = Engine.get_physics_interpolation_fraction()
	final_time_usec = Time.get_ticks_usec()
	final_pose_captured.emit()

func bone_global_pose(bone: int) -> Transform3D:
	if not use_final_pose: return skeleton.get_bone_global_pose(bone)
	assert(final_global_poses.size() == skeleton.get_bone_count(), "Final Skeleton3D snapshot has not been observed")
	return final_global_poses[bone]

func bone_local_pose(bone: int) -> Transform3D:
	if not use_final_pose: return skeleton.get_bone_pose(bone)
	var parent := skeleton.get_bone_parent(bone)
	return bone_global_pose(parent).affine_inverse() * bone_global_pose(bone) if parent >= 0 else bone_global_pose(bone)

func capture(rest := false, reference: Node3D = null, interpolated := false) -> PackedVector3Array:
	var result := PackedVector3Array()
	if not issues.is_empty(): return result
	var xf := transforms(rest)
	var frame := output_frame(rest, reference, interpolated)
	for surface in surfaces:
		for vertex in surface.raw.size(): result.append(frame * _point(surface, vertex, xf))
	return result

func subset(samples: Array[Vector2i], reference: Node3D = null, interpolated := false) -> PackedVector3Array:
	var result := PackedVector3Array()
	var xf := transforms(false)
	var frame := output_frame(false, reference, interpolated)
	for sample in samples: result.append(frame * _point(surfaces[sample.x], sample.y, xf))
	return result

func _point(surface: Dictionary, vertex: int, xf: Array[Transform3D]) -> Vector3:
	var result := Vector3.ZERO
	for influence in int(surface.influences):
		var slot := vertex * int(surface.influences) + influence
		if surface.weights[slot] > 0.0: result += (xf[surface.bones[slot]] * surface.raw[vertex]) * surface.weights[slot]
	return result

func triangles(points: PackedVector3Array, owner_filter: Array = []) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	for surface in surfaces:
		var indices: PackedInt32Array = surface.indices
		for at in range(0, indices.size() - 2, 3):
			var a := indices[at]
			var b := indices[at + 1]
			var c := indices[at + 2]
			if not owner_filter.is_empty() and surface.names[a] not in owner_filter and surface.names[b] not in owner_filter and surface.names[c] not in owner_filter: continue
			result.append(PackedVector3Array([points[surface.offset + a], points[surface.offset + b], points[surface.offset + c]]))
	return result

func referenced(points: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for index in referenced_vertices: result.append(points[index])
	return result

static func bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty(): return AABB()
	var low := points[0]
	var high := low
	for point in points:
		low = low.min(point)
		high = high.max(point)
	return AABB(low, high - low)

static func delta(first: PackedVector3Array, second: PackedVector3Array) -> float:
	if first.is_empty() or first.size() != second.size(): return INF
	var result := 0.0
	for index in first.size(): result = maxf(result, first[index].distance_to(second[index]))
	return result
