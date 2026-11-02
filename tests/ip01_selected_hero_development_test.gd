extends SceneTree
## Development checks for the selected sheet04; independent acceptance is separate.
const Models = preload("res://game/characters/models/civilian_model.gd")
const Catalog = preload("res://game/characters/character_catalog.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SELECTED_HERO: " + label)

func _run() -> void:
	check(Catalog.ILYUSHA_VISIBLE_HEIGHT_M == Catalog.RF_ADULT_MALE_REFERENCE_M, "hero uses the sourced adult male height")
	var model := Models.new().build_model("ilyusha")
	root.add_child(model)
	check(model.get_meta("concept_reference", "") == "04.png", "current hero is the selected independent concept04")
	var skeleton: Skeleton3D = model.get_node("Skeleton3D")
	var instance: MeshInstance3D = skeleton.get_node("UniformMesh")
	check(skeleton.get_bone_count() == 14 and instance.skin.get_bind_count() == 14, "author14 contract remains intact")
	skeleton.force_update_all_bone_transforms()
	var mesh := instance.mesh as ArrayMesh
	var rest_error := 0.0
	var blend_count := 0
	var dark_cloth := 0
	var green_cloth := 0
	var head_min := Vector3.INF
	var head_max := -Vector3.INF
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for vertex in vertices.size():
			var point := Vector3.ZERO
			var total := 0.0
			for influence in 4:
				var slot := vertex * 4 + influence
				total += weights[slot]
				if weights[slot] <= 0: continue
				var bone := instance.skin.get_bind_bone(bones[slot])
				point += skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bones[slot]) * vertices[vertex] * weights[slot]
			if weights[vertex * 4 + 1] > 0: blend_count += 1
			rest_error = maxf(rest_error, point.distance_to(vertices[vertex]))
			check(absf(total - 1.0) < 0.00005, "skin weights sum to one")
			if mesh.surface_get_name(surface) == "cloth":
				if colors[vertex].g > colors[vertex].r * 1.3: green_cloth += 1
				if colors[vertex].r < .4 and colors[vertex].g < .4: dark_cloth += 1
			if bones[vertex * 4] == 3:
				head_min = head_min.min(vertices[vertex])
				head_max = head_max.max(vertices[vertex])
	check(rest_error < 0.00005, "skinned rest equals authored bind geometry")
	check(blend_count > 100, "elbows knees and hips have actual blended weights")
	check(dark_cloth > 500 and green_cloth == 0, "graphite coat replaces former green clothes")
	check(head_max.z - head_min.z > .14, "head has real profile depth")
	check(absf(mesh.get_aabb().position.y) < .00001 and absf(mesh.get_aabb().end.y - 1.0) < .00001, "authored soles0 top1")
	model.free()
	print("SELECTED_HERO_DEVELOPMENT: %d checks, %d failures; likeness/GPU not accepted" % [checks, failures])
	quit(0 if failures == 0 else 1)
