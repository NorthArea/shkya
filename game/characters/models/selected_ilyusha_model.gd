extends RefCounted
## Original solid mesh following the owner's selected independent sheet04.
## Bind coordinates: soles0, crown1, forward-Z. Historical author14 joints stay public.
const Builder = preload("res://game/characters/models/uniform_mesh_builder.gd")
const CONCEPT_REFERENCE := "04.png"
const KNEE_Y := 0.236
const HIP_Y := 0.490
const SHOULDER_Y := 0.685
const ELBOW_Y := 0.510
const WRIST_Y := 0.366
const LEG_X := 0.104
const SECTION := [Vector2(.72, -1), Vector2(1, -.72), Vector2(1, .72), Vector2(.72, 1), Vector2(-.72, 1), Vector2(-1, .72), Vector2(-1, -.72), Vector2(-.72, -1)]

func append_to(b: Builder) -> void:
	_bones(b)
	b.vertex_tints["cloth"] = Color("45464a")
	_volume(b, [Vector3(.180, .367, .098), Vector3(.196, .384, .108), Vector3(.197, .435, .111), Vector3(.194, .510, .112), Vector3(.198, .600, .105), Vector3(.202, .652, .094), Vector3(.174, .692, .083), Vector3(.111, .725, .068)], "cloth", 2)
	# The hip joints lie inside the coat, above its hem; the hidden pelvis
	# and thigh tops keep the same standing silhouette while bending at the hip.
	b.vertex_tints["cloth"] = Color("28292e")
	_volume(b, [Vector3(.151, .333, .062), Vector3(.170, .366, .079), Vector3(.163, .395, .073), Vector3(.163, .495, .073)], "cloth", 1)
	for side: float in [1.0, -1.0]:
		var upper := 4 if side > 0 else 7
		var thigh := 10 if side > 0 else 12
		_sleeve(b, side, upper)
		_hand(b, side, upper + 2)
		_trousers(b, side, thigh)
		_boot(b, side, thigh + 1)
	_jacket_details(b)
	_head(b)
	_blend_joints(b)

func _bones(b: Builder) -> void:
	b.add_bone("root", -1, Vector3.ZERO)
	b.add_bone("hips", 0, Vector3(0, .500, 0))
	b.add_bone("spine", 1, Vector3(0, .570, 0))
	b.add_bone("head", 2, Vector3(0, .749, 0))
	for side: float in [1.0, -1.0]:
		var suffix := "_l" if side > 0 else "_r"
		var upper := b.add_bone("upper_arm" + suffix, 2, Vector3(side * .190, SHOULDER_Y, 0))
		var lower := b.add_bone("lower_arm" + suffix, upper, Vector3(side * .253, ELBOW_Y, -.003))
		b.add_bone("hand" + suffix, lower, Vector3(side * .271, WRIST_Y, -.012))
	for side: float in [1.0, -1.0]:
		var suffix := "_l" if side > 0 else "_r"
		var thigh := b.add_bone("leg" + suffix, 1, Vector3(side * LEG_X, HIP_Y, 0))
		b.add_bone("foot" + suffix, thigh, Vector3(side * LEG_X, KNEE_Y, 0))

func _sleeve(b: Builder, side: float, upper: int) -> void:
	b.vertex_tints["cloth"] = Color("414246")
	# One continuous sleeve crossing the elbow; no exposed articulated toy balls.
	_volume(b, [Vector3(.044, .365, .047), Vector3(.050, .388, .054), Vector3(.052, .438, .059), Vector3(.057, .504, .062), Vector3(.063, .560, .066), Vector3(.066, .611, .069), Vector3(.059, .655, .064), Vector3(.039, .687, .046)], "cloth", upper, Vector3(side * .265, 0, -.004), side * -.195)
	b.vertex_tints["trim"] = Color("38393c")
	_volume(b, [Vector3(.045, .362, .048), Vector3(.048, .374, .051), Vector3(.049, .385, .052)], "trim", upper + 1, Vector3(side * .270, 0, -.004))

func _hand(b: Builder, side: float, bone: int) -> void:
	b.vertex_tints["skin"] = Color("d9a588")
	# Palm offset matches the existing reach_hands anatomical grip convention.
	_volume(b, [Vector3(.023, .292, .018), Vector3(.032, .308, .024), Vector3(.033, .337, .025), Vector3(.025, .366, .022)], "skin", bone, Vector3(side * .274, 0, -.020))
	for finger in 4:
		var x := side * (.252 + float(finger) * .014)
		var end_y := .270 + absf(float(finger) - 1.5) * .007
		b.tube(PackedVector3Array([Vector3(x, .315, -.026), Vector3(x + side * .002, .289, -.030), Vector3(x - side * .003, end_y, -.037)]), .0082, "skin", bone, 6)
		b.ellipsoid(Vector3(x - side * .003, end_y, -.037), Vector3(.0082, .0082, .0082), "skin", bone, 6, 4)
	b.tube(PackedVector3Array([Vector3(side * .250, .343, -.028), Vector3(side * .239, .317, -.047), Vector3(side * .241, .303, -.051)]), .011, "skin", bone, 7)

func _trousers(b: Builder, side: float, thigh: int) -> void:
	b.vertex_tints["cloth"] = Color("2a2b30")
	_volume(b, [Vector3(.061, .112, .060), Vector3(.065, .131, .064), Vector3(.063, .180, .065), Vector3(.068, KNEE_Y, .069), Vector3(.073, .288, .071), Vector3(.079, .344, .074), Vector3(.077, .385, .073), Vector3(.077, .420, .073), Vector3(.077, .460, .073), Vector3(.074, .495, .071)], "cloth", thigh, Vector3(side * LEG_X, 0, .007))
	b.vertex_tints["trim"] = Color("25262a")
	b.tube(PackedVector3Array([Vector3(side * .165, .129, .020), Vector3(side * .171, .231, .019), Vector3(side * .182, .345, .020)]), .0015, "trim", thigh, 4)

func _boot(b: Builder, side: float, bone: int) -> void:
	var center := Vector3(side * LEG_X, 0, -.027)
	b.vertex_tints["ink"] = Color("19191b")
	_volume(b, [Vector3(.067, 0, .098), Vector3(.071, .012, .101), Vector3(.070, .026, .100), Vector3(.065, .036, .095)], "ink", bone, center)
	b.vertex_tints["trim"] = Color("29292b")
	_volume(b, [Vector3(.064, .028, .093), Vector3(.066, .052, .093), Vector3(.061, .075, .083), Vector3(.053, .093, .060), Vector3(.052, .127, .050)], "trim", bone, center + Vector3(0, 0, .004))
	# Raised toe cap, heel and sole lugs are visible geometry in profile/back.
	b.vertex_tints["trim"] = Color("242426")
	_volume(b, [Vector3(.056, .037, .026), Vector3(.057, .056, .025), Vector3(.051, .067, .022)], "trim", bone, center + Vector3(0, 0, -.065))
	for z: float in [-.105, -.070, -.035, .002, .038]:
		for edge: float in [-1.0, 1.0]:
			b.box(Vector3(side * LEG_X + edge * .063, .009, z), Vector3(.019, .018, .016), "ink", bone)
	b.vertex_tints["ink"] = Color("171719")
	for row in 4:
		var y := .070 + row * .011
		var z := -.098 + row * .011
		b.tube(PackedVector3Array([Vector3(side * LEG_X - .027, y, z), Vector3(side * LEG_X + .027, y + .002, z)]), .0026, "ink", bone, 4)

func _jacket_details(b: Builder) -> void:
	b.vertex_tints["trim"] = Color("38393d")
	_volume(b, [Vector3(.185, .367, .104), Vector3(.196, .379, .111), Vector3(.196, .393, .112)], "trim", 2)
	# Raised open collar: the aperture contains the neck; no solid torus across it.
	b.vertex_tints["cloth"] = Color("3c3d41")
	var collar_outer: Array[Vector3] = [Vector3(.110, .709, .080), Vector3(.118, .742, .080), Vector3(.104, .766, .071)]
	var collar_inner: Array[Vector3] = [Vector3(.084, .709, .058), Vector3(.090, .742, .058), Vector3(.085, .766, .051)]
	_collar(b, collar_outer, collar_inner)
	b.vertex_tints["trim"] = Color("222327")
	b.box(Vector3(0, .705, -.077), Vector3(.030, .057, .014), "trim", 2)
	# Twin zipper tapes follow the jacket's actual front envelope.
	for side: float in [-1.0, 1.0]:
		b.tube(PackedVector3Array([Vector3(side * .004, .373, -.113), Vector3(side * .004, .510, -.115), Vector3(side * .004, .601, -.108), Vector3(side * .004, .687, -.088), Vector3(side * .004, .731, -.082)]), .0023, "trim", 2, 4)
	b.vertex_tints["accent"] = Color("a59a4e")
	b.box(Vector3(0, .697, -.096), Vector3(.012, .033, .007), "accent", 2, Basis(Vector3.BACK, -.06))
	b.vertex_tints["trim"] = Color("303135")
	for side: float in [-1.0, 1.0]:
		# Plain inset pocket opening with a narrow raised welt on each front side.
		b.box(Vector3(side * .142, .462, -.113), Vector3(.018, .113, .005), "trim", 2, Basis(Vector3.BACK, side * -.11))
		b.vertex_tints["cloth"] = Color("4a4b4f")
		b.tube(PackedVector3Array([Vector3(side * .151, .409, -.115), Vector3(side * .139, .517, -.115)]), .0020, "cloth", 2, 4)
	b.vertex_tints["trim"] = Color("393a3e")
	b.tube(PackedVector3Array([Vector3(-.167, .651, .085), Vector3(-.100, .659, .098), Vector3(0, .660, .100), Vector3(.100, .659, .098), Vector3(.167, .651, .085)]), .0017, "trim", 2, 4)

func _head(b: Builder) -> void:
	b.vertex_tints["skin"] = Color("dca98b")
	_volume(b, [Vector3(.057, .710, .050), Vector3(.061, .788, .052)], "skin", 3)
	_volume(b, [Vector3(.069, .760, .067), Vector3(.091, .772, .084), Vector3(.098, .800, .091), Vector3(.100, .846, .094), Vector3(.097, .893, .091), Vector3(.093, .940, .085), Vector3(.087, .963, .076)], "skin", 3, Vector3(0, 0, -.007))
	for side: float in [-1.0, 1.0]:
		b.ellipsoid(Vector3(side * .102, .864, .003), Vector3(.020, .032, .020), "skin", 3, 10, 6)
		b.vertex_tints["trim"] = Color("bc8269")
		b.ellipsoid(Vector3(side * .107, .863, -.014), Vector3(.011, .019, .004), "trim", 3, 8, 5)
		# Tiny eyes under heavy straight brows; eyelid covers the upper sclera.
		b.vertex_tints["eye"] = Color("ede8dc")
		b.ellipsoid(Vector3(side * .043, .879, -.101), Vector3(.019, .009, .007), "eye", 3, 10, 6)
		b.vertex_tints["ink"] = Color("272323")
		b.ellipsoid(Vector3(side * .043, .877, -.108), Vector3(.0048, .0052, .003), "ink", 3, 8, 5)
		b.vertex_tints["skin"] = Color("dca98b")
		b.box(Vector3(side * .043, .886, -.104), Vector3(.040, .010, .012), "skin", 3)
		b.vertex_tints["trim"] = Color("a27560")
		b.tube(PackedVector3Array([Vector3(side * .043 - .020, .882, -.111), Vector3(side * .043 + .020, .882, -.111)]), .0018, "trim", 3, 4)
		b.vertex_tints["ink"] = Color("332b28")
		b.box(Vector3(side * .043, .910, -.101), Vector3(.060, .019, .019), "ink", 3, Basis(Vector3.BACK, side * .025))
	# Broad blunt nose built from bevelled rectangular sections, not a trunk.
	b.vertex_tints["skin"] = Color("cc8b70")
	_volume(b, [Vector3(.019, .851, .018), Vector3(.025, .859, .026), Vector3(.024, .873, .027), Vector3(.015, .905, .015)], "skin", 3, Vector3(0, 0, -.115))
	b.vertex_tints["trim"] = Color("aa775f")
	b.tube(PackedVector3Array([Vector3(-.034, .825, -.103), Vector3(0, .829, -.105), Vector3(.034, .825, -.103)]), .0018, "trim", 3, 5)
	b.vertex_tints["trim"] = Color("ca977b")
	b.tube(PackedVector3Array([Vector3(0, .770, -.092), Vector3(0, .792, -.100)]), .0010, "trim", 3, 4)
	_hair(b)

func _hair(b: Builder) -> void:
	b.vertex_tints["ink"] = Color("352c27")
	_volume(b, [Vector3(.096, .939, .077), Vector3(.102, .962, .082), Vector3(.098, .983, .076), Vector3(.073, .998, .052)], "ink", 3, Vector3(0, 0, .011))
	# The rear cap reaches the ear line, unlike the exposed forehead at the front.
	_volume(b, [Vector3(.090, .855, .022), Vector3(.100, .875, .027), Vector3(.102, .938, .027), Vector3(.095, .971, .024)], "ink", 3, Vector3(0, 0, .077))
	# Temple blocks and angular swept fringe. Back remains a short fitted cap.
	for side: float in [-1.0, 1.0]:
		b.box(Vector3(side * .091, .916, .006), Vector3(.016, .074, .130), "ink", 3)
	var a := Vector3(-.093, .947, -.069)
	var c := Vector3(.086, .962, -.069)
	var peak := Vector3(-.027, 1.0, -.028)
	var back := Vector3(.032, .988, .061)
	b.vertex_tints["ink"] = Color("42342b")
	_face(b, a, c, peak, "ink", 3)
	_face(b, c, back, peak, "ink", 3)
	b.vertex_tints["ink"] = Color("302722")
	_face(b, a, peak, Vector3(-.090, .980, .049), "ink", 3)
	b.vertex_tints["ink"] = Color("4b3b30")
	_face(b, Vector3(-.066, .981, -.063), Vector3(-.005, .973, -.071), peak, "ink", 3)

func _collar(b: Builder, outer: Array[Vector3], inner: Array[Vector3]) -> void:
	# Omit the front-centre segment for the zip opening; close all remaining rims.
	for index in SECTION.size():
		var next := (index + 1) % SECTION.size()
		if index == 7: continue
		for layer in range(outer.size() - 1):
			var a := _section_point(outer[layer], index)
			var c := _section_point(outer[layer], next)
			var top_a := _section_point(outer[layer + 1], index)
			var top_c := _section_point(outer[layer + 1], next)
			_quad(b, a, top_a, top_c, c, "cloth", 2)
			_quad(b, _section_point(inner[layer], next), _section_point(inner[layer + 1], next), _section_point(inner[layer + 1], index), _section_point(inner[layer], index), "cloth", 2)
		for layer in [0, outer.size() - 1]:
			_quad(b, _section_point(outer[layer], index), _section_point(outer[layer], next), _section_point(inner[layer], next), _section_point(inner[layer], index), "cloth", 2)
	for side: float in [1.0, -1.0]:
		var front: Array[Vector3] = [Vector3(side * .012, .709, -.080), Vector3(side * .012, .732, -.082), Vector3(side * .075, .766, -.071), Vector3(side * .079, .709, -.080)]
		if side < 0: front.reverse()
		_quad(b, front[0], front[1], front[2], front[3], "cloth", 2)
		var thickness := Vector3(0, 0, .016)
		_quad(b, front[3] + thickness, front[2] + thickness, front[1] + thickness, front[0] + thickness, "cloth", 2)
		for edge in 4:
			var next := (edge + 1) % 4
			_quad(b, front[edge], front[next], front[next] + thickness, front[edge] + thickness, "cloth", 2)

func _volume(b: Builder, rows: Array[Vector3], key: String, bone: int, offset := Vector3.ZERO, lean := 0.0) -> void:
	for row in range(rows.size() - 1):
		for side in SECTION.size():
			var next := (side + 1) % SECTION.size()
			var a := _section_point(rows[row], side) + offset
			var c := _section_point(rows[row], next) + offset
			var top_a := _section_point(rows[row + 1], side) + offset
			var top_c := _section_point(rows[row + 1], next) + offset
			a.x += (a.y - WRIST_Y) * lean
			c.x += (c.y - WRIST_Y) * lean
			top_a.x += (top_a.y - WRIST_Y) * lean
			top_c.x += (top_c.y - WRIST_Y) * lean
			_quad(b, a, top_a, top_c, c, key, bone)
	for row in [0, rows.size() - 1]:
		var center := Vector3(0, rows[row].y, 0) + offset
		center.x += (center.y - WRIST_Y) * lean
		for side in SECTION.size():
			var a := _section_point(rows[row], side) + offset
			var c := _section_point(rows[row], (side + 1) % SECTION.size()) + offset
			a.x += (a.y - WRIST_Y) * lean
			c.x += (c.y - WRIST_Y) * lean
			var normal := Vector3.DOWN if row == 0 else Vector3.UP
			b._triangle(center, a, c, normal, normal, normal, key, bone)

func _section_point(row: Vector3, side: int) -> Vector3:
	var p: Vector2 = SECTION[side]
	return Vector3(p.x * row.x, row.y, p.y * row.z)

func _face(b: Builder, a: Vector3, c: Vector3, d: Vector3, key: String, bone: int) -> void:
	var normal := (c - a).cross(d - a).normalized()
	# Hair patches point away from the head centre.
	if normal.dot((a + c + d) / 3.0 - Vector3(0, .92, 0)) < 0: normal = -normal
	b._triangle(a, c, d, normal, normal, normal, key, bone)

func _quad(b: Builder, a: Vector3, c: Vector3, d: Vector3, e: Vector3, key: String, bone: int) -> void:
	var normal := (c - a).cross(d - a).normalized()
	b._triangle(a, c, d, normal, normal, normal, key, bone)
	b._triangle(a, d, e, normal, normal, normal, key, bone)

func _blend_joints(b: Builder) -> void:
	for part: Dictionary in b._parts.values():
		var positions: PackedVector3Array = part.positions
		var bones: PackedInt32Array = part.bones
		var weights: PackedFloat32Array = part.weights
		for vertex in positions.size():
			var slot := vertex * 4
			var bone := bones[slot]
			var next := -1
			var mix := 0.0
			if bone in [4, 7]:
				next = bone + 1
				mix = 1.0 - smoothstep(ELBOW_Y - .035, ELBOW_Y + .035, positions[vertex].y)
			elif bone in [10, 12]:
				next = bone + 1
				mix = 1.0 - smoothstep(KNEE_Y - .030, KNEE_Y + .030, positions[vertex].y)
			elif bone in [1, 2] and positions[vertex].y < .55:
				# The lower hem wraps the thighs; the upper back remains with the pelvis.
				var p := positions[vertex]
				var to_pelvis := 1.0 if bone == 1 else 1.0 - smoothstep(.49, .55, p.y)
				var front := 1.0 - smoothstep(-.015, .065, p.z)
				var rear_hem := 1.0 - smoothstep(.395, .445, p.y)
				var to_thigh := (1.0 - smoothstep(.40, .50, p.y)) * maxf(front, rear_hem)
				if bone == 1: to_thigh = 1.0 - smoothstep(.41, .495, p.y)
				var left := smoothstep(-.05, .05, p.x)
				bones[slot] = 2
				bones[slot + 1] = 1
				bones[slot + 2] = 10
				bones[slot + 3] = 12
				weights[slot] = (1.0 - to_pelvis) * (1.0 - to_thigh)
				weights[slot + 1] = to_pelvis * (1.0 - to_thigh)
				weights[slot + 2] = to_thigh * left
				weights[slot + 3] = to_thigh * (1.0 - left)
			if next >= 0:
				bones[slot + 1] = next
				weights[slot] = 1.0 - mix
				weights[slot + 1] = mix
		part.bones = bones
		part.weights = weights
