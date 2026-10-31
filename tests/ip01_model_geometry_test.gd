extends SceneTree
## Independent IP-01 geometry oracle. Run only after root closes the movement checkpoint.
## tools/run.command --headless --script tests/ip01_model_geometry_test.gd
## Optional user arguments: -- res://path/police_model.gd res://path/guard_model.gd
const DEFAULT_PATHS := ["res://game/characters/models/police_model.gd", "res://game/characters/models/guard_model.gd"]
const NAMES := ["root", "hips", "spine", "head", "upper_arm_l", "lower_arm_l", "hand_l", "upper_arm_r", "lower_arm_r", "hand_r", "leg_l", "foot_l", "leg_r", "foot_r"]
const PARENTS := [-1, 0, 1, 2, 2, 4, 5, 2, 7, 8, 1, 10, 1, 12]
const EPS := 0.003
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var paths: Array = Array(OS.get_cmdline_user_args())
	if paths.is_empty(): paths = DEFAULT_PATHS
	for path in paths:
		await _model(str(path))
	print("IP01_GEOMETRY: %d checks, %d failures; rendering and runtime NOT_RUN" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _model(path: String) -> void:
	_check(ResourceLoader.exists(path), path + ": script exists")
	if not ResourceLoader.exists(path): return
	var script = load(path)
	_check(script is Script and script.can_instantiate(), path + ": instantiable script")
	if not script is Script or not script.can_instantiate(): return
	var factory = script.new()
	_check(factory is RefCounted and factory.has_method("build_model"), path + ": RefCounted.build_model")
	if not factory is RefCounted or not factory.has_method("build_model"): return
	var model = factory.build_model()
	_check(model is Node3D, path + ": build_model returns Node3D")
	if not model is Node3D: return
	root.add_child(model)
	await process_frame
	var again = script.new().build_model()
	_check(again is Node3D and again != model, path + ": fresh visual node on repeated construction")
	if not again is Node3D:
		model.free()
		return
	root.add_child(again)
	await process_frame
	var skeletons: Array = []
	var meshes: Array = []
	var second_meshes: Array = []
	_nodes(model, skeletons, meshes, path)
	_collect_meshes(again, second_meshes)
	_check(skeletons.size() == 1, path + ": one Skeleton3D")
	_check(not meshes.is_empty(), path + ": visible mesh geometry")
	_check(model.get_meta("visible_height", 0.0) == 1.0, path + ": visible_height metadata is normalized")
	var bone_map = model.get_meta("bone_names", {})
	_check(bone_map is Dictionary and bone_map.size() == NAMES.size(), path + ": complete bone_names metadata")
	var skeleton: Skeleton3D = skeletons[0] if skeletons.size() == 1 else null
	if skeleton:
		_check(skeleton.get_bone_count() == NAMES.size(), path + ": exactly 14 bones")
		for b in mini(skeleton.get_bone_count(), NAMES.size()):
			_check(skeleton.get_bone_name(b) == NAMES[b] and skeleton.get_bone_parent(b) == PARENTS[b], path + ": bone hierarchy " + NAMES[b])
			_check(bone_map.get(NAMES[b], -1) == b, path + ": metadata index " + NAMES[b])
			_check(skeleton.get_bone_global_rest(b).is_finite(), path + ": finite bone rest " + NAMES[b])
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var total_triangles := 0
	var total_surfaces := 0
	var signed_volume := 0.0
	_check(meshes.size() == second_meshes.size(), path + ": repeated hierarchy mesh count")
	for mi in meshes.size():
		var instance: MeshInstance3D = meshes[mi]
		var mesh = instance.mesh
		_check(mesh is ArrayMesh, path + ": skinned ArrayMesh " + str(mi))
		if not mesh is ArrayMesh: continue
		_check(instance.skin != null and skeleton != null and instance.get_node_or_null(instance.skeleton) == skeleton, path + ": skin attached to actual skeleton")
		if instance.skin and skeleton: _skin(instance, skeleton, path)
		if mi < second_meshes.size():
			var other: MeshInstance3D = second_meshes[mi]
			_check(mesh == other.mesh and instance.skin == other.skin, path + ": repeated builds share mesh and Skin resources")
			for s in mesh.get_surface_count():
				_check(instance.get_active_material(s) == other.get_active_material(s), path + ": repeated material shared " + str(s))
		var relative: Transform3D = model.global_transform.affine_inverse() * instance.global_transform
		total_surfaces += mesh.get_surface_count()
		for s in mesh.get_surface_count():
			_check(mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES, path + ": triangle surface " + str(s))
			var a: Array = mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var bones = a[Mesh.ARRAY_BONES]
			var weights = a[Mesh.ARRAY_WEIGHTS]
			_check(not vertices.is_empty() and normals.size() == vertices.size(), path + ": vertices and normals align")
			var influence_count := 8 if mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
			var weighted: bool = bones != null and weights != null and bones.size() == vertices.size() * influence_count and weights.size() == vertices.size() * influence_count
			_check(weighted, path + ": complete skin weight arrays")
			var bad_vertices := 0
			var bad_weights := 0
			for v in vertices.size():
				if not vertices[v].is_finite(): bad_vertices += 1
				var p := relative * vertices[v]
				lo = lo.min(p)
				hi = hi.max(p)
				if v >= normals.size() or not normals[v].is_finite() or absf(normals[v].length() - 1.0) > 0.02: bad_vertices += 1
				if weighted:
					var sum := 0.0
					for k in influence_count:
						var offset := v * influence_count + k
						var w := float(weights[offset])
						if not is_finite(w) or w < 0.0: bad_weights += 1
						if w > 0.0 and (int(bones[offset]) < 0 or int(bones[offset]) >= NAMES.size()): bad_weights += 1
						sum += w
					if absf(sum - 1.0) > 0.0001: bad_weights += 1
			_check(bad_vertices == 0, path + ": finite vertices / unit normals (%d bad)" % bad_vertices)
			_check(bad_weights == 0, path + ": finite nonnegative normalized weights / valid bones (%d bad)" % bad_weights)
			if indices.is_empty():
				for v in vertices.size(): indices.append(v)
			_check(indices.size() % 3 == 0, path + ": triangle index count divisible by three")
			var invalid := 0
			for index in indices:
				if index < 0 or index >= vertices.size(): invalid += 1
			_check(invalid == 0, path + ": valid vertex indices")
			if invalid > 0: continue
			var inverted := 0
			var degenerate := 0
			for t in range(0, indices.size() - 2, 3):
				var ia := indices[t]
				var ib := indices[t + 1]
				var ic := indices[t + 2]
				var cross := (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia])
				if cross.length_squared() < 1e-20:
					degenerate += 1
					continue
				if normals.size() == vertices.size() and cross.dot(normals[ia] + normals[ib] + normals[ic]) >= 0.0: inverted += 1
				var va := relative * vertices[ia]
				var vb := relative * vertices[ib]
				var vc := relative * vertices[ic]
				signed_volume += va.dot(vb.cross(vc)) / 6.0
			_check(inverted == 0, path + ": clockwise winding agrees with normals (%d inverted)" % inverted)
			print("IP01_SURFACE: %s surface=%d vertices=%d triangles=%d degenerate=%d" % [path, s, vertices.size(), indices.size() / 3, degenerate])
			total_triangles += indices.size() / 3
			_material(instance.get_active_material(s), path)
	_check(lo.is_finite() and hi.is_finite() and absf(lo.y) <= EPS and absf(hi.y - 1.0) <= EPS, path + ": normalized feet=0/top=1; bounds " + str(AABB(lo, hi - lo)))
	_check(hi.x - lo.x > 0.0001 and hi.z - lo.z > 0.0001 and absf(signed_volume) > 0.000001, path + ": nonzero XYZ extent and enclosed signed volume")
	_check(total_surfaces >= 3 and total_surfaces <= 6, path + ": 3–6 surfaces (%d)" % total_surfaces)
	_check(total_triangles > 0 and total_triangles < 12000, path + ": triangle budget below 12000 (%d)" % total_triangles)
	print("IP01_MODEL: %s triangles=%d surfaces=%d bounds=%s signed_volume=%.6f" % [path, total_triangles, total_surfaces, AABB(lo, hi - lo), signed_volume])
	model.free()
	again.free()

func _nodes(node: Node, skeletons: Array, meshes: Array, path: String) -> void:
	_check(not (node is Sprite3D or node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D or node is Camera3D or node is Light3D), path + ": visual-only node " + str(node.get_path()))
	if node is Skeleton3D: skeletons.append(node)
	if node is MeshInstance3D: meshes.append(node)
	if node.get_script() != null:
		var source: String = node.get_script().source_code
		_check(not source.contains("Input.") and not source.contains("move_and_slide") and not source.contains("var velocity"), path + ": no visual-owned input/velocity")
	for child in node.get_children(): _nodes(child, skeletons, meshes, path)

func _collect_meshes(node: Node, meshes: Array) -> void:
	if node is MeshInstance3D: meshes.append(node)
	for child in node.get_children(): _collect_meshes(child, meshes)

func _skin(instance: MeshInstance3D, skeleton: Skeleton3D, path: String) -> void:
	var skin: Skin = instance.skin
	_check(skin.get_bind_count() == NAMES.size(), path + ": 14 Skin binds")
	var seen := {}
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		if b < 0: b = skeleton.find_bone(skin.get_bind_name(i))
		_check(b >= 0 and b < NAMES.size() and not seen.has(b), path + ": unique valid Skin bind " + str(i))
		if b < 0 or b >= NAMES.size(): continue
		seen[b] = true
		var bind := skin.get_bind_pose(i)
		_check(bind.is_finite(), path + ": finite inverse bind " + str(i))
		var rest_in_mesh: Transform3D = instance.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(b)
		var identity := rest_in_mesh * bind
		_check(identity.origin.length() < 0.0001 and identity.basis.is_equal_approx(Basis.IDENTITY), path + ": inverse-rest bind identity " + NAMES[b])

func _material(material: Material, path: String) -> void:
	_check(material != null, path + ": material exists")
	if material == null: return
	var image_texture := false
	for property in material.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE:
			var value = material.get(property.name)
			if value is Texture2D: image_texture = true
	_check(not image_texture, path + ": no model image texture")
