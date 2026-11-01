extends SceneTree
## Source-pose and solid-cloth regressions. GPU art remains a separate check.
const Models = preload("res://game/characters/models/civilian_model.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("IP01_HERO_DETAILS: " + message)

func _run() -> void:
	_granny_ribbon()
	_vendor_hands()
	print("IP01_HERO_DETAILS: %d checks, %d failures; GPU appearance NOT_RUN" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _granny_ribbon() -> void:
	var model := Models.new().build_model("babka")
	var mesh: ArrayMesh = model.get_node("Skeleton3D/UniformMesh").mesh
	var triangles := []
	var occluders := []
	var adjacency := {}
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for index in range(0, points.size(), 3):
			var center := (points[index] + points[index + 1] + points[index + 2]) / 3.0
			if mesh.surface_get_name(surface) == "trim" and bones[index * 4] == 2 and center.y > 0.55:
				triangles.append([points[index], points[index + 1], points[index + 2]])
				for edge in 3:
					var a := _key(points[index + edge])
					var b := _key(points[index + (edge + 1) % 3])
					if not adjacency.has(a): adjacency[a] = []
					if not adjacency.has(b): adjacency[b] = []
					adjacency[a].append(b)
					adjacency[b].append(a)
			elif mesh.surface_get_name(surface) in ["cloth", "skin"]:
				occluders.append([points[index], points[index + 1], points[index + 2]])
	_check(not triangles.is_empty(), "grandmother has front white jabot geometry")
	var components := 0
	var visited := {}
	for start: Vector3i in adjacency:
		if visited.has(start): continue
		components += 1
		var todo := [start]
		while not todo.is_empty():
			var point: Vector3i = todo.pop_back()
			if visited.has(point): continue
			visited[point] = true
			for neighbor: Vector3i in adjacency[point]: todo.append(neighbor)
	_check(components == 1, "jabot is one connected cloth ribbon, rather than separate beads")
	var behind := 0
	var visible_from_back := 0
	for index in range(0, triangles.size(), maxi(1, triangles.size() / 16)):
		var triangle: Array = triangles[index]
		var center: Vector3 = (triangle[0] + triangle[1] + triangle[2]) / 3.0
		if center.z >= 0.0: behind += 1
		var covered := false
		for body: Array in occluders:
			var hit = Geometry3D.ray_intersects_triangle(center + Vector3.BACK * 5.0, Vector3.FORWARD, body[0], body[1], body[2])
			if hit != null and hit.z > center.z + 0.001:
				covered = true
				break
		if not covered: visible_from_back += 1
	_check(behind == 0, "jabot does not wrap behind the neck")
	_check(visible_from_back == 0, "head and dress occlude the whole front ribbon from behind")
	model.free()

func _key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * 100000), roundi(point.y * 100000), roundi(point.z * 100000))

func _vendor_hands() -> void:
	var model := Models.new().build_model("vendor")
	var skeleton: Skeleton3D = model.get_node("Skeleton3D")
	var mesh: ArrayMesh = skeleton.get_node("UniformMesh").mesh
	for bone: int in [6, 9]:
		var center := Vector3.ZERO
		var count := 0
		for surface in mesh.get_surface_count():
			if mesh.surface_get_name(surface) != "skin": continue
			var arrays := mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for index in points.size():
				if bones[index * 4] != bone: continue
				center += points[index]
				count += 1
		center /= maxf(count, 1)
		_check(count > 100, "vendor retains substantial hand volume")
		_check(absf(center.x) < 0.18 and center.y > 0.37 and center.y < 0.45 and center.z < -0.14, "vendor palm rests in front of the apron at the authored SVG pose")
		_check(center.distance_to(skeleton.get_bone_global_rest(bone).origin) < 0.06, "vendor hand joint follows the actual bent-arm palm")
	model.free()
