extends SceneTree
## No display/GPU: export actual skinned runtime geometry for the CPU z-buffer viewer.
## ./tools/godot.sh --headless --path . --script tools/capture/ip01_cpu_geometry.gd -- /absolute/output.json ilyusha babka vendor
const Uniform = preload("res://game/characters/uniform_visual.gd")
const Models = preload("res://game/characters/models/civilian_model.gd")
var records := {}
var references := {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var output := "res://builds/screenshots/IP-01/legacy-cpu/geometry.json" if args.is_empty() else args[0]
	var drawings: Array[String] = Models.DRAWINGS.duplicate()
	if args.size() > 1:
		drawings.clear()
		for index in range(1, args.size()): drawings.append(args[index])
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	for drawing: String in drawings:
		for view: String in ["front", "side", "back"]:
			var path := "res://assets/art/characters/%s_%s_idle.svg" % [drawing, view]
			if not FileAccess.file_exists(path): continue
			var reference := Image.new()
			if reference.load_svg_from_string(FileAccess.get_file_as_string(path)) != OK:
				push_error("Cannot rasterize approved reference " + path)
				quit(1)
				return
			reference.save_png(absolute.get_base_dir().path_join("reference_%s_%s.png" % [drawing, view]))
			references[path] = FileAccess.get_sha256(path)
		var visual := Uniform.new()
		visual.configure(drawing, 1.0, Color.WHITE)
		root.add_child(visual)
		for pose: String in ["rest", "walk_left", "walk_right", "lada"]:
			visual.reset_pose()
			if pose == "lada": visual.set_occupant_pose(&"lada")
			elif pose.begins_with("walk"):
				visual.update_walk(0.25 if pose == "walk_left" else 0.75, true, 0.0, 0.25)
			visual.skeleton.force_update_all_bone_transforms()
			records[drawing + "/" + pose] = _triangles(visual)
		visual.free()
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write CPU geometry export: " + absolute)
		quit(1)
		return
	file.store_string(JSON.stringify({"scope": "CPU adapter geometry only; no cabin placement or hand IK. Godot lighting, GPU rendering, world occlusion and gameplay are NOT_RUN", "source_sha256": {"civilian_model": FileAccess.get_sha256("res://game/characters/models/civilian_model.gd"), "uniform_visual": FileAccess.get_sha256("res://game/characters/uniform_visual.gd"), "legacy_resident_models": FileAccess.get_sha256("res://game/characters/models/legacy_resident_models.gd")}, "source_reference_sha256": references, "models": records}))
	file.close()
	print("IP01_CPU_GEOMETRY: %d skinned poses exported without a display; GPU appearance NOT_RUN" % records.size())
	quit()

func _triangles(visual: Node3D) -> Array:
	var mesh: ArrayMesh = visual.uniform_mesh.mesh
	var skeleton: Skeleton3D = visual.skeleton
	var triangles := []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var material: StandardMaterial3D = mesh.surface_get_material(surface)
		for index in range(0, vertices.size(), 3):
			var triangle := []
			for corner in 3:
				var slot := index + corner
				var point := Vector3.ZERO
				var normal := Vector3.ZERO
				for influence in 4:
					var offset := slot * 4 + influence
					if weights[offset] <= 0.0: continue
					var bind := bones[offset]
					var transform: Transform3D = skeleton.get_bone_global_pose(visual.uniform_mesh.skin.get_bind_bone(bind)) * visual.uniform_mesh.skin.get_bind_pose(bind)
					point += transform * vertices[slot] * weights[offset]
					normal += transform.basis * normals[slot] * weights[offset]
				normal = normal.normalized()
				var color := colors[slot] * material.albedo_color
				triangle.append([point.x, point.y, point.z, normal.x, normal.y, normal.z, color.r, color.g, color.b])
			triangles.append(triangle)
	return triangles
