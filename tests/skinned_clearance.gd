extends RefCounted
## CPU surface clearance: a 12-segment vehicle wheel against actual Skin triangles.
static func point_triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() <= 1e-18:
		return minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)), minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, b, c)), point.distance_to(Geometry3D.get_closest_point_to_segment(point, c, a))))
	normal = normal.normalized()
	var projection := point - normal * normal.dot(point - a)
	if (b - a).cross(projection - a).dot(normal) >= -1e-10 and (c - b).cross(projection - b).dot(normal) >= -1e-10 and (a - c).cross(projection - c).dot(normal) >= -1e-10:
		return point.distance_to(projection)
	return minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)), minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, b, c)), point.distance_to(Geometry3D.get_closest_point_to_segment(point, c, a))))
static func segment_triangle_distance(first: Vector3, second: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	if Geometry3D.segment_intersects_triangle(first, second, a, b, c) != null:
		return 0.0
	var closest := minf(point_triangle_distance(first, a, b, c), point_triangle_distance(second, a, b, c))
	for edge: Array in [[a, b], [b, c], [c, a]]:
		var points := Geometry3D.get_closest_points_between_segments(first, second, edge[0], edge[1])
		closest = minf(closest, points[0].distance_to(points[1]))
	return closest

static func mesh_wheel_clearance(actor: Node3D, reference: Node3D,
		centre := Vector3(-0.6, 1.97, -5.35), axis := Vector3(0, 0.35, -0.94),
		radius := 0.24, tube_radius := 0.018) -> Dictionary:
	var visual: Node = actor.uniform_visual
	var skeleton: Skeleton3D = visual.skeleton
	var mesh: MeshInstance3D = visual.uniform_mesh
	var segments: Array = []
	for index in 12:
		var angle := TAU * index / 12.0
		var next := TAU * (index + 1) / 12.0
		segments.append([centre + (Vector3.RIGHT * cos(angle) + axis * sin(angle)) * radius, centre + (Vector3.RIGHT * cos(next) + axis * sin(next)) * radius])
	var closest := INF
	var crossed := 0
	var nearest_surface := ""
	var nearest_triangle := PackedVector3Array()
	var nearest_segment := -1
	var triangles := 0
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var posed := PackedVector3Array()
		var head_flags: Array[bool] = []
		for index in vertices.size():
			var head := false
			var point := Vector3.ZERO
			for influence in 4:
				var slot := index * 4 + influence
				if weights[slot] <= 0.0: continue
				var bind := bones[slot]
				var bone := mesh.skin.get_bind_bone(bind)
				point += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[index]) * weights[slot]
				head = head or (skeleton.get_bone_name(bone) == "head" and weights[slot] > 0.5)
			posed.append(reference.to_local(mesh.to_global(point)))
			head_flags.append(head)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for index in vertices.size(): indices.append(index)
		for index in range(0, indices.size(), 3):
			if not (head_flags[indices[index]] or head_flags[indices[index + 1]] or head_flags[indices[index + 2]]): continue
			var a := posed[indices[index]]
			var b := posed[indices[index + 1]]
			var c := posed[indices[index + 2]]
			triangles += 1
			for segment_index in segments.size():
				var segment: Array = segments[segment_index]
				var distance := segment_triangle_distance(segment[0], segment[1], a, b, c)
				if distance < closest:
					closest = distance
					nearest_surface = mesh.mesh.surface_get_name(surface)
					nearest_triangle = PackedVector3Array([a, b, c])
					nearest_segment = segment_index
				if distance == 0.0:
					crossed += 1
	return {"head_triangles": triangles, "wheel_tube_radius": tube_radius, "minimum_centreline_distance": closest, "ring_surface_crossings": crossed, "nearest_surface": nearest_surface, "nearest_head_triangle": str(nearest_triangle), "nearest_wheel_segment": nearest_segment}
