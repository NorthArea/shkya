extends SceneTree
## Tests rendered body-space geometry against the exterior shell, not a virtual floor.
const Clearance = preload("res://tests/skinned_clearance.gd")
const Lada = preload("res://game/vehicles/lada_visual.gd")
const Driver = preload("res://game/vehicles/lada_driver.gd")
const GEOMETRY_EPS_M := 0.001
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	var car := Lada.build()
	root.add_child(car)
	var driver: Node = car.get_node("Body/Driver")
	if driver.sprite != null:
		_sprite_driver(car, driver)
	else:
		_skinned_driver(car, driver)
	for model: StringName in Lada.SEDANS:
		var spec: Dictionary = Lada.SEDANS[model]
		var body: Mesh = Lada.sedan_meshes(model)["body"]
		var slab_triangles := 0
		var roof_triangles := 0
		var hood_triangles := 0
		var boot_triangles := 0
		var interior_floor := INF
		for surface in body.get_surface_count():
			if body.get_meta("slots")[surface] != "paint":
				continue
			var vertices: PackedVector3Array = body.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for index in range(0, vertices.size(), 3):
				var a := vertices[index]
				var b := vertices[index + 1]
				var c := vertices[index + 2]
				var centre := (a + b + c) / 3.0
				if absf(centre.x) < 0.6 and absf(centre.z) < 0.6 and centre.y > 1.38:
					roof_triangles += 1
				if centre.z < -1.30 and centre.y > 0.85: hood_triangles += 1
				if centre.z > 1.30 and centre.y > 0.85: boot_triangles += 1
				if centre.z > -0.60 and centre.z < 0.60 and absf(centre.x) < 0.6 and centre.y > 0.90 and centre.y < 1.05:
					slab_triangles += 1
		check(slab_triangles == 0, String(model) + " has no painted lid through the middle of the cabin: %d" % slab_triangles)
		check(roof_triangles > 0 and hood_triangles > 0 and boot_triangles > 0, String(model) + " retains the roof, bonnet and boot around its open cabin")
		var interior: Mesh = Lada.sedan_meshes(model)["interior"]
		for surface in interior.get_surface_count():
			var vertices: PackedVector3Array = interior.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point in vertices:
				interior_floor = minf(interior_floor, point.y)
		check(interior_floor >= 0.30, String(model) + " cabin floor is inside the exterior body")
	car.free()
	print("CAR01_CABIN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _sprite_driver(car: Node3D, driver: Node3D) -> void:
	var sprite: Sprite3D = driver.sprite
	check(sprite.region_enabled, "SVG driver clips legs instead of shrinking the hero")
	var standing_canvas: float = preload("res://game/characters/character_catalog.gd").canvas_height_for("ilyusha", 1.60)
	check(absf(sprite.pixel_size * sprite.texture.get_height() - standing_canvas) < 0.001, "seated body retains independently requested 160cm intrinsic scale")
	for view: String in ["front", "back", "side"]:
		var texture: Texture2D = load("res://assets/art/characters/ilyusha_%s_idle.svg" % view)
		var image := texture.get_image().get_region(Rect2i(sprite.region_rect))
		var alpha := image.get_used_rect()
		var region_height := sprite.region_rect.size.y
		var floor_y: float = driver.position.y + sprite.position.y + (region_height * 0.5 - alpha.end.y) * sprite.pixel_size
		var head_y: float = driver.position.y + sprite.position.y + (region_height * 0.5 - alpha.position.y) * sprite.pixel_size
		check(floor_y >= 0.32, view + ": cropped opaque body stays above cabin floor")
		check(head_y >= 1.20 and head_y <= 1.355, view + ": opaque head remains visible below roof lining")
	check(car.get_node("Body/Interior") != null, "local SVG fallback retains accepted sedan interior")
	check(Driver.uses_3d(), "shared hull/interior selector stays on the existing 3D path")

func _skinned_driver(car: Node3D, driver: Node) -> void:
	var visual: Node = driver.uniform_visual
	visual.skeleton.force_update_all_bone_transforms()
	var low := Vector3.INF
	var high := -Vector3.INF
	var outside_width := 0
	var body_points := PackedVector3Array()
	var body_sources: Array[Dictionary] = []
	for surface in visual.uniform_mesh.mesh.get_surface_count():
		var arrays: Array = visual.uniform_mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			var posed := Vector3.ZERO
			for influence in 4:
				var slot := index * 4 + influence
				var bind := bones[slot]
				var bone: int = visual.uniform_mesh.skin.get_bind_bone(bind)
				posed += (visual.skeleton.get_bone_global_pose(bone) * visual.uniform_mesh.skin.get_bind_pose(bind) * vertices[index]) * weights[slot]
			posed = car.get_node("Body").to_local(visual.uniform_mesh.to_global(posed))
			body_points.append(posed)
			var active_bones: Dictionary = {}
			for influence in 4:
				var slot := index * 4 + influence
				if weights[slot] > 0: active_bones[String(visual.skeleton.get_bone_name(visual.uniform_mesh.skin.get_bind_bone(bones[slot])))] = weights[slot]
			body_sources.append({"surface": visual.uniform_mesh.mesh.surface_get_name(surface), "vertex": index, "bind": str(vertices[index]), "weights": active_bones})
			low = low.min(posed)
			high = high.max(posed)
			var side_limit := lerpf(0.76, 0.645, clampf((posed.y - 0.98) / (1.40 - 0.98), 0, 1))
			if absf(posed.x) > side_limit: outside_width += 1
	print("CAR01_DRIVER_BOUNDS ", low, " .. ", high)
	check(low.y >= 0.31, "every actual skinned vertex stays above the exterior underbody and footwell")
	check(high.y <= 1.355 and high.y >= 1.20, "driver retains visible head below the roof lining")
	check(outside_width == 0, "driver stays inside cabin width")
	var player_spec: Dictionary = Lada.SEDANS[Lada.PLAYER_MODEL]
	var windscreen_bottom: Vector2 = player_spec["ws"][0]
	# Shared seat/steering contract permits the owner's agreed lateral relocation;
	# the actual ring geometry is independently checked below before clearance.
	var wheel_centre := Vector3(Driver.LADA_STEERING_X, float(player_spec["belt"]) + 0.13, windscreen_bottom.y + 0.30)
	_actual_interior(car, body_points, body_sources, wheel_centre)
	var clearance := Clearance.mesh_wheel_clearance(driver, car.get_node("Body"), wheel_centre, Vector3(0, 0.87, -0.50), 0.18, 0.014)
	print("CAR01_HEAD_WHEEL ", clearance)
	check(clearance.head_triangles > 0 and clearance.minimum_centreline_distance >= 0.019, "full skinned Ilyusha head clears the original steering wheel tube by 5mm")
	for index in 2:
		var hand: int = visual.skeleton.find_bone("hand_l" if index == 0 else "hand_r")
		var palm: Vector3 = visual.skeleton.get_bone_global_pose(hand) * Vector3(0, -0.034, -0.008)
		palm = car.get_node("Body").to_local(visual.model.to_global(palm))
		check(palm.distance_to(Driver.LADA_GRIPS[index]) <= 0.04, "actual posed palm retains the existing 4cm steering-grip bound")

func _actual_interior(car: Node3D, body_points: PackedVector3Array, body_sources: Array[Dictionary], wheel_centre: Vector3) -> void:
	var reference: Node3D = car.get_node("Body")
	var interior: MeshInstance3D = reference.get_node("Interior")
	var mesh := interior.mesh
	var wall_triangles: Array[PackedVector3Array] = []
	var cloth_triangles: Array[PackedVector3Array] = []
	var dark_points := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var slot: String = mesh.get_meta("slots")[surface]
		if slot not in ["dark", "cloth"]: continue
		var arrays := mesh.surface_get_arrays(surface)
		var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var vertices := PackedVector3Array()
		for point in raw: vertices.append(reference.to_local(interior.to_global(point)))
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for index in vertices.size(): indices.append(index)
		for offset in range(0, indices.size(), 3):
			var triangle := PackedVector3Array([vertices[indices[offset]], vertices[indices[offset + 1]], vertices[indices[offset + 2]]])
			if slot == "cloth":
				cloth_triangles.append(triangle)
			else:
				for point in triangle: dark_points.append(point)
				var cross := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])
				if cross.length() * .5 > .02: wall_triangles.append(triangle)
	var ring_present := true
	for index in 12:
		var angle := TAU * index / 12.0
		var centreline := wheel_centre + (Vector3.RIGHT * cos(angle) + Vector3(0, .87, -.50) * sin(angle)) * .18
		var nearest := INF
		for point in dark_points: nearest = minf(nearest, point.distance_to(centreline))
		ring_present = ring_present and nearest <= .015
	check(ring_present, "canonical relocated steering ring exists in actual interior mesh at all12 sections")
	check(not wall_triangles.is_empty() and not cloth_triangles.is_empty(), "actual cabin includes solid walls and seat geometry")
	var unique: Dictionary = {}
	var sources: Dictionary = {}
	for index in body_points.size():
		var point := body_points[index]
		var key := Vector3i(roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000))
		unique[key] = point
		sources[key] = body_sources[index]
	# Include every posed triangle centroid as well as every distinct skin vertex.
	for offset in range(0, body_points.size(), 3):
		var point := (body_points[offset] + body_points[offset + 1] + body_points[offset + 2]) / 3.0
		var key := Vector3i(roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000))
		unique[key] = point
		sources[key] = {"triangle_centroid_vertices": [body_sources[offset], body_sources[offset + 1], body_sources[offset + 2]]}
	var door_violations := 0
	var firewall_violations := 0
	var seat_core_depth := 0.0
	var deepest_point := Vector3.ZERO
	var deepest_triangle := PackedVector3Array()
	var deepest_source: Dictionary = {}
	var support_gap := INF
	for point: Vector3 in unique.values():
		var left := -INF
		var right := INF
		var firewall := -INF
		for triangle: PackedVector3Array in wall_triangles:
			var normal := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
			var centre := (triangle[0] + triangle[1] + triangle[2]) / 3.0
			if absf(normal.x) > .95 and absf(centre.x) > .5:
				var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3(-2, point.y, point.z), Vector3(2, point.y, point.z), triangle[0], triangle[1], triangle[2])
				if hit != null:
					if hit.x < 0: left = maxf(left, hit.x)
					else: right = minf(right, hit.x)
			if absf(normal.z) > .5 and centre.z < -.5:
				var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3(point.x, point.y, -2), Vector3(point.x, point.y, 2), triangle[0], triangle[1], triangle[2])
				if hit != null: firewall = maxf(firewall, hit.z)
		if point.x < left - GEOMETRY_EPS_M or point.x > right + GEOMETRY_EPS_M: door_violations += 1
		if point.z < firewall - GEOMETRY_EPS_M: firewall_violations += 1
		# All cloth components are closed seat solids. A skew ray avoids shared
		# rectangle diagonals; deduplicate coplanar hits before applying parity.
		if point.y > .9: continue
		var hits: Array[float] = []
		var nearest := INF
		var nearest_triangle := PackedVector3Array()
		for triangle: PackedVector3Array in cloth_triangles:
			var hit: Variant = Geometry3D.segment_intersects_triangle(point, point + Vector3(.123, .067, 1).normalized() * 5, triangle[0], triangle[1], triangle[2])
			if hit != null: hits.append(point.distance_to(hit))
			var distance := Clearance.point_triangle_distance(point, triangle[0], triangle[1], triangle[2])
			if distance < nearest:
				nearest = distance
				nearest_triangle = triangle
		hits.sort()
		var crossings := 0
		var previous := -INF
		for distance in hits:
			if distance - previous > .000001:
				crossings += 1
				previous = distance
		if crossings % 2 == 1 and nearest > seat_core_depth:
			seat_core_depth = nearest
			deepest_point = point
			deepest_triangle = nearest_triangle
			deepest_source = sources[Vector3i(roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000))]
		if point.y < .55 and absf(point.x - Driver.LADA_SEAT_X) < .23 and point.z > -.35 and point.z < .15:
			support_gap = minf(support_gap, nearest)
	print("CAR01_ACTUAL_INTERIOR ", JSON.stringify({"skin_vertex_and_centroid_samples": unique.size(), "door_violations": door_violations, "firewall_violations": firewall_violations, "maximum_seat_core_penetration_m": seat_core_depth, "deepest_body_point": str(deepest_point), "deepest_body_source": deepest_source, "nearest_seat_triangle": str(deepest_triangle), "seat_support_gap_m": support_gap}))
	check(door_violations == 0, "all actual skin vertices/triangle centres remain inside actual door lining")
	check(firewall_violations == 0, "all actual skin vertices/triangle centres remain behind actual toe-board/dashboard")
	check(seat_core_depth <= GEOMETRY_EPS_M, "actual body stays outside solid cushion/backrest core within1mm geometry tolerance")
	check(support_gap <= .01, "actual seated body contacts its real cushion within the existing1cm support tolerance")
