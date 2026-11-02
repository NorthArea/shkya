extends SceneTree
## Independent selected04 body continuity: actual Player skin and Lada occupant.
## Complements unchanged LOC476/MOTION24/cabin oracles; no likeness/feel/GPU verdict.
const Player = preload("res://game/player/ilyusha.gd")
const Car = preload("res://game/vehicles/lada_visual.gd")
const Driver = preload("res://game/vehicles/lada_driver.gd")
const CONTACT_EPS_M := 0.001 # same numerical tolerance as actual-height acceptance
const SEAM_EPS_M := 0.0002 # existing CHAR07 skin-point tolerance
const DT := 1.0 / 60.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("SELECTED_HERO_BODY: " + label)

func _run() -> void:
	_oracle_selftest()
	var fixture := Node3D.new()
	root.add_child(fixture)
	var player := Player.new()
	player.input_enabled = false
	player.set_physics_process(false)
	fixture.add_child(player)
	var look: Node = player.visual.get_node("Look")
	look.set_physics_process(false)
	look.reset_pose()
	var visual: Node3D = look.uniform_visual
	_inspect(visual, "rest")
	for speed: float in [4.0, 8.0]:
		visual.reset_pose()
		for frame in 120:
			player.position += Vector3.FORWARD * speed * DT
			visual.update_locomotion(Vector3.FORWARD * speed, true, &"locomotion", DT)
			if frame >= 60 and frame % 15 == 0:
				_inspect(visual, "walk" if speed == 4.0 else "run", frame)
	var car := Car.build()
	fixture.add_child(car)
	var driver: Node3D = car.get_node("Body/Driver")
	_inspect(driver.uniform_visual, "Lada seated")
	_occupant_transitions(driver, fixture)
	fixture.free()
	await process_frame
	print("SELECTED_HERO_BODY: %d checks, %d failures; sampled CPU contact only; appearance/feel/GPU NOT_RUN" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _occupant_transitions(driver: Node3D, fixture: Node3D) -> void:
	var visual: Node = driver.uniform_visual
	var before := _posed_points(visual)
	var model_scale: Vector3 = visual.model.global_basis.get_scale()
	check(visual.skeleton.get_bone_count() == 16 and visual.author_skeleton.get_bone_count() == 14, "actual selected Lada uses walking16 while preserving author14")
	var xray: MeshInstance3D = visual.build_xray()
	visual.reset_pose()
	check(_delta(before, _posed_points(visual)) <= SEAM_EPS_M, "reset restores the same actual seat pose and cached steering grips")
	visual.set_lod(37.0, 3.0)
	check(visual.uniform_mesh.visibility_range_end == 37.0 and xray.mesh == visual.uniform_mesh.mesh and xray.skin == visual.uniform_mesh.skin and xray.get_node(xray.skeleton) == visual.skeleton, "seated LOD/xray stay bound to the active16 skin")
	visual.set_occupant_pose(&"trolley_standing")
	check(visual.skeleton.get_bone_count() == 14 and xray.get_node(xray.skeleton) == visual.skeleton and xray.mesh == visual.uniform_mesh.mesh, "16 to14 profile transition rebinds actual xray and mesh")
	visual.set_occupant_pose(&"lada")
	var frame_3d := driver.get_parent() as Node3D
	visual.reach_hands(visual.model.to_local(frame_3d.to_global(Driver.LADA_GRIPS[0])), visual.model.to_local(frame_3d.to_global(Driver.LADA_GRIPS[1])))
	check(visual.skeleton.get_bone_count() == 16 and xray.get_node(xray.skeleton) == visual.skeleton and xray.mesh == visual.uniform_mesh.mesh and xray.skin == visual.uniform_mesh.skin, "14 to16 transition restores selected Lada skin/xray")
	check(_delta(before, _posed_points(visual)) <= SEAM_EPS_M and model_scale.distance_to(visual.model.global_basis.get_scale()) < 0.00001, "16 to14 to16 preserves every actual seat vertex and intrinsic scale")
	visual.reset_pose()
	check(_delta(before, _posed_points(visual)) <= SEAM_EPS_M, "reset after profile changes restores steering grips without pose drift")
	var head: int = visual.skeleton.find_bone("head")
	check(visual.skeleton.get_bone_pose_position(head).is_equal_approx(visual.skeleton.get_bone_rest(head).origin), "seated head keeps its full rest neck translation")
	check(visual.skeleton.get_bone_global_pose(head).basis.is_equal_approx(Basis.IDENTITY), "seated face remains upright through natural counter-rotation")
	var fresh := Car.build()
	fixture.add_child(fresh)
	var twin: Node = fresh.get_node("Body/Driver").uniform_visual
	check(twin.skeleton != visual.skeleton and twin.author_skeleton.get_bone_count() == 14 and _delta(before, _posed_points(twin)) <= SEAM_EPS_M, "fresh cached factory gets an independent correctly seated16 instance")
	fresh.free()

func _posed_points(visual: Node) -> PackedVector3Array:
	var mesh: MeshInstance3D = visual.uniform_mesh
	var skeleton: Skeleton3D = visual.skeleton
	skeleton.force_update_all_bone_transforms()
	var points := PackedVector3Array()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			var point := Vector3.ZERO
			for influence in 4:
				var slot := index * 4 + influence
				if weights[slot] <= 0: continue
				point += (skeleton.get_bone_global_pose(mesh.skin.get_bind_bone(bones[slot])) * mesh.skin.get_bind_pose(bones[slot]) * vertices[index]) * weights[slot]
			points.append(mesh.to_global(point))
	return points

func _delta(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size(): return INF
	var maximum := 0.0
	for index in a.size(): maximum = maxf(maximum, a[index].distance_to(b[index]))
	return maximum

func _inspect(visual: Node3D, label: String, frame := 0) -> void:
	var instance: MeshInstance3D = visual.uniform_mesh
	var skeleton: Skeleton3D = visual.skeleton
	skeleton.force_update_all_bone_transforms()
	var bone_length_error := 0.0
	var bone_scale_error := 0.0
	for bone in skeleton.get_bone_count():
		# Pelvis travel is gait authority; limb/neck shortening and per-bone
		# scaling would hide a body/cabin mismatch despite equal model.scale.
		if skeleton.get_bone_name(bone) != "hips":
			bone_length_error = maxf(bone_length_error, absf(skeleton.get_bone_pose_position(bone).length() - skeleton.get_bone_rest(bone).origin.length()) * visual.model.global_basis.y.length())
		bone_scale_error = maxf(bone_scale_error, skeleton.get_bone_pose_scale(bone).distance_to(Vector3.ONE))
	check(bone_length_error <= SEAM_EPS_M and bone_scale_error <= 0.00001, "%s/%d: pose preserves intrinsic limb/neck lengths and bone scales (%.6fm)" % [label, frame, bone_length_error])
	var transforms: Array[Transform3D] = []
	for bind in instance.skin.get_bind_count():
		transforms.append(skeleton.get_bone_global_pose(instance.skin.get_bind_bone(bind)) * instance.skin.get_bind_pose(bind))
	var groups: Dictionary = {}
	var seams: Dictionary = {}
	var seam_error := 0.0
	var finite := true
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var posed := PackedVector3Array()
		var owners := PackedInt32Array()
		for vertex in raw.size():
			var p := Vector3.ZERO
			var owner := 0
			var strongest := -1.0
			for influence in 4:
				var slot := vertex * 4 + influence
				if weights[slot] <= 0.0: continue
				p += transforms[bones[slot]] * raw[vertex] * weights[slot]
				if weights[slot] > strongest:
					strongest = weights[slot]
					owner = instance.skin.get_bind_bone(bones[slot])
			p = instance.to_global(p)
			finite = finite and p.is_finite()
			posed.append(p)
			owners.append(owner)
			# Identical authored positions, including across material boundaries,
			# must remain coincident after the actual weighted pose.
			var key := Vector3i(roundi(raw[vertex].x * 1000000), roundi(raw[vertex].y * 1000000), roundi(raw[vertex].z * 1000000))
			if seams.has(key):
				seam_error = maxf(seam_error, p.distance_to(seams[key]))
			else:
				seams[key] = p
		for offset in range(0, raw.size(), 3):
			var triangle := PackedVector3Array([posed[offset], posed[offset + 1], posed[offset + 2]])
			# Each triangle belongs to its vertex-majority region. Where all three
			# differ, use the middle vertex; no triangle belongs to both neighbours.
			var owner: int = owners[offset] if owners[offset] == owners[offset + 1] or owners[offset] == owners[offset + 2] else owners[offset + 1]
			var name_ := String(skeleton.get_bone_name(owner))
			if not groups.has(name_): groups[name_] = []
			groups[name_].append({"p": triangle, "box": _box(triangle)})
			if name_ in ["hips", "spine"]:
				if not groups.has("torso"): groups["torso"] = []
				groups["torso"].append({"p": triangle, "box": _box(triangle)})
	check(finite, "%s/%d: finite actual weighted vertices" % [label, frame])
	check(seam_error <= SEAM_EPS_M, "%s/%d: coincident authored seams stay joined (%.6fm)" % [label, frame, seam_error])
	var pairs: Array = [["torso", "head"]]
	for suffix: String in ["_l", "_r"]:
		pairs.append(["torso", "upper_arm" + suffix])
		pairs.append(["upper_arm" + suffix, "lower_arm" + suffix])
		pairs.append(["lower_arm" + suffix, "hand" + suffix])
		pairs.append(["torso", "leg" + suffix])
		pairs.append(["leg" + suffix, "foot" + suffix])
		if groups.has("ankle" + suffix): pairs.append(["foot" + suffix, "ankle" + suffix])
	var measurements: Dictionary = {}
	for pair: Array in pairs:
		var gap := _gap(groups.get(pair[0], []), groups.get(pair[1], []))
		measurements[pair[0] + "→" + pair[1]] = gap if is_finite(gap) else "missing geometry"
		check(gap <= CONTACT_EPS_M, "%s/%d: %s joins %s, surface contact witness %.6fm" % [label, frame, pair[0], pair[1], gap])
	print("SELECTED_HERO_JOINTS ", JSON.stringify({"pose": label, "frame": frame, "seam_error_m": seam_error, "contact_witness_gap_m": measurements}))

func _oracle_selftest() -> void:
	var first := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	var detached := PackedVector3Array([Vector3(0, 0, 0.02), Vector3(1, 0, 0.02), Vector3(0, 1, 0.02)])
	var crossing := PackedVector3Array([Vector3(.2, .2, -.1), Vector3(.2, .2, .1), Vector3(.6, .2, .1)])
	check(absf(_triangle_gap(first, detached) - .02) < .000001, "contact oracle distinguishes a detached 20mm valid triangle pair")
	check(_triangle_gap(first, crossing) < .000001, "contact oracle accepts actual intersecting surfaces")
	check(is_inf(_gap([], [])), "missing body geometry cannot satisfy the contact oracle")

func _box(points: PackedVector3Array) -> AABB:
	var result := AABB(points[0], Vector3.ZERO)
	for point in points: result = result.expand(point)
	return result

func _box_gap(a: AABB, b: AABB) -> float:
	return Vector3(maxf(0, maxf(a.position.x - b.end.x, b.position.x - a.end.x)), maxf(0, maxf(a.position.y - b.end.y, b.position.y - a.end.y)), maxf(0, maxf(a.position.z - b.end.z, b.position.z - a.end.z))).length()

func _gap(a: Array, b: Array) -> float:
	var minimum := INF
	for first: Dictionary in a:
		for second: Dictionary in b:
			if _box_gap(first.box, second.box) > minimum: continue
			minimum = minf(minimum, _triangle_gap(first.p, second.p))
			if minimum <= CONTACT_EPS_M: return minimum
	return minimum

func _triangle_gap(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var minimum := INF
	for index in 3:
		if Geometry3D.segment_intersects_triangle(a[index], a[(index + 1) % 3], b[0], b[1], b[2]) != null: return 0.0
		if Geometry3D.segment_intersects_triangle(b[index], b[(index + 1) % 3], a[0], a[1], a[2]) != null: return 0.0
		minimum = minf(minimum, a[index].distance_to(_closest_triangle(a[index], b)))
		minimum = minf(minimum, b[index].distance_to(_closest_triangle(b[index], a)))
		for other in 3:
			var points := Geometry3D.get_closest_points_between_segments(a[index], a[(index + 1) % 3], b[other], b[(other + 1) % 3])
			minimum = minf(minimum, points[0].distance_to(points[1]))
	return minimum

# Closest point on a triangle, Ericson's Voronoi-region construction.
func _closest_triangle(p: Vector3, t: PackedVector3Array) -> Vector3:
	var ab := t[1] - t[0]
	var ac := t[2] - t[0]
	var ap := p - t[0]
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0 and d2 <= 0: return t[0]
	var bp := p - t[1]
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0 and d4 <= d3: return t[1]
	var vc := d1 * d4 - d3 * d2
	if vc <= 0 and d1 >= 0 and d3 <= 0: return t[0] + ab * d1 / (d1 - d3)
	var cp := p - t[2]
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0 and d5 <= d6: return t[2]
	var vb := d5 * d2 - d1 * d6
	if vb <= 0 and d2 >= 0 and d6 <= 0: return t[0] + ac * d2 / (d2 - d6)
	var va := d3 * d6 - d5 * d4
	if va <= 0 and d4 - d3 >= 0 and d5 - d6 >= 0: return t[1] + (t[2] - t[1]) * (d4 - d3) / ((d4 - d3) + (d5 - d6))
	var denominator := va + vb + vc
	if absf(denominator) < 1e-20: return t[0]
	return t[0] + ab * vb / denominator + ac * vc / denominator
