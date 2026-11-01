extends SceneTree
## Independent door-component acceptance. No boarding, GPU or native-FPS verdict.
const Lada = preload("res://game/vehicles/lada_visual.gd")
const Door = preload("res://game/vehicles/lada_door_visual.gd")
const Damage = preload("res://game/vehicles/vehicle_damage.gd")
const EPS := 0.00002
const NORMAL_EPS := 0.0002 # Godot's independent ArrayMesh normal packing roundtrip.
const SWEEP_LAYER := 1 << 19
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func _ticks(count := 2) -> void:
	for _frame in count:
		await physics_frame
		await process_frame

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(2))
	var car := Lada.build(Color(0.7, 0.6, 0.4), "", true, 0.0, 0.0)
	var neighbour := Lada.build(Color(0.4, 0.6, 0.7), "", false, 0.0, 0.0)
	root.add_child(car)
	root.add_child(neighbour)
	car.get_node("Motion").set_process(false)
	neighbour.position.x = 8.0
	var body: Node3D = car.get_node("Body")
	var canonical := _canonical(car)
	var original := _snapshot(canonical)
	var other_original := _snapshot(_canonical(neighbour))
	check(canonical[0].mesh == neighbour.get_node("Body/BodyMesh").mesh, "fixture uses the same cached sedan mesh in an independent neighbour")
	check(neighbour.get_node_or_null("Body/OccupantDoor") == null, "ordinary sedan construction does not attach the player door to neighbours")
	var baseline_points := _point_set(canonical, body)
	var source_attributes := _source_attributes(canonical)
	_aperture_preconditions(canonical, body)
	var door: Node3D = Door.attach(car)
	var node_count := car.find_children("*", "Node", true, false).size()
	for _repeat in 4:
		check(Door.attach(car) == door, "repeated attach returns the existing player door")
	check(car.find_children("*", "Node", true, false).size() == node_count, "repeated attach adds no extra scene nodes")
	check(_same_snapshot(canonical, original), "attaching preserves canonical mesh pointers, every array, materials and visibility")
	var closed: Dictionary = door.anchors()
	for name_: StringName in [&"hinge", &"handle", &"aperture", &"seat", &"approach"]:
		check(closed.has(name_) and closed[name_] is Transform3D and closed[name_].is_finite(), "public world anchor exists and is finite: " + String(name_))
	check(closed[&"seat"].is_equal_approx(car.get_node("Body/Driver").global_transform), "seat anchor comes from the actual seated Driver transform")
	var hinge: Vector3 = body.to_local(closed[&"hinge"].origin)
	var handle: Vector3 = body.to_local(closed[&"handle"].origin)
	check(hinge.x < -0.60 and hinge.z < -0.45 and handle.z > hinge.z + 0.5, "driver-side hinge is at the front and handle is behind it on the left")
	check(body.to_local(closed[&"approach"].origin).x < -1.0, "approach anchor is outside the left side of the real body")
	door.set_open_fraction(-1.0)
	check(door.open_fraction() == 0.0, "negative opening clamps to the closed state")
	door.set_open_fraction(0.4)
	var intermediate: Dictionary = door.anchors()
	door.set_open_fraction(2.0)
	check(door.open_fraction() == 1.0, "opening above one clamps to fully open")
	var opened: Dictionary = door.anchors()
	check(opened[&"hinge"].origin.distance_to(closed[&"hinge"].origin) <= EPS, "opening retains the actual hinge origin")
	check(body.to_local(opened[&"handle"].origin).x < body.to_local(intermediate[&"handle"].origin).x - 0.1 and body.to_local(intermediate[&"handle"].origin).x < handle.x - 0.1, "actual handle moves outward to negative Body X as the front-left door opens")
	for name_: StringName in [&"aperture", &"seat", &"approach"]:
		check(opened[name_].is_equal_approx(closed[name_]), "opening does not move the fixed " + String(name_) + " anchor")
	var visible := _visible_parts(canonical, door)
	node_count = car.find_children("*", "Node", true, false).size()
	check(not canonical[0].visible and not canonical[1].visible and not canonical[2].visible, "open rendering uses derived geometry while canonical damage sources remain present")
	check(_same_snapshot(canonical, original, false), "opening never cuts or edits canonical source mesh arrays or material overrides")
	_aperture_clear(visible, body)
	_protected_geometry(visible, body, baseline_points)
	_structural_posts(visible, body, canonical[0])
	_moving_mirror(visible, body, baseline_points, closed, opened)
	_derived_attributes(visible, body, source_attributes, closed, opened)
	await _sweep_geometry(car, door, body)
	_follow_body_transform(car, door, body)
	door.set_open_fraction(1.0)
	var open_signature := _positions_hash(_visible_parts(canonical, door), body)
	var damaged := Damage.dent(car, body.to_global(Vector3(-0.8, 0.70, -0.28)), body.global_basis * Vector3.RIGHT, 8.0)
	check(damaged and canonical[0].mesh != original[0].mesh, "real VehicleDamage replaces the full canonical BodyMesh while the door is open")
	var damaged_mesh: Mesh = canonical[0].mesh
	await _ticks()
	check(_positions_hash(_visible_parts(canonical, door), body) != open_signature, "open visible derived geometry follows the new damaged source pointer")
	check(_same_snapshot(_canonical(neighbour), other_original), "opening and damage do not edit neighbouring cached geometry or materials")
	door.reset_closed()
	check(door.open_fraction() == 0.0 and canonical[0].mesh == damaged_mesh and canonical[0].visible and canonical[1].visible and canonical[2].visible, "reset closes onto the current damaged canonical source instead of an undamaged snapshot")
	check(_visible_parts(canonical, door).size() == 3, "closed rendering contains exactly the original three body parts")
	door.set_open_fraction(1.0)
	Damage.reset(car)
	await _ticks()
	check(canonical[0].mesh == original[0].mesh and _positions_hash(_visible_parts(canonical, door), body) == open_signature, "owner damage reset restores the original visible door geometry without a stale derived cache")
	for _repeat in 4:
		door.reset_closed()
		Door.attach(car)
	check(_same_snapshot(canonical, original), "repeated close/reset restores original pointers, arrays, materials and visibility exactly")
	check(car.find_children("*", "Node", true, false).size() == node_count, "animation, damage, attach and reset do not accumulate nodes")
	car.free()
	neighbour.free()
	await process_frame
	print("CHARACTER04_DOOR: %d checks, %d failures; boarding/GPU/native FPS NOT_RUN" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _canonical(car: Node3D) -> Array[MeshInstance3D]:
	return [car.get_node("Body/BodyMesh"), car.get_node("Body/Glass"), car.get_node("Body/Interior")]

func _snapshot(parts: Array[MeshInstance3D]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part: MeshInstance3D in parts:
		var arrays := []
		var materials := []
		for surface in part.mesh.get_surface_count():
			arrays.append(hash(part.mesh.surface_get_arrays(surface)))
			materials.append([part.mesh.surface_get_material(surface), part.get_surface_override_material(surface)])
		result.append({"mesh": part.mesh, "arrays": arrays, "materials": materials, "visible": part.visible, "transform": part.transform})
	return result

func _same_snapshot(parts: Array[MeshInstance3D], before: Array[Dictionary], visibility := true) -> bool:
	var now := _snapshot(parts)
	for index in parts.size():
		for key: String in ["mesh", "arrays", "materials", "transform"]:
			if now[index][key] != before[index][key]: return false
		if visibility and now[index].visible != before[index].visible: return false
	return true

func _gather(node: Node, parts: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.is_visible_in_tree() and node.mesh != null:
		parts.append(node)
	for child: Node in node.get_children():
		_gather(child, parts)

func _visible_parts(canonical: Array[MeshInstance3D], door: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for part: MeshInstance3D in canonical:
		if part.is_visible_in_tree(): result.append(part)
	_gather(door, result)
	return result

func _triangles(parts: Array[MeshInstance3D], body: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for part: MeshInstance3D in parts:
		var transform := body.global_transform.affine_inverse() * part.global_transform
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices != null and not indices.is_empty():
				for index: int in indices: result.append(transform * vertices[index])
			else:
				for vertex: Vector3 in vertices: result.append(transform * vertex)
	return result

func _ray_hits(triangles: PackedVector3Array, y: float, z: float) -> int:
	var hits := 0
	for index in range(0, triangles.size(), 3):
		if Geometry3D.segment_intersects_triangle(Vector3(-0.98, y, z), Vector3(-0.60, y, z), triangles[index], triangles[index + 1], triangles[index + 2]) != null:
			hits += 1
	return hits

func _aperture_preconditions(parts: Array[MeshInstance3D], body: Node3D) -> void:
	var outer := _triangles([parts[0]], body)
	var glass := _triangles([parts[1]], body)
	var lining := _triangles([parts[2]], body)
	for z: float in [-0.55, -0.30, -0.05]:
		check(_ray_hits(outer, 0.70, z) > 0 and _ray_hits(lining, 0.70, z) > 0, "closed fixture independently contains both outer door skin and inner lining at z=" + str(z))
		check(_ray_hits(glass, 1.12, z) > 0, "closed fixture independently contains driver-window glass at z=" + str(z))

func _aperture_clear(parts: Array[MeshInstance3D], body: Node3D) -> void:
	var triangles := _triangles(parts, body)
	for y: float in [0.60, 0.84, 1.12]:
		for z: float in [-0.55, -0.30, -0.05]:
			check(_ray_hits(triangles, y, z) == 0, "actual open aperture clears exterior/glass/lining at y=%.2f z=%.2f" % [y, z])
	check(_ray_hits(triangles, 0.35, -0.30) > 0, "the fixed threshold remains under the cleared doorway")

func _key(point: Vector3) -> String:
	return "%.5f/%.5f/%.5f" % [point.x, point.y, point.z]

func _point_set(parts: Array[MeshInstance3D], body: Node3D) -> Dictionary:
	var result := {}
	for point: Vector3 in _triangles(parts, body): result[_key(point)] = point
	return result

func _protected_geometry(parts: Array[MeshInstance3D], body: Node3D, original: Dictionary) -> void:
	var current := _point_set(parts, body)
	var missing := 0
	var missing_points: Array[Vector3] = []
	var protected_count := 0
	for key: String in original:
		var point: Vector3 = original[key]
		if point.x > 0.2 or point.z > 0.40 or point.z < -0.96 or point.y < 0.32 or (point.y > 1.44 and absf(point.x) < 0.60):
			protected_count += 1
			if not current.has(key):
				missing += 1
				if missing_points.size() < 8: missing_points.append(point)
	if not missing_points.is_empty(): print("CHARACTER04_PROTECTED_MISSING ", missing_points)
	check(protected_count > 100 and missing == 0, "right side, rear door, front body, roof and underbody retain their actual fixed vertices (%d missing)" % missing)

func _structural_posts(parts: Array[MeshInstance3D], body: Node3D, original_body: MeshInstance3D) -> void:
	var slots: Array = original_body.mesh.get_meta("slots", [])
	var paint: Material = original_body.get_active_material(slots.find("paint"))
	var closed := _material_triangles([original_body], body, paint)
	var opened := _material_triangles(parts, body, paint)
	var spec: Dictionary = Lada.SEDANS[Lada.PLAYER_MODEL]
	var bottom: Vector2 = spec["ws"][0]
	var top: Vector2 = spec["ws"][1]
	var sill := bottom.x + 0.005
	var eave := top.x - 0.02
	# These are the physical source tubes, whose mesh contains endpoint rings
	# rather than vertices at the middle of each tube. The mirror is not a post.
	var posts := {
		"A": [Vector3(-float(spec["glass_w"]), sill, bottom.y + 0.01), Vector3(-float(spec["roof_w"]), eave, top.y + 0.01)],
		"B": [Vector3(-float(spec["glass_w"]) - 0.003, sill, float(spec["b_z"])), Vector3(-float(spec["roof_w"]) - 0.003, eave, float(spec["b_z"]) + 0.02)]}
	for name_: String in posts:
		for fraction: float in [0.25, 0.5, 0.75]:
			var center := Vector3(posts[name_][0]).lerp(posts[name_][1], fraction)
			var start := center - Vector3.RIGHT * 0.12
			var finish := center + Vector3.RIGHT * 0.12
			var before := _segment_points(closed, start, finish)
			var after := _segment_points(opened, start, finish)
			check(before.size() >= 2, "closed source contains both painted walls of structural post %s at %.2f" % [name_, fraction])
			var preserved := before.size() == after.size()
			for index in mini(before.size(), after.size()):
				preserved = preserved and before[index].distance_to(after[index]) <= EPS
			check(preserved, "opening preserves exact painted structural post intersections %s at %.2f" % [name_, fraction])

func _material_triangles(parts: Array[MeshInstance3D], body: Node3D, material: Material) -> PackedVector3Array:
	var result := PackedVector3Array()
	for part: MeshInstance3D in parts:
		var transform := body.global_transform.affine_inverse() * part.global_transform
		for surface in part.mesh.get_surface_count():
			if part.get_active_material(surface) != material: continue
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices != null and not indices.is_empty():
				for index: int in indices: result.append(transform * vertices[index])
			else:
				for vertex: Vector3 in vertices: result.append(transform * vertex)
	return result

func _segment_points(triangles: PackedVector3Array, start: Vector3, finish: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for index in range(0, triangles.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(start, finish, triangles[index], triangles[index + 1], triangles[index + 2])
		if hit == null: continue
		var duplicate := false
		for point: Vector3 in result:
			if point.distance_to(hit) <= EPS: duplicate = true
		if not duplicate: result.append(hit)
	result.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	return result

func _moving_mirror(parts: Array[MeshInstance3D], body: Node3D, original: Dictionary, closed: Dictionary, opened: Dictionary) -> void:
	var spec: Dictionary = Lada.SEDANS[Lada.PLAYER_MODEL]
	var center := Vector3(-float(spec["half_w"]) - 0.11, float(spec["belt"]) + 0.06, float(spec["ws"][0].y) + 0.14)
	var pivot: Vector3 = body.to_local(closed[&"hinge"].origin)
	var before: Vector3 = body.to_local(closed[&"handle"].origin) - pivot
	var after: Vector3 = body.to_local(opened[&"handle"].origin) - pivot
	before.y = 0.0
	after.y = 0.0
	var rotation := Basis(Vector3.UP, before.signed_angle_to(after, Vector3.UP))
	var current := _point_set(parts, body)
	var count := 0
	var follows := 0
	var remains_closed := 0
	for key: String in original:
		var point: Vector3 = original[key]
		var delta := (point - center).abs()
		if delta.x > 0.04 or delta.y > 0.055 or delta.z > 0.08: continue
		count += 1
		if current.has(key): remains_closed += 1
		var expected := pivot + rotation * (point - pivot)
		var found := current.has(_key(expected))
		if not found:
			for candidate: Vector3 in current.values():
				if candidate.distance_to(expected) <= EPS:
					found = true
					break
		if found: follows += 1
	check(count >= 8 and follows == count and remains_closed == 0, "real driver mirror follows the moving door instead of being mistaken for a fixed A post")

func _source_attributes(parts: Array[MeshInstance3D]) -> Dictionary:
	var result := {}
	for part: MeshInstance3D in parts:
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for index in vertices.size():
				var entry := _attributes(part, surface, arrays, index)
				var key := _key(vertices[index])
				if not result.has(key): result[key] = []
				result[key].append(entry)
	return result

func _attributes(part: MeshInstance3D, surface: int, arrays: Array, index: int) -> Dictionary:
	var result := {"material": part.get_active_material(surface), "normal": Vector3.ZERO}
	if arrays[Mesh.ARRAY_NORMAL] != null: result.normal = arrays[Mesh.ARRAY_NORMAL][index]
	for channel: int in [Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		result[channel] = null if arrays[channel] == null or arrays[channel].is_empty() else arrays[channel][index]
	return result

func _derived_attributes(parts: Array[MeshInstance3D], body: Node3D, source: Dictionary, closed: Dictionary, opened: Dictionary) -> void:
	var pivot: Vector3 = body.to_local(closed[&"hinge"].origin)
	var before: Vector3 = body.to_local(closed[&"handle"].origin) - pivot
	var after: Vector3 = body.to_local(opened[&"handle"].origin) - pivot
	before.y = 0.0
	after.y = 0.0
	var rotation := Basis(Vector3.UP, before.signed_angle_to(after, Vector3.UP))
	var matched := 0
	var moving := 0
	var bad := 0
	for part: MeshInstance3D in parts:
		var transform := body.global_transform.affine_inverse() * part.global_transform
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for index in vertices.size():
				var point := transform * vertices[index]
				var candidates: Array = source.get(_key(point), [])
				var leaf := false
				if candidates.is_empty():
					candidates = source.get(_key(pivot + rotation.inverse() * (point - pivot)), [])
					leaf = not candidates.is_empty()
				if candidates.is_empty(): continue # New partition-boundary vertices have no original vertex counterpart.
				matched += 1
				if leaf: moving += 1
				var actual := _attributes(part, surface, arrays, index)
				actual.normal = transform.basis * Vector3(actual.normal)
				var valid := false
				for expected: Dictionary in candidates:
					var normal: Vector3 = rotation * Vector3(expected.normal) if leaf else expected.normal
					var same: bool = actual.material == expected.material and Vector3(actual.normal).distance_to(normal) <= NORMAL_EPS
					for channel: int in [Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
						same = same and actual[channel] == expected[channel]
					if same: valid = true
				if not valid: bad += 1
	check(matched > 100 and moving > 12 and bad == 0, "visible fixed and moving source vertices preserve materials, normals, colour and both UV channels (%d bad of %d, %d moving)" % [bad, matched, moving])

func _sweep_geometry(car: Node3D, door: Node3D, body: Node3D) -> void:
	door.set_open_fraction(0.2)
	var candidates: Array[MeshInstance3D] = []
	_gather(door, candidates)
	var before := {}
	for part: MeshInstance3D in candidates: before[part.get_instance_id()] = part.global_transform
	door.set_open_fraction(0.7)
	var moving: Array[MeshInstance3D] = []
	for part: MeshInstance3D in candidates:
		if not part.global_transform.is_equal_approx(before[part.get_instance_id()]): moving.append(part)
	check(not moving.is_empty(), "geometry oracle independently observes moving door renderers")
	var cloud: PackedVector3Array = door.sweep_vertices(0.0, 1.0)
	check(cloud.size() >= 8, "sweep exposes a nonempty conservative world point cloud")
	var sweep_body := StaticBody3D.new()
	sweep_body.collision_layer = SWEEP_LAYER
	sweep_body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = cloud
	collider.shape = shape
	sweep_body.add_child(collider)
	root.add_child(sweep_body)
	await _ticks()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.0005
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = SWEEP_LAYER
	query.margin = 0.0
	var outside := 0
	var sampled := 0
	for fraction: float in [0.0, 0.13, 0.37, 0.68, 0.91, 1.0]:
		door.set_open_fraction(fraction)
		for part: MeshInstance3D in moving:
			for surface in part.mesh.get_surface_count():
				var vertices: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for slot in mini(48, vertices.size()):
					var index := int(float(slot) * vertices.size() / mini(48, vertices.size()))
					query.transform = Transform3D(Basis.IDENTITY, part.to_global(vertices[index]))
					sampled += 1
					if car.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): outside += 1
	check(sampled > 30 and outside == 0, "convex sweep covers actual moving geometry at endpoints and intermediate angles (%d outside of %d)" % [outside, sampled])
	var cloud_local := PackedVector3Array()
	for point: Vector3 in cloud: cloud_local.append(body.to_local(point))
	var low := Vector3.INF
	var high := -Vector3.INF
	for point: Vector3 in cloud_local:
		low = low.min(point)
		high = high.max(point)
	check(low.x > -2.3 and high.x < -0.45 and low.z > -1.1 and high.z < 0.45, "sweep is bounded around the driver's front door rather than the whole vehicle")
	sweep_body.free()
	await _ticks()

func _follow_body_transform(car: Node3D, door: Node3D, body: Node3D) -> void:
	door.set_open_fraction(0.6)
	var before: Dictionary = door.anchors()
	var before_sweep: PackedVector3Array = door.sweep_vertices(0.15, 0.85)
	var old := body.global_transform
	car.position = Vector3(3, 0.1, -4)
	car.rotation.y = 0.67
	body.position = Vector3(0.04, 0.02, -0.03)
	body.rotation = Vector3(0.03, 0.12, -0.02)
	var after: Dictionary = door.anchors()
	var after_sweep: PackedVector3Array = door.sweep_vertices(0.15, 0.85)
	var change := body.global_transform * old.affine_inverse()
	for name_: StringName in before:
		check(after[name_].is_equal_approx(change * Transform3D(before[name_])), "world anchor follows the real translated/rotated Body: " + String(name_))
	var follows := before_sweep.size() == after_sweep.size() and not before_sweep.is_empty()
	for index in mini(before_sweep.size(), after_sweep.size()):
		follows = follows and after_sweep[index].distance_to(change * before_sweep[index]) <= EPS
	check(follows, "sweep point cloud follows the actual Body transform in world coordinates")

func _positions_hash(parts: Array[MeshInstance3D], body: Node3D) -> int:
	return hash(_triangles(parts, body))
