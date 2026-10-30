extends SceneTree

const Layout = preload("res://game/world/layout.gd")
const RoadShader = preload("res://game/world/shaders/road.gdshader")
var main: Node
var world: DemoWorld
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	var geometry: Node = world.get_node("LevelGeometry")
	var roads: Array[MeshInstance3D] = []
	for child in geometry.get_children():
		if child is MeshInstance3D and child.material_override is ShaderMaterial and child.material_override.shader == RoadShader:
			roads.append(child)
	check(roads.size() == 1, "the arena road is one surface without coplanar corner overlays")
	if not roads.is_empty():
		var material: ShaderMaterial = roads[0].material_override
		check(material.get_shader_parameter("global_ruts") == true, "the arena uses a shared world-space rut field")
		var bounds = material.get_shader_parameter("lane_bounds")
		var radii = material.get_shader_parameter("lane_radii")
		if check(bounds is PackedVector4Array and bounds.size() == 2 and radii is Vector2,
			"the road material receives the two actual rounded lane descriptors"):
			var traffic: Node = geometry.get_node("Traffic")
			_check_lane(traffic.path, bounds[0], radii.x)
			_check_lane(traffic.car_path, bounds[1], radii.y)
		if roads.size() == 1:
			_check_mesh(roads[0])
			check(roads[0].find_children("*", "CollisionObject3D", true, false).is_empty(), "road dressing adds no physics bodies")
	check(not geometry.get_node("Traffic").vehicles.is_empty(), "the actual traffic remains connected")
	await _finish()

func _check_lane(lane: PathVehicle.LanePath, bounds: Vector4, radius: float) -> void:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in lane.points:
		var p := Vector2(point.x, point.z)
		low = low.min(p)
		high = high.max(p)
	var expected := Vector4((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, (high.x - low.x) * 0.5, (high.y - low.y) * 0.5)
	check(bounds.is_equal_approx(expected) and is_equal_approx(radius, lane.radius), "rut descriptor matches the actual vehicle lane")
	var worst := 0.0
	var supported := true
	for i in int(ceil(lane.length * 2.0)):
		var p3 := lane.position_at(float(i) * 0.5)
		var p := Vector2(p3.x, p3.z)
		worst = maxf(worst, absf(_rounded_distance(p, bounds, radius)))
		# The entire bend, not merely its rectangle intersection, must be on the visible road.
		var tangent := lane.direction_at(float(i) * 0.5)
		var right := Vector2(-tangent.z, tangent.x)
		for side: float in [-1.0, 1.0]:
			supported = supported and _on_road(p + right * 0.8)
	check(worst < 0.01, "the analytic field follows all straight sections and quarter-turn arcs (error %.4f m)" % worst)
	check(supported, "both wheel tracks stay inside the original road union throughout each bend")
	var continuous := true
	for arc: Vector2 in lane.arcs:
		for join: float in [arc.x, arc.y]:
			var before := lane.position_at(join - 0.02)
			var after := lane.position_at(join + 0.02)
			var a := Vector2(before.x, before.z)
			var b := Vector2(after.x, after.z)
			continuous = continuous and absf(_rounded_distance(a, bounds, radius) - _rounded_distance(b, bounds, radius)) < 0.01
	check(continuous, "the same field continues across every straight-to-arc join")

func _rounded_distance(point: Vector2, bounds: Vector4, radius: float) -> float:
	var q := (point - Vector2(bounds.x, bounds.y)).abs() - Vector2(bounds.z, bounds.w) + Vector2.ONE * radius
	return q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0) - radius

func _on_road(point: Vector2) -> bool:
	for surface in Layout.SURFACES:
		if surface[1] == "road" and Rect2(surface[2] - surface[3] * 0.5, surface[3]).grow(0.001).has_point(point):
			return true
	return false

func _check_mesh(road: MeshInstance3D) -> void:
	var faces := road.mesh.get_faces()
	var flat := not faces.is_empty()
	var faces_up := true
	var triangles: Array = []
	for i in range(0, faces.size(), 3):
		var tri := []
		for j in 3:
			var p: Vector3 = road.global_transform * faces[i + j]
			flat = flat and absf(p.y - 0.025) < 0.0001
			tri.append(Vector2(p.x, p.z))
		# Godot front faces use clockwise winding; XZ triangles facing up have a positive XZ cross product.
		faces_up = faces_up and (tri[1] - tri[0]).cross(tri[2] - tri[0]) > 0.0
		triangles.append(tri)
	check(flat, "the road has one continuous top at its original 0.025 m height")
	check(faces_up, "the road front faces are visible from above with Godot clockwise winding")
	var coverage := true
	var overlap := false
	for x in range(-99, 100, 4):
		for z in range(-124, 125, 4):
			var point := Vector2(float(x) + 0.173, float(z) + 0.287)
			var hits := 0
			for tri in triangles:
				if Geometry2D.point_is_inside_triangle(point, tri[0], tri[1], tri[2]): hits += 1
			coverage = coverage and ((hits > 0) == _on_road(point))
			overlap = overlap or hits > 1
	check(coverage, "the surface covers exactly the existing road union including all four junctions")
	check(not overlap, "road triangles never overlap or create texture-fighting patches")

func _frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
	return ok

func _finish() -> void:
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	print("ROAD01: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
