extends SceneTree
## Developer geometry/rig/isolation checks. Native appearance and gameplay are separate gates.
const Models = preload("res://game/characters/models/civilian_model.gd")
const NAMES := ["root", "hips", "spine", "head", "upper_arm_l", "lower_arm_l", "hand_l", "upper_arm_r", "lower_arm_r", "hand_r", "leg_l", "foot_l", "leg_r", "foot_r"]
const PARENTS := [-1, 0, 1, 2, 2, 4, 5, 2, 7, 8, 1, 10, 1, 12]
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("IP01_CIVILIAN: " + message)

func _run() -> void:
	var expected: Array[String] = ["ilyusha", "babka", "vendor", "officer"]
	for kind: String in ["babka", "man", "woman", "boy", "shuba", "beret", "violet", "ushanka", "ushanka_walk", "tourist", "kid", "kid2", "dog", "kolpak", "bow", "turban"]:
		expected.append("resident_" + kind)
	for kind: String in ["police_long", "police_round", "guard_alt"]:
		expected.append(kind)
	_check(Models.DRAWINGS.size() == expected.size(), "all current role drawings are explicitly covered")
	for drawing: String in expected:
		_check(Models.supports(drawing), drawing + " supported")
		await _model(drawing)
	_check(not Models.supports("missing_role"), "unknown role cannot silently become another identity")
	print("IP01_CIVILIAN_GEOMETRY: %d checks, %d failures; visual/runtime NOT_RUN" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _model(drawing: String) -> void:
	var model := Models.new().build_model(drawing)
	var other := Models.new().build_model(drawing)
	_check(model != null and other != null and model != other, drawing + " fresh instances")
	if model == null or other == null: return
	root.add_child(model)
	root.add_child(other)
	await process_frame
	_check(_count_nodes(model) == 3, drawing + " one root, one skeleton, one batched mesh")
	_check(model.get_meta("drawing", "") == drawing and model.get_meta("visible_height", 0.0) == 1.0 and model.get_meta("forward_axis", "") == "-Z", drawing + " identity and coordinate contract")
	var skeleton := model.get_node("Skeleton3D") as Skeleton3D
	var second := other.get_node("Skeleton3D") as Skeleton3D
	var instance := skeleton.get_node("UniformMesh") as MeshInstance3D
	var twin := second.get_node("UniformMesh") as MeshInstance3D
	_check(instance.get_node(instance.skeleton) == skeleton and instance.skin != null, drawing + " skin bound to own skeleton")
	_check(instance.mesh == twin.mesh and instance.skin == twin.skin, drawing + " cache shares immutable mesh and skin")
	_check(skeleton != second, drawing + " poses owned per actor")
	_rest_geometry(instance, skeleton, drawing + " fresh initial")
	_rest_geometry(twin, second, drawing + " cached initial")
	_check(skeleton.get_bone_count() == NAMES.size() and instance.skin.get_bind_count() == NAMES.size(), drawing + " complete human rig and binds")
	for i in NAMES.size():
		_check(skeleton.get_bone_name(i) == NAMES[i] and skeleton.get_bone_parent(i) == PARENTS[i], drawing + " hierarchy " + NAMES[i])
		var bind := instance.skin.get_bind_pose(i)
		var identity := skeleton.get_bone_global_rest(i) * bind
		_check(instance.skin.get_bind_bone(i) == i and bind.is_finite() and identity.origin.length() < 0.0001 and identity.basis.is_equal_approx(Basis.IDENTITY), drawing + " inverse bind " + NAMES[i])
	var mesh := instance.mesh as ArrayMesh
	_check(mesh != null and mesh.get_surface_count() >= 3 and mesh.get_surface_count() <= 6, drawing + " opaque batched material budget")
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var volume := 0.0
	var triangles := 0
	var invalid := 0
	var winding := 0
	var bone_vertices: Dictionary = {}
	var face_forward := 0
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		_check(material != null and material == twin.mesh.surface_get_material(surface) and material.albedo_texture == null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, drawing + " shared opaque texture-free material " + str(surface))
		var a := mesh.surface_get_arrays(surface)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		_check(v.size() > 0 and n.size() == v.size() and bones.size() == v.size() * 4 and weights.size() == v.size() * 4, drawing + " complete vertex attributes " + str(surface))
		for i in v.size():
			lo = lo.min(v[i])
			hi = hi.max(v[i])
			if not v[i].is_finite() or not n[i].is_finite() or absf(n[i].length() - 1.0) > 0.02: invalid += 1
			var sum := 0.0
			for k in 4:
				var bone: int = bones[i * 4 + k]
				var weight: float = weights[i * 4 + k]
				if not is_finite(weight) or weight < 0 or (weight > 0 and (bone < 0 or bone >= NAMES.size())): invalid += 1
				if weight > 0:
					bone_vertices[bone] = int(bone_vertices.get(bone, 0)) + 1
				sum += weight
			if absf(sum - 1.0) > 0.00001: invalid += 1
			if bones[i * 4] == 3 and v[i].z < -0.095: face_forward += 1
		for i in range(0, v.size(), 3):
			var cross := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
			if cross.length_squared() < 1e-20 or cross.dot(n[i] + n[i + 1] + n[i + 2]) >= 0: winding += 1
			volume += v[i].dot(v[i + 1].cross(v[i + 2])) / 6.0
		triangles += v.size() / 3
	_check(invalid == 0, drawing + " finite geometry, normals, normalized nonnegative skin weights")
	_check(winding == 0, drawing + " nondegenerate clockwise triangles")
	_check(absf(lo.y) < 0.003 and absf(hi.y - 1.0) < 0.003, drawing + " grounded normalized bounds " + str(AABB(lo, hi - lo)))
	_check(hi.x - lo.x > 0.25 and hi.z - lo.z > 0.15 and absf(volume) > 0.005, drawing + " solid volume in three axes")
	_check(triangles > 1000 and triangles < 12000, drawing + " triangle budget " + str(triangles))
	_check(face_forward > 50, drawing + " face occupies forward volume rather than a flat decal")
	for bone in range(1, NAMES.size()):
		var influenced := 0
		for weighted_bone: int in bone_vertices:
			var ancestor := weighted_bone
			while ancestor >= 0:
				if ancestor == bone:
					influenced += int(bone_vertices[weighted_bone])
					break
				ancestor = skeleton.get_bone_parent(ancestor)
		_check(influenced > 0, drawing + " weighted geometry in subtree of " + NAMES[bone])
	var rest_point := _skinned_vertex(instance, skeleton, 10)
	skeleton.set_bone_pose_rotation(10, Quaternion(Vector3.RIGHT, 0.28))
	skeleton.set_bone_pose_rotation(4, Quaternion(Vector3.RIGHT, -0.18))
	skeleton.force_update_all_bone_transforms()
	await process_frame
	var moved_point := _skinned_vertex(instance, skeleton, 10)
	_check(rest_point.distance_to(moved_point) > 0.005, drawing + " leg pose deforms weighted geometry")
	_check(second.get_bone_pose_rotation(10).is_equal_approx(Quaternion.IDENTITY) and second.get_bone_pose_rotation(4).is_equal_approx(Quaternion.IDENTITY), drawing + " another actor pose stays isolated")
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	await process_frame
	_check(rest_point.is_equal_approx(_skinned_vertex(instance, skeleton, 10)), drawing + " reset returns exact rest pose")
	_rest_geometry(instance, skeleton, drawing + " reset")
	var hips_rest := skeleton.get_bone_rest(1).origin
	skeleton.set_bone_pose_position(1, hips_rest + Vector3.UP * 0.01)
	skeleton.force_update_all_bone_transforms()
	await process_frame
	_check((_skinned_vertex(instance, skeleton, 10) - rest_point).is_equal_approx(Vector3.UP * 0.01), drawing + " hips translation moves descendant leg geometry")
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	await process_frame
	_rest_geometry(instance, skeleton, drawing + " hips reset")
	print("IP01_CIVILIAN_MODEL: %s triangles=%d bounds=%s volume=%.6f geometry_sha256=%s" % [drawing, triangles, AABB(lo, hi - lo), volume, _geometry_hash(mesh)])
	if drawing not in ["police_long", "police_round", "guard_alt"]:
		await _seated_geometry(instance, skeleton, drawing)
	model.free()
	other.free()

func _geometry_hash(mesh: ArrayMesh) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
			hash.update(var_to_bytes(arrays[attribute]))
	return hash.finish().hex_encode()

func _seated_geometry(instance: MeshInstance3D, skeleton: Skeleton3D, drawing: String) -> void:
	const ANGLE := 1.35
	var legs: Array[Dictionary] = []
	var rotation := Basis(Vector3.RIGHT, ANGLE)
	var sole := INF
	for suffix: String in ["_l", "_r"]:
		var leg := skeleton.find_bone("leg" + suffix)
		var foot := skeleton.find_bone("foot" + suffix)
		var hip_at := skeleton.get_bone_global_rest(leg).origin
		var knee_at := skeleton.get_bone_global_rest(foot).origin
		# Civilian foot_* is the authored knee. Its location is allowed to change
		# with the selected body; hierarchy, segment order and geometry are not.
		_check(skeleton.get_bone_parent(foot) == leg and hip_at.y > knee_at.y and knee_at.y > 0.0 and Vector2(hip_at.x - knee_at.x, hip_at.z - knee_at.z).length() < 0.0001, drawing + " lower-leg pivot is a real knee below hip and above sole")
		var displacement := hip_at + rotation * (knee_at - hip_at) - knee_at
		legs.append({"leg": leg, "foot": foot, "hip": hip_at, "knee": knee_at, "displacement": displacement})
		sole = minf(sole, displacement.y)
	var lower_vertices := 0
	var bad_lower_weights := 0
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			for segment: Dictionary in legs:
				# A long coat/hem may have secondary thigh weights below a knee;
				# it is not the authored leg/trouser region checked here.
				if instance.skin.get_bind_bone(bones[index * 4]) not in [segment.leg, segment.foot]: continue
				var thigh_weight := 0.0
				var shin_weight := 0.0
				for influence in 4:
					var slot := index * 4 + influence
					var bone := instance.skin.get_bind_bone(bones[slot])
					if bone == segment.leg: thigh_weight += weights[slot]
					if bone == segment.foot: shin_weight += weights[slot]
				if vertices[index].y < segment.knee.y:
					# The knee's continuous blend may retain a proximal influence;
					# the distal segment must dominate below the actual knee plane.
					if thigh_weight > shin_weight + 0.00005: bad_lower_weights += 1
					if shin_weight > 0.5 and vertices[index].y > segment.knee.y * 0.5: lower_vertices += 1
	_check(bad_lower_weights == 0 and lower_vertices > 50, drawing + " actual lower trousers are controlled by the lower segment, including blended knees")
	for segment: Dictionary in legs:
		skeleton.set_bone_pose_rotation(segment.leg, Quaternion(Vector3.RIGHT, ANGLE))
		skeleton.set_bone_pose_rotation(segment.foot, Quaternion(Vector3.RIGHT, -ANGLE))
	skeleton.force_update_all_bone_transforms()
	await process_frame
	for segment: Dictionary in legs:
		var leg: int = segment.leg
		var foot: int = segment.foot
		var thigh := skeleton.get_bone_global_pose(foot).origin - skeleton.get_bone_global_pose(leg).origin
		_check(thigh.normalized().z < -0.9 and thigh.y < 0, drawing + " seated thigh points forward")
		var shin := skeleton.get_bone_global_pose(foot).basis * Vector3.DOWN
		_check(shin.is_equal_approx(Vector3.DOWN), drawing + " seated shin points down")
		var rest := skeleton.get_bone_global_rest(foot).origin
		var posed := skeleton.get_bone_global_pose(foot) * instance.skin.get_bind_pose(foot) * Vector3(rest.x, 0, rest.z)
		_check(absf(posed.y - segment.displacement.y) < 0.0001, drawing + " posed sole matches rest-vector two-segment solver")
	# Independent forward kinematics, not a second call to the posed skeleton:
	# thigh P'=H+R(P-H); counter-rotated shin P'=H+R(K-H)+(P-K).
	var maximum_solver_delta := 0.0
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			var expected := Vector3.ZERO
			var actual := Vector3.ZERO
			for influence in 4:
				var slot := index * 4 + influence
				if weights[slot] <= 0.0: continue
				var bone := instance.skin.get_bind_bone(bones[slot])
				var independent := vertices[index]
				for segment: Dictionary in legs:
					if bone == segment.leg: independent = segment.hip + rotation * (vertices[index] - segment.hip)
					if bone == segment.foot: independent = vertices[index] + segment.displacement
				expected += independent * weights[slot]
				actual += (skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bones[slot]) * vertices[index]) * weights[slot]
			maximum_solver_delta = maxf(maximum_solver_delta, actual.distance_to(expected))
	_check(maximum_solver_delta < 0.0001, drawing + " every actual weighted vertex matches the independent two-segment rest-vector solver")
	var posed_bounds := _cpu_bounds(instance, skeleton)
	_check(absf(posed_bounds.position.y - sole) < 0.0001, drawing + " entire posed geometry rests on solved sole")
	# This is the upright-shin trolley pose. Lada uses its actual pedal pose and
	# cabin floor in car01_cabin_clearance_test.gd; it cannot inherit this solver.
	_check(posed_bounds.size.y < 1.0 and posed_bounds.size.z < 1.0, drawing + " seated body stays within its normalized envelope")
	for height: float in [1.5583, 1.91]:
		var trolley_bottom := 0.8 + (posed_bounds.position.y - sole) * height
		var trolley_top := 0.8 + (posed_bounds.end.y - sole) * height
		_check(absf(trolley_bottom - 0.8) < 0.0001 and trolley_top < 2.87, drawing + " actual seated geometry fits trolley floor and roof")
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	await process_frame
	_rest_geometry(instance, skeleton, drawing + " seated reset")
	print("IP01_CIVILIAN_SEATED: %s sole=%.6f posed=%s" % [drawing, sole, posed_bounds])

func _cpu_bounds(instance: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var lower := Vector3(INF, INF, INF)
	var upper := Vector3(-INF, -INF, -INF)
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			var point := Vector3.ZERO
			for influence in 4:
				var offset := index * 4 + influence
				if weights[offset] <= 0: continue
				var bind := bones[offset]
				point += (skeleton.get_bone_global_pose(instance.skin.get_bind_bone(bind)) * instance.skin.get_bind_pose(bind) * vertices[index]) * weights[offset]
			lower = lower.min(point)
			upper = upper.max(point)
	return AABB(lower, upper - lower)

func _rest_geometry(instance: MeshInstance3D, skeleton: Skeleton3D, label_: String) -> void:
	var pose_matches_rest := true
	for bone in skeleton.get_bone_count():
		if not skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_rest(bone)):
			pose_matches_rest = false
	_check(pose_matches_rest, label_ + " every local bone pose equals authored rest")
	var lower := INF
	var upper := -INF
	var foot_lower := INF
	var max_delta := 0.0
	for surface in instance.mesh.get_surface_count():
		var a := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			var point := Vector3.ZERO
			var foot := false
			for influence in 4:
				var offset := index * 4 + influence
				if weights[offset] <= 0.0: continue
				var bind := bones[offset]
				var bone := instance.skin.get_bind_bone(bind)
				point += (skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind) * vertices[index]) * weights[offset]
				if bone in [11, 13]: foot = true
			max_delta = maxf(max_delta, point.distance_to(vertices[index]))
			lower = minf(lower, point.y)
			upper = maxf(upper, point.y)
			if foot: foot_lower = minf(foot_lower, point.y)
	_check(max_delta < 0.0001, label_ + " actual skinned rest reproduces every bind-space vertex")
	_check(absf(lower) < 0.003 and absf(foot_lower) < 0.003 and absf(upper - 1.0) < 0.003, label_ + " actual skinned body/feet=0 and top=1")
	print("IP01_CIVILIAN_REST: %s hips_local=%s body_min=%.6f feet_min=%.6f top=%.6f max_bind_delta=%.6f" % [label_, skeleton.get_bone_pose_position(1), lower, foot_lower, upper, max_delta])

func _count_nodes(node: Node) -> int:
	_check(node is Node3D and not (node is Sprite3D or node is CollisionObject3D or node is CollisionShape3D or node is Camera3D or node is Light3D), "visual tree contains geometry only")
	var count := 1
	for child: Node in node.get_children(): count += _count_nodes(child)
	return count

func _skinned_vertex(instance: MeshInstance3D, skeleton: Skeleton3D, target_bone: int) -> Vector3:
	var selected := Vector3.INF
	var farthest := -1.0
	var pivot := skeleton.get_bone_global_rest(target_bone).origin
	for surface in instance.mesh.get_surface_count():
		var a := instance.mesh.surface_get_arrays(surface)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		for i in v.size():
			if bones[i * 4] == target_bone:
				var distance := Vector2(v[i].y - pivot.y, v[i].z - pivot.z).length_squared()
				if distance > farthest:
					farthest = distance
					selected = v[i]
	if farthest < 0:
		push_error("Missing target geometry")
		return Vector3.INF
	return skeleton.get_bone_global_pose(target_bone) * instance.skin.get_bind_pose(target_bone) * selected
