extends SceneTree
## Exact oracle for immutable bind-mesh sole data; no animation or appearance simplification.
const Uniform = preload("res://game/characters/uniform_visual.gd")
const Civilian = preload("res://game/characters/models/civilian_model.gd")
const Rig = preload("res://game/characters/locomotion_rig.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)
func visual(drawing: String, height: float) -> Node3D:
	var actor := Node3D.new()
	root.add_child(actor)
	var look := Uniform.new()
	look.configure(drawing, height, Color.WHITE)
	actor.add_child(look)
	look.prepare_locomotion()
	return look
func _run() -> void:
	var probe := visual("police", 2.0)
	check(probe.rig.get("_resource_data") is Dictionary, "sole derived data belongs to existing rig resource entry")
	if failures:
		probe.get_parent().free()
		print("SOLE_CACHE: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	probe.get_parent().free()
	for drawing: String in ["police", "guard"] + Array(Civilian.DRAWINGS):
		if drawing != "ilyusha":
			catalog_case(drawing)
	for entry: Dictionary in Rig._resources.values():
		check(entry.footprints.size() == 2, "bounded two-leg derived storage")
		for cached: Dictionary in entry.footprints:
			check(cached.signature is PackedByteArray and cached.corners is PackedVector3Array,
				"derived entries retain values, not actors, skeletons, materials or resources")
	print("SOLE_CACHE: %d checks, %d failures; headless exact-output only" % [checks, failures])
	quit(0 if failures == 0 else 1)
func catalog_case(drawing: String) -> void:
	var first := visual(drawing, 1.6)
	var second := visual(drawing, 2.4)
	var rig = first.rig
	var data: Dictionary = rig._resource_data
	var original: ArrayMesh = rig.mesh.mesh
	check(is_same(data, second.rig._resource_data), drawing + " actors share existing immutable data owner")
	check(rig.skeleton != second.rig.skeleton and not is_same(rig.legs, second.rig.legs), drawing + " independent rigs")
	var before: Array = []
	for surface in original.get_surface_count():
		before.append(original.surface_get_arrays(surface))
	first.skeleton.set_bone_pose_rotation(1, Quaternion(Vector3.UP, 0.4))
	first.skeleton.force_update_all_bone_transforms()
	for index in 2:
		var initial: Vector3 = data.soles[index]
		var expected := reference(rig, index, initial)
		check(first.gait._sole_corners[index].to_byte_array() == expected.to_byte_array(), drawing + " cold exact corners")
		check(second.gait._sole_corners[index].to_byte_array() == expected.to_byte_array(), drawing + " scaled/posed sibling exact corners")
		var leg: Dictionary = rig.legs[index]
		var saved_sole: Vector3 = leg.rest_sole
		leg.rest_sole = initial
		var signature: PackedByteArray = data.footprints[index].signature
		var returned: PackedVector3Array = first.gait._sole_footprint(index)
		returned[0] += Vector3(7, 8, 9)
		check(first.gait._sole_footprint(index).to_byte_array() == expected.to_byte_array(), drawing + " returned corners cannot mutate cache")
		check(second.gait._sole_corners[index].to_byte_array() == expected.to_byte_array(), drawing + " sibling corners remain independent")
		var old_rest: Vector3 = leg.ankle_rest
		leg.ankle_rest += Vector3(0.03125, -0.015625, 0.0625)
		check(first.gait._sole_footprint(index).to_byte_array() == reference(rig, index, initial).to_byte_array(), drawing + " changed ankle rest misses")
		leg.ankle_rest = old_rest
		leg.rest_sole = initial + Vector3(-0.25, -0.125, 0.0625)
		check(first.gait._sole_footprint(index).to_byte_array() == reference(rig, index, leg.rest_sole).to_byte_array(), drawing + " changed initial sole misses")
		leg.rest_sole = initial
		var old_ankle: int = leg.ankle
		leg.ankle = -1
		check(first.gait._sole_footprint(index).to_byte_array() == reference(rig, index, initial).to_byte_array(), drawing + " changed ankle index misses")
		leg.ankle = old_ankle
		var stored: PackedVector3Array = data.footprints[index].corners
		var incompatible := stored.duplicate()
		incompatible[0] += Vector3.ONE
		data.footprints[index].corners = incompatible
		rig.civilian_mode = not rig.civilian_mode
		check(first.gait._sole_footprint(index).to_byte_array() == expected.to_byte_array(), drawing + " opposite civilian discriminator cannot hit incompatible cached data")
		rig.civilian_mode = not rig.civilian_mode
		data.footprints[index].corners = stored
		check(data.footprints[index].signature == signature, drawing + " unsupported signatures do not grow or replace cache")
		leg.rest_sole = saved_sole
	# Cached final ArrayMeshes are immutable. A replacement may vary geometry;
	# in-place mutation of a shared cached mesh is outside the existing rig contract.
	var changed := ArrayMesh.new()
	for surface in before.size():
		var arrays: Array = before[surface].duplicate()
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		for i in positions.size():
			positions[i] += Vector3(0.125, -0.25, 0.5)
		arrays[Mesh.ARRAY_VERTEX] = positions
		changed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	rig.mesh.mesh = changed
	for index in 2:
		var leg: Dictionary = rig.legs[index]
		var saved: Vector3 = leg.rest_sole
		leg.rest_sole = data.soles[index]
		check(first.gait._sole_footprint(index).to_byte_array() == reference(rig, index, leg.rest_sole).to_byte_array(), drawing + " changed final mesh identity/geometry misses")
		leg.rest_sole = saved
	rig.mesh.mesh = original
	for surface in before.size():
		check(original.surface_get_arrays(surface) == before[surface], drawing + " original arrays/bones/weights immutable")
	first.gait._feet[0].plant = Vector3(2, 3, 4)
	check(second.gait._feet[0].plant == Vector3.ZERO, drawing + " planted foot state independent")
	var cached_before: Vector3 = data.soles[0]
	rig.legs[0].rest_sole += Vector3.ONE
	check(data.soles[0] == cached_before, drawing + " mutable actor sole does not change cached bind sole")
	var first_weak: WeakRef = weakref(first.get_parent())
	var second_weak: WeakRef = weakref(second.get_parent())
	first.get_parent().free()
	second.get_parent().free()
	check(first_weak.get_ref() == null and second_weak.get_ref() == null, drawing + " cache retains no actor")
# Independent pre-cache oracle, preserving decoded committed arrays and operation order.
func reference(rig, index: int, initial: Vector3) -> PackedVector3Array:
	var leg: Dictionary = rig.legs[index]
	var low := initial
	var high := initial
	for surface in rig.mesh.mesh.get_surface_count():
		var arrays: Array = rig.mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in vertices.size():
			for slot in 4:
				var influence := vertex * 4 + slot
				if bones[influence] == leg.ankle and weights[influence] > 0.5:
					low = low.min(vertices[vertex])
					high = high.max(vertices[vertex])
	return PackedVector3Array([Vector3(low.x, low.y, low.z) - leg.ankle_rest,
		Vector3(low.x, low.y, high.z) - leg.ankle_rest,
		Vector3(high.x, low.y, low.z) - leg.ankle_rest,
		Vector3(high.x, low.y, high.z) - leg.ankle_rest])
