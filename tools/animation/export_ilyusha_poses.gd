extends SceneTree
## CPU export of the native modifier's final skin for internal Blender previews.
## It does not render, open windows, or substitute a second runtime body.
const Uniform = preload("res://game/characters/uniform_visual.gd")
const OUTPUT := "res://builds/checks/ART-01-imported-hero/animated-poses"
var _final: Array[Transform3D] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for speed: float in [4.0, 8.0]:
		var visual := Uniform.new()
		visual.configure("ilyusha", 1.765, Color.WHITE)
		root.add_child(visual)
		var hero := visual.imported_hero
		hero.set_process(false)
		hero.skeleton.skeleton_updated.connect(func():
			_final.resize(hero.skeleton.get_bone_count())
			for bone in hero.skeleton.get_bone_count():
				_final[bone] = hero.skeleton.get_bone_global_pose(bone))
		await process_frame
		var captured := {}
		for frame in 360:
			visual.position.z -= speed / 120.0
			visual.update_locomotion(Vector3(0, 0, -speed), true, &"locomotion", 1.0 / 120.0)
			hero._sample(1.0 / 120.0)
			await process_frame
			if frame < 30:
				continue
			var phase: float = hero._cycle_phase
			for quarter in 4:
				if captured.has(quarter) or absf(phase - float(quarter) / 4.0) > 0.025:
					continue
				var path := OUTPUT + "/speed%d_phase%d.json" % [speed, quarter]
				_export_skin(hero, path, phase, speed)
				captured[quarter] = true
			if captured.size() == 4:
				break
		visual.free()
	quit()

func _export_skin(hero: Node3D, path: String, phase: float, speed: float) -> void:
	var mesh: ArrayMesh = hero.uniform_mesh.mesh
	var skin: Skin = hero.uniform_mesh.skin
	var binds: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if not skin.get_bind_name(bind).is_empty():
			bone = hero.skeleton.find_bone(skin.get_bind_name(bind))
		binds.append(_final[bone] * skin.get_bind_pose(bind))
	var surfaces: Array[Dictionary] = []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var influences := 8 if mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
		var positions_out: Array[float] = []
		var normals_out: Array[float] = []
		for vertex in vertices.size():
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			for influence in influences:
				var slot := vertex * influences + influence
				point += binds[bones[slot]] * vertices[vertex] * weights[slot]
				normal += binds[bones[slot]].basis.inverse().transposed() * normals[vertex] * weights[slot]
			normal = normal.normalized()
			positions_out.append_array([point.x, point.y, point.z])
			normals_out.append_array([normal.x, normal.y, normal.z])
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		surfaces.append({"name": material.resource_name, "color": [material.albedo_color.r, material.albedo_color.g, material.albedo_color.b, material.albedo_color.a], "positions": positions_out, "normals": normals_out, "indices": Array(indices)})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"speed": speed, "phase": phase, "stride": hero._cycle_stride, "cadence_steps_per_second": 2.0 * speed / hero._cycle_stride, "surfaces": surfaces}))
	print("EXPORTED ", path, " phase=", phase, " cadence=", 2.0 * speed / hero._cycle_stride)
