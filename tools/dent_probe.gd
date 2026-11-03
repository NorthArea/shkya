extends SceneTree
## Isolated dent timings; headless validates the probe only, native establishes GPU cost.
const Visual = preload("res://game/vehicles/lada_visual.gd")
const MIN_SPEED := 2.3
const RADIUS := 0.95
const MAX_DEPTH := 0.34
const ORIGINAL := &"vehicle_undamaged_mesh"
const Damage = preload("res://game/vehicles/vehicle_damage.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var visual := Visual.build()
	root.add_child(visual)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(5, 3, -7)
	camera.look_at(Vector3(0, 0.7, 0))
	await process_frame
	await process_frame
	for i in 12:
		if i % 3 == 0: Damage.reset(visual)
		var started := Time.get_ticks_usec()
		var changed := _timed_legacy_dent(visual, Vector3(0.6, 0.65, -2.03), Vector3.BACK, 12.0) if "legacy" in OS.get_cmdline_user_args() else Damage.dent(visual, Vector3(0.6, 0.65, -2.03), Vector3.BACK, 12.0)
		print("DENT_PROBE hit=%d first=%s elapsed_us=%d changed=%s renderer=%s" % [i, i % 3 == 0, Time.get_ticks_usec()-started, changed, RenderingServer.get_current_rendering_method()])
		await process_frame
	visual.queue_free()
	camera.queue_free()
	await process_frame
	quit()

func _timed_legacy_dent(visual: Node3D, world_contact: Vector3, inward_world: Vector3, closing_speed: float) -> bool:
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
	var stages := {"read": 0, "deform": 0, "upload_temporary": 0, "read_temporary": 0, "normals": 0, "normal_commit_read": 0, "upload_final": 0}
	var stage_start := Time.get_ticks_usec()
	var replacement := ArrayMesh.new()
	var changed := false
	for s in current.get_surface_count():
		stage_start = Time.get_ticks_usec()
		var arrays := current.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base_vertices: PackedVector3Array = original.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		stages["read"] += Time.get_ticks_usec() - stage_start
		stage_start = Time.get_ticks_usec()
		for i in vertices.size():
			# Original coordinates keep a second hit at the same body panel cumulative.
			var distance := base_vertices[i].distance_to(point)
			if distance >= RADIUS:
				continue
			var weight := pow(1.0 - distance / RADIUS, 2.0)
			var displacement := vertices[i] - base_vertices[i] + inward * depth * weight
			vertices[i] = base_vertices[i] + displacement.limit_length(MAX_DEPTH)
			changed = true
		stages["deform"] += Time.get_ticks_usec() - stage_start
		stage_start = Time.get_ticks_usec()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var temporary := ArrayMesh.new()
		temporary.add_surface_from_arrays(current.surface_get_primitive_type(s), arrays)
		stages["upload_temporary"] += Time.get_ticks_usec() - stage_start
		stage_start = Time.get_ticks_usec()
		var tool := SurfaceTool.new()
		tool.create_from(temporary, 0)
		stages["read_temporary"] += Time.get_ticks_usec() - stage_start
		stage_start = Time.get_ticks_usec()
		tool.generate_normals()
		stages["normals"] += Time.get_ticks_usec() - stage_start
		stage_start = Time.get_ticks_usec()
		var normals_mesh := tool.commit()
		var normals: PackedVector3Array = normals_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		stages["normal_commit_read"] += Time.get_ticks_usec() - stage_start
		stage_start = Time.get_ticks_usec()
		# SurfaceTool preserves the provider's vertex order (these meshes are unindexed).
		if normals.size() == vertices.size():
			arrays[Mesh.ARRAY_NORMAL] = normals
		replacement.add_surface_from_arrays(current.surface_get_primitive_type(s), arrays)
		replacement.surface_set_material(s, current.surface_get_material(s))
		stages["upload_final"] += Time.get_ticks_usec() - stage_start
		stage_start = Time.get_ticks_usec()
	stages["upload_final"] += Time.get_ticks_usec() - stage_start
	stage_start = Time.get_ticks_usec()
	print("DENT_STAGES_US ", stages)
	if not changed:
		return false
	replacement.set_meta("slots", current.get_meta("slots", []))
	part.mesh = replacement
	visual.set_meta("vehicle_dent_count", int(visual.get_meta("vehicle_dent_count", 0)) + 1)
	return true
