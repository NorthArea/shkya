extends RefCounted
## Walking-only skeleton. Authored resources and their fourteen bone indices stay intact.
static var _resources: Dictionary = {}
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var legs: Array[Dictionary] = []

func build(author: Skeleton3D, authored_mesh: MeshInstance3D, civilian: bool) -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "LocomotionSkeleton3D"
	for index in author.get_bone_count():
		skeleton.add_bone(author.get_bone_name(index))
		skeleton.set_bone_parent(index, author.get_bone_parent(index))
		skeleton.set_bone_rest(index, author.get_bone_rest(index))
	for suffix: String in ["_l", "_r"]:
		var hip := author.find_bone("leg" + suffix)
		var old_foot := author.find_bone("foot" + suffix)
		var hip_at := author.get_bone_global_rest(hip).origin
		var foot_at := author.get_bone_global_rest(old_foot).origin
		var added := skeleton.get_bone_count()
		var knee: int = old_foot if civilian else added
		var ankle: int = added if civilian else old_foot
		var knee_at: Vector3 = foot_at if civilian else hip_at.lerp(foot_at, 0.49)
		var ankle_at: Vector3 = Vector3(foot_at.x, minf(0.075, foot_at.y * 0.34), foot_at.z) if civilian else foot_at
		skeleton.add_bone(("ankle" if civilian else "knee") + suffix)
		if civilian:
			skeleton.set_bone_parent(ankle, knee)
			skeleton.set_bone_rest(ankle, Transform3D(Basis.IDENTITY, ankle_at - knee_at))
		else:
			skeleton.set_bone_parent(knee, hip)
			skeleton.set_bone_rest(knee, Transform3D(Basis.IDENTITY, knee_at - hip_at))
			skeleton.set_bone_parent(ankle, knee)
			skeleton.set_bone_rest(ankle, Transform3D(Basis.IDENTITY, ankle_at - knee_at))
		legs.append({"hip": hip, "knee": knee, "ankle": ankle, "hip_rest": hip_at,
			"knee_rest": knee_at, "ankle_rest": ankle_at, "rest_sole": Vector3(foot_at.x, 0, foot_at.z),
			"upper_length": hip_at.distance_to(knee_at), "lower_length": knee_at.distance_to(ankle_at)})
	author.get_parent().add_child(skeleton)
	skeleton.reset_bone_poses()
	var key := authored_mesh.mesh.get_instance_id()
	if not _resources.has(key):
		_resources[key] = _build_resources(authored_mesh, civilian)
	var resources: Dictionary = _resources[key]
	for index in legs.size():
		legs[index].rest_sole = resources.soles[index]
	mesh = MeshInstance3D.new()
	mesh.name = "LocomotionMesh"
	mesh.mesh = resources.mesh
	mesh.skin = resources.skin
	mesh.skeleton = NodePath("..")
	mesh.cast_shadow = authored_mesh.cast_shadow
	mesh.visibility_range_end = authored_mesh.visibility_range_end
	mesh.visibility_range_end_margin = authored_mesh.visibility_range_end_margin
	skeleton.add_child(mesh)

func _build_resources(source: MeshInstance3D, civilian: bool) -> Dictionary:
	var skin := Skin.new()
	for index in skeleton.get_bone_count():
		skin.add_bind(index, skeleton.get_bone_global_rest(index).affine_inverse())
	var result := ArrayMesh.new()
	result.resource_name = source.mesh.resource_name + "_Locomotion"
	var soles: Array[Vector3] = [legs[0].rest_sole, legs[1].rest_sole]
	var lowest := [INF, INF]
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES].duplicate()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS].duplicate()
		for vertex in vertices.size():
			var influences: Dictionary = {}
			for slot in 4:
				var offset := vertex * 4 + slot
				if weights[offset] <= 0.0:
					continue
				var bone := indices[offset]
				var weight := weights[offset]
				var replacement := bone
				var mix_amount := 0.0
				for side in legs.size():
					var leg: Dictionary = legs[side]
					if civilian and bone == leg.knee:
						replacement = leg.ankle
						mix_amount = 1.0 - smoothstep(leg.ankle_rest.y + 0.012, leg.ankle_rest.y + 0.055, vertices[vertex].y)
					elif not civilian and bone == leg.hip:
						replacement = leg.knee
						mix_amount = 1.0 - smoothstep(leg.knee_rest.y - 0.025, leg.knee_rest.y + 0.025, vertices[vertex].y)
					if bone in [leg.hip, leg.knee, leg.ankle] and weight > 0.5 and vertices[vertex].y < lowest[side]:
						lowest[side] = vertices[vertex].y
						soles[side] = vertices[vertex]
				influences[bone] = float(influences.get(bone, 0.0)) + weight * (1.0 - mix_amount)
				influences[replacement] = float(influences.get(replacement, 0.0)) + weight * mix_amount
			var active: Array = influences.keys()
			active.sort_custom(func(a: int, b: int) -> bool: return influences[a] > influences[b])
			var total := 0.0
			for slot in mini(4, active.size()):
				total += float(influences[active[slot]])
			for slot in 4:
				var offset := vertex * 4 + slot
				indices[offset] = int(active[slot]) if slot < active.size() else 0
				weights[offset] = float(influences[active[slot]]) / total if slot < active.size() else 0.0
		arrays[Mesh.ARRAY_BONES] = indices
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_name(surface, source.mesh.surface_get_name(surface))
		result.surface_set_material(surface, source.mesh.surface_get_material(surface))
	return {"mesh": result, "skin": skin, "soles": soles}

func solve_leg(index: int, sole: Vector3, sole_basis: Basis, weight: float) -> void:
	var leg: Dictionary = legs[index]
	var hip: int = leg.hip
	var knee: int = leg.knee
	var ankle: int = leg.ankle
	var hip_at := skeleton.get_bone_global_pose(hip).origin
	var ankle_at: Vector3 = sole - sole_basis * (leg.rest_sole - leg.ankle_rest)
	var reach: Vector3 = ankle_at - hip_at
	var upper_length: float = leg.upper_length
	var lower_length: float = leg.lower_length
	var distance := clampf(reach.length(), absf(upper_length - lower_length) + 0.00001, upper_length + lower_length - 0.00001)
	var toward: Vector3 = reach.normalized()
	var bend: Vector3 = Vector3.FORWARD - toward * Vector3.FORWARD.dot(toward)
	if bend.length_squared() < 0.00001:
		bend = Vector3.UP - toward * Vector3.UP.dot(toward)
	bend = bend.normalized()
	var along := (distance * distance + upper_length * upper_length - lower_length * lower_length) / (2.0 * distance)
	var knee_at: Vector3 = hip_at + toward * along + bend * sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var upper := Quaternion((leg.knee_rest - leg.hip_rest).normalized(), (knee_at - hip_at).normalized())
	var lower := Quaternion((leg.ankle_rest - leg.knee_rest).normalized(), (hip_at + toward * distance - knee_at).normalized())
	var parent := skeleton.get_bone_parent(hip)
	var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(hip, Quaternion.IDENTITY.slerp(parent_rotation.inverse() * upper, weight))
	skeleton.set_bone_pose_rotation(knee, Quaternion.IDENTITY.slerp(upper.inverse() * lower, weight))
	skeleton.set_bone_pose_rotation(ankle, Quaternion.IDENTITY.slerp(lower.inverse() * sole_basis.get_rotation_quaternion(), weight))
