extends RefCounted
## Original police design: e01/e03 and the approved police SVG construction.
## The blue sleeve band was removed by the owner; large piped epaulettes remain.
const Builder = preload("res://game/characters/models/uniform_mesh_builder.gd")
static var _packed: PackedScene

func _material(color: String) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color)
	result.roughness = 1.0
	result.metallic = 0.0
	result.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	result.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	result.vertex_color_use_as_albedo = true
	result.vertex_color_is_srgb = true
	return result

func build_model() -> Node3D:
	if _packed != null:
		return _packed.instantiate() as Node3D
	var b := Builder.new()
	b.palette = {
		"navy": _material("#FFFFFF"),
		"fur_leather_ink": _material("#252330"),
		"ochre_skin": _material("#CBA970"),
		"paper_eye": _material("#E9E0C7"),
		"brass_pencil": _material("#AE893E"),
		"piping": _material("#86464B"),
	}
	b.palette["ochre_skin"].diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	b.palette["fur_leather_ink"].diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	b.vertex_tints["navy"] = Color("#283044")
	_bones(b)
	_coat(b)
	_legs_and_boots(b)
	_arms_and_tools(b)
	_face(b)
	_ushanka(b)
	var root := b.build_node("Police")
	_own_descendants(root, root)
	_packed = PackedScene.new()
	var pack_error := _packed.pack(root)
	if pack_error != OK:
		push_error("Police model could not cache PackedScene: %s" % pack_error)
		_packed = null
	return root

func _own_descendants(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		_own_descendants(child, root)

func _bones(b: Builder) -> void:
	b.add_bone("root", -1, Vector3.ZERO)
	b.add_bone("hips", 0, Vector3(0, 0.235, 0))
	b.add_bone("spine", 1, Vector3(0, 0.445, 0))
	b.add_bone("head", 2, Vector3(0, 0.688, -0.05))
	b.add_bone("upper_arm_l", 2, Vector3(-0.245, 0.67, 0))
	b.add_bone("lower_arm_l", 4, Vector3(-0.289, 0.455, -0.04))
	b.add_bone("hand_l", 5, Vector3(-0.065, 0.468, -0.28))
	b.add_bone("upper_arm_r", 2, Vector3(0.245, 0.67, 0))
	b.add_bone("lower_arm_r", 7, Vector3(0.29, 0.49, -0.04))
	b.add_bone("hand_r", 8, Vector3(0.14, 0.567, -0.296))
	b.add_bone("leg_l", 1, Vector3(0.126, 0.225, 0))
	b.add_bone("foot_l", 10, Vector3(0.126, 0.078, 0))
	b.add_bone("leg_r", 1, Vector3(-0.126, 0.225, 0))
	b.add_bone("foot_r", 12, Vector3(-0.126, 0.078, 0))

func _coat(b: Builder) -> void:
	# A high, heavy, rounded rectangle, not a tapered athletic torso.
	var levels: Array[Vector3] = [
		Vector3(0.237, 0.174, 0.148), Vector3(0.267, 0.19, 0.17),
		Vector3(0.274, 0.23, 0.181), Vector3(0.272, 0.42, 0.188),
		Vector3(0.267, 0.585, 0.18), Vector3(0.252, 0.663, 0.153),
		Vector3(0.208, 0.704, 0.118), Vector3(0.144, 0.712, 0.088),
	]
	b.body_profile(levels, "navy", 2, 24)
	# Padded standing collar around the neck; lapels read as separate folded cloth.
	b.ellipsoid(Vector3(0, 0.684, 0.015), Vector3(0.155, 0.038, 0.115), "fur_leather_ink", 2, 20, 8)
	b.vertex_tints["navy"] = Color("#53515A")
	_triangle_panel(b, PackedVector3Array([Vector3(-0.065, 0.694, -0.151), Vector3(0.065, 0.694, -0.151), Vector3(0, 0.574, -0.196)]), "navy", 2)
	b.vertex_tints["navy"] = Color("#283044")
	b.box(Vector3(0, 0.633, -0.184), Vector3(0.018, 0.099, 0.012), "fur_leather_ink", 2, Basis(Vector3.FORWARD, -0.04))
	for side: float in [-1.0, 1.0]:
		b.vertex_tints["navy"] = Color("#303A52")
		var lapel := PackedVector3Array([Vector3(side * 0.15, 0.7, -0.113), Vector3(side * 0.065, 0.69, -0.158), Vector3(side * 0.009, 0.576, -0.196), Vector3(side * 0.037, 0.559, -0.2), Vector3(side * 0.084, 0.615, -0.184), Vector3(side * 0.061, 0.635, -0.177), Vector3(side * 0.119, 0.672, -0.142)])
		_triangle_panel(b, lapel, "navy", 2)
		b.tube(lapel, 0.002, "fur_leather_ink", 2, 5)
		b.vertex_tints["navy"] = Color("#283044")
		# A broad raised shoulder plate, muted red piping and a plain brass button.
		var shoulder_basis := Basis(Vector3.FORWARD, side * 0.28)
		b.vertex_tints["navy"] = Color("#626879")
		b.box(Vector3(side * 0.235, 0.681, -0.024), Vector3(0.117, 0.022, 0.088), "navy", 2, shoulder_basis)
		b.vertex_tints["navy"] = Color("#283044")
		b.tube(PackedVector3Array([Vector3(side * 0.18, 0.697, -0.069), Vector3(side * 0.282, 0.668, -0.069)]), 0.0034, "piping", 2, 6)
		b.ellipsoid(Vector3(side * 0.185, 0.701, -0.045), Vector3(0.006, 0.004, 0.006), "brass_pencil", 2, 8, 5)
		# Pocket flaps sit on the actual coat surface at each side.
		b.box(Vector3(side * 0.182, 0.354, -0.146), Vector3(0.112, 0.042, 0.024), "navy", 2, Basis(Vector3.UP, side * -0.48))
		b.tube(PackedVector3Array([Vector3(side * 0.133, 0.337, -0.174), Vector3(side * 0.215, 0.337, -0.12)]), 0.002, "fur_leather_ink", 2)
		b.ellipsoid(Vector3(side * 0.175, 0.349, -0.164), Vector3(0.006, 0.006, 0.004), "brass_pencil", 2, 8, 5)
	for p: Vector3 in [Vector3(-0.043, 0.417, -0.19), Vector3(-0.046, 0.344, -0.187), Vector3(0.069, 0.344, -0.183), Vector3(0.071, 0.265, -0.176)]:
		b.ellipsoid(p, Vector3(0.007, 0.007, 0.0045), "brass_pencil", 2, 8, 5)
	b.tube(PackedVector3Array([Vector3(-0.024, 0.575, -0.182), Vector3(-0.034, 0.46, -0.189), Vector3(-0.043, 0.325, -0.183), Vector3(-0.049, 0.193, -0.166)]), 0.0017, "fur_leather_ink", 2)
	# Rear vent and waist tab are visible from the gameplay approach camera.
	b.tube(PackedVector3Array([Vector3(0, 0.65, 0.16), Vector3(0, 0.44, 0.19), Vector3(0, 0.19, 0.171)]), 0.0018, "fur_leather_ink", 2)
	b.box(Vector3(0, 0.414, 0.187), Vector3(0.19, 0.025, 0.012), "navy", 2)
	for side: float in [-1.0, 1.0]:
		b.ellipsoid(Vector3(side * 0.073, 0.415, 0.196), Vector3(0.006, 0.006, 0.003), "brass_pencil", 2, 8, 5)

func _legs_and_boots(b: Builder) -> void:
	for side: float in [-1.0, 1.0]:
		var leg := 10 if side > 0.0 else 12
		var foot := leg + 1
		b.ellipsoid(Vector3(side * 0.126, 0.153, 0.008), Vector3(0.083, 0.089, 0.085), "navy", leg, 14, 8)
		# Short boot shafts and broad outturned toes, with soles exactly at y=0.
		b.ellipsoid(Vector3(side * 0.126, 0.071, 0.003), Vector3(0.062, 0.067, 0.065), "fur_leather_ink", foot, 14, 8)
		b.ellipsoid(Vector3(side * 0.15, 0.03, -0.041), Vector3(0.089, 0.029, 0.098), "fur_leather_ink", foot, 16, 8)
		b.box(Vector3(side * 0.145, 0.008, -0.033), Vector3(0.157, 0.016, 0.171), "fur_leather_ink", foot, Basis(Vector3.UP, side * -0.22))
		for k in range(3):
			var y := 0.048 + float(k) * 0.011
			b.tube(PackedVector3Array([Vector3(side * 0.126 - 0.024, y, -0.059), Vector3(side * 0.126 + 0.024, y - 0.005, -0.06)]), 0.002, "navy", foot, 5)

func _arms_and_tools(b: Builder) -> void:
	for side: float in [-1.0, 1.0]:
		var upper := 4 if side < 0.0 else 7
		var lower := upper + 1
		b.ellipsoid(Vector3(side * 0.275, 0.552, -0.005), Vector3(0.08, 0.129, 0.116), "navy", upper, 16, 10)
		var y := 0.478 if side < 0.0 else 0.535
		b.ellipsoid(Vector3(side * 0.204, y, -0.16), Vector3(0.132, 0.074, 0.098), "navy", lower, 16, 10)
		b.ellipsoid(Vector3(side * 0.115, y + 0.008, -0.237), Vector3(0.058, 0.064, 0.042), "fur_leather_ink", lower, 12, 8)
		b.ellipsoid(Vector3(side * 0.127, y + 0.008, -0.224), Vector3(0.055, 0.063, 0.047), "navy", lower, 12, 8)
	_hand(b, Vector3(-0.062, 0.468, -0.284), 6, 1.0)
	_hand(b, Vector3(0.14, 0.567, -0.296), 9, -1.0)
	# Left hand supports the page; the viewer sees the writing hand on the left.
	var note_basis := Basis(Vector3.FORWARD, 0.13)
	b.box(Vector3(0.027, 0.501, -0.276), Vector3(0.119, 0.14, 0.015), "fur_leather_ink", 6, note_basis)
	b.box(Vector3(0.027, 0.501, -0.286), Vector3(0.11, 0.13, 0.008), "paper_eye", 6, note_basis)
	for i in range(6):
		var x := 0.071 - float(i) * 0.017
		var y := 0.569 - (x - 0.027) * 0.13
		b.tube(PackedVector3Array([Vector3(x, y - 0.005, -0.293), Vector3(x, y + 0.006, -0.295), Vector3(x, y + 0.012, -0.282), Vector3(x, y + 0.005, -0.269)]), 0.0022, "fur_leather_ink", 6, 5)
	for i in range(3):
		var y := 0.533 - float(i) * 0.023
		b.tube(PackedVector3Array([Vector3(0.067, y - 0.006, -0.291), Vector3(-0.008, y + 0.004, -0.291)]), 0.0008, "brass_pencil", 6, 4)
	# The graphite touches the upper page inside its bounds; the shaft passes
	# through the curled writing fingers rather than pointing away from the book.
	b.tube(PackedVector3Array([Vector3(0.193, 0.599, -0.309), Vector3(0.081, 0.533, -0.296)]), 0.0051, "brass_pencil", 9, 6)
	b.tube(PackedVector3Array([Vector3(0.081, 0.533, -0.296), Vector3(0.072, 0.527, -0.293)]), 0.003, "paper_eye", 9, 5)
	b.ellipsoid(Vector3(0.071, 0.526, -0.292), Vector3(0.0025, 0.003, 0.0025), "fur_leather_ink", 9, 8, 5)
	b.ellipsoid(Vector3(0.195, 0.6, -0.309), Vector3(0.0055, 0.006, 0.0055), "piping", 9, 8, 5)

func _hand(b: Builder, center: Vector3, bone: int, curl: float) -> void:
	b.ellipsoid(center, Vector3(0.042, 0.033, 0.025), "ochre_skin", bone, 14, 8)
	for i in range(4):
		var offset := Vector3(curl * 0.022, 0.023 - float(i) * 0.013, -0.015)
		b.ellipsoid(center + offset, Vector3(0.031, 0.0085, 0.014), "ochre_skin", bone, 10, 6)
		if i < 3:
			b.tube(PackedVector3Array([center + offset + Vector3(-0.011, -0.006, -0.014), center + offset + Vector3(0.014, -0.006, -0.014)]), 0.0012, "brass_pencil", bone, 4)
	b.ellipsoid(center + Vector3(-curl * 0.018, 0.026, -0.008), Vector3(0.021, 0.014, 0.019), "ochre_skin", bone, 10, 6)

func _face(b: Builder) -> void:
	# One continuous broad jowled head. Its cheek mass is part of the face cage,
	# and the lower jaw sits in front of the coat rather than disappearing into it.
	var levels: Array[Vector3] = [
		Vector3(0.054, 0.675, 0.05), Vector3(0.103, 0.682, 0.078),
		Vector3(0.132, 0.696, 0.096), Vector3(0.14, 0.717, 0.103),
		Vector3(0.136, 0.745, 0.105), Vector3(0.124, 0.778, 0.105),
		Vector3(0.111, 0.815, 0.099), Vector3(0.105, 0.849, 0.094),
		Vector3(0.102, 0.882, 0.088),
	]
	_soft_volume(b, levels, "ochre_skin", 3, Vector3(0, 0, -0.07), 3.4)
	for side: float in [-1.0, 1.0]:
		var x := side * 0.027 - 0.009
		b.ellipsoid(Vector3(x, 0.833, -0.16900), Vector3(0.018, 0.006, 0.009), "paper_eye", 3, 12, 6)
		b.ellipsoid(Vector3(x - 0.003, 0.831, -0.17700), Vector3(0.0036, 0.004, 0.002), "fur_leather_ink", 3, 8, 5)
		# Heavy lids leave only a narrow white eye visible below them.
		b.ellipsoid(Vector3(x, 0.841, -0.17100), Vector3(0.021, 0.008, 0.009), "ochre_skin", 3, 12, 6)
		b.tube(PackedVector3Array([Vector3(x - 0.019, 0.839 + side * 0.001, -0.17800), Vector3(x, 0.838, -0.18200), Vector3(x + 0.018, 0.837, -0.17800)]), 0.0034, "fur_leather_ink", 3, 6)
		b.tube(PackedVector3Array([Vector3(x - 0.012, 0.82, -0.17500), Vector3(x, 0.818, -0.18000), Vector3(x + 0.011, 0.82, -0.17600)]), 0.0013, "fur_leather_ink", 3, 5)
	# A narrow bridge, small bulb and two nostrils, not a pasted facial mark.
	b.ellipsoid(Vector3(-0.009, 0.816, -0.17900), Vector3(0.009, 0.025, 0.016), "ochre_skin", 3, 14, 8)
	b.ellipsoid(Vector3(-0.009, 0.803, -0.19500), Vector3(0.013, 0.009, 0.015), "ochre_skin", 3, 14, 8)
	for x: float in [-0.018, 0.0]:
		b.ellipsoid(Vector3(x, 0.798, -0.20200), Vector3(0.0038, 0.002, 0.0027), "fur_leather_ink", 3, 8, 5)
	# Small brush moustache, irregular lower bristles and a disappointed mouth.
	b.ellipsoid(Vector3(-0.008, 0.785, -0.18600), Vector3(0.035, 0.0085, 0.008), "fur_leather_ink", 3, 14, 6)
	for i in range(8):
		var x := -0.038 + float(i) * 0.0085
		b.tube(PackedVector3Array([Vector3(x, 0.787, -0.19200), Vector3(x + 0.0005, 0.777 + float(i % 3) * 0.001, -0.19200)]), 0.0014, "fur_leather_ink", 3, 4)
	b.tube(PackedVector3Array([Vector3(-0.031, 0.761, -0.18400), Vector3(-0.023, 0.766, -0.18900), Vector3(-0.008, 0.768, -0.19000), Vector3(0.008, 0.766, -0.18800), Vector3(0.018, 0.761, -0.18400)]), 0.0018, "fur_leather_ink", 3, 6)
	b.tube(PackedVector3Array([Vector3(-0.019, 0.753, -0.18600), Vector3(-0.008, 0.75, -0.19000), Vector3(0.002, 0.753, -0.18600)]), 0.0011, "fur_leather_ink", 3, 5)
	for side: float in [-1.0, 1.0]:
		b.tube(PackedVector3Array([Vector3(side * 0.024 - 0.008, 0.801, -0.18200), Vector3(side * 0.038 - 0.008, 0.78, -0.18100), Vector3(side * 0.047 - 0.008, 0.751, -0.17800)]), 0.0016, "fur_leather_ink", 3, 6)
	for x: float in [-0.078, 0.0, 0.078]:
		b.tube(PackedVector3Array([Vector3(x - 0.019, 0.716, -0.17800), Vector3(x, 0.711, -0.18300), Vector3(x + 0.019, 0.716, -0.17800)]), 0.0014, "fur_leather_ink", 3, 5)


func _ushanka(b: Builder) -> void:
	# Rounded padded crown and folded forehead panel, with a soft irregular rim.
	var crown: Array[Vector3] = [
		Vector3(0.132, 0.884, 0.104), Vector3(0.158, 0.898, 0.121),
		Vector3(0.17, 0.927, 0.131), Vector3(0.167, 0.954, 0.128),
		Vector3(0.151, 0.98, 0.116), Vector3(0.112, 0.995, 0.085),
		Vector3(0.055, 1.0, 0.042),
	]
	_soft_volume(b, crown, "fur_leather_ink", 3, Vector3(0, 0, -0.04), 2.8, 0.045)
	b.ellipsoid(Vector3(0, 0.83, 0.022), Vector3(0.155, 0.097, 0.079), "fur_leather_ink", 3, 20, 10)
	var flap: Array[Vector3] = [
		Vector3(0.02, 0.742, 0.035), Vector3(0.039, 0.753, 0.061),
		Vector3(0.05, 0.777, 0.075), Vector3(0.049, 0.806, 0.08),
		Vector3(0.038, 0.844, 0.077), Vector3(0.027, 0.88, 0.062),
		Vector3(0.02, 0.9, 0.045),
	]
	for side: float in [-1.0, 1.0]:
		_soft_volume(b, flap, "fur_leather_ink", 3, Vector3(side * 0.148, 0, -0.022), 2.6, 0.12)
		for j in range(3):
			var y := 0.78 + float(j) * 0.029
			b.tube(PackedVector3Array([Vector3(side * 0.164, y, -0.096), Vector3(side * 0.175, y + 0.008, -0.087)]), 0.0013, "navy", 3, 5)
	var panel: Array[Vector3] = [
		Vector3(0.079, 0.875, 0.016), Vector3(0.117, 0.883, 0.029),
		Vector3(0.126, 0.906, 0.035), Vector3(0.123, 0.939, 0.033),
		Vector3(0.107, 0.954, 0.025), Vector3(0.069, 0.96, 0.013),
	]
	_soft_volume(b, panel, "fur_leather_ink", 3, Vector3(0, 0, -0.152), 2.7, 0.065)
	b.ellipsoid(Vector3(-0.008, 0.919, -0.188), Vector3(0.01, 0.01, 0.003), "brass_pencil", 3, 10, 6)
	b.ellipsoid(Vector3(-0.008, 0.919, -0.191), Vector3(0.003, 0.003, 0.0015), "fur_leather_ink", 3, 8, 5)

func _soft_point(level: Vector3, angle: float, power: float, ripple: float, center: Vector3) -> Vector3:
	var c := cos(angle)
	var s := sin(angle)
	var wave := 0.72 * sin(8.0 * angle + level.y * 9.0) + 0.28 * sin(13.0 * angle - level.y * 13.0)
	var irregular := 1.0 + ripple * wave
	var fur_y := minf(1.0, level.y + ripple * 0.065 * sin(9.0 * angle + level.y * 17.0))
	return center + Vector3(signf(c) * pow(absf(c), 2.0 / power) * level.x * irregular, fur_y, signf(s) * pow(absf(s), 2.0 / power) * level.z * irregular)

func _soft_volume(b: Builder, levels: Array[Vector3], material: String, bone: int, center: Vector3, power: float, ripple: float = 0.0) -> void:
	# A continuous soft rectangular cross-section gives the face and fur their
	# sculpted silhouette, instead of assembling visible intersecting spheres.
	const SIDES := 32
	var positions: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for j in range(levels.size()):
		for i in range(SIDES):
			var angle := TAU * float(i) / SIDES
			var point := _soft_point(levels[j], angle, power, ripple, center)
			var tangent := _soft_point(levels[j], angle + 0.001, power, ripple, center) - _soft_point(levels[j], angle - 0.001, power, ripple, center)
			var vertical := _soft_point(levels[mini(j + 1, levels.size() - 1)], angle, power, ripple, center) - _soft_point(levels[maxi(j - 1, 0)], angle, power, ripple, center)
			positions.append(point)
			normals.append(vertical.cross(tangent).normalized())
	for j in range(levels.size() - 1):
		for i in range(SIDES):
			var a := j * SIDES + i
			var d := j * SIDES + (i + 1) % SIDES
			var c := (j + 1) * SIDES + (i + 1) % SIDES
			var next := (j + 1) * SIDES + i
			b._triangle(positions[a], positions[next], positions[c], normals[a], normals[next], normals[c], material, bone)
			b._triangle(positions[a], positions[c], positions[d], normals[a], normals[c], normals[d], material, bone)
	for j: int in [0, levels.size() - 1]:
		var cap_center := center + Vector3(0, levels[j].y, 0)
		var normal := Vector3.DOWN if j == 0 else Vector3.UP
		for i in range(SIDES):
			b._triangle(cap_center, positions[j * SIDES + i], positions[j * SIDES + (i + 1) % SIDES], normal, normal, normal, material, bone)

func _triangle_panel(b: Builder, points: PackedVector3Array, material: String, bone: int) -> void:
	var projected := PackedVector2Array()
	for point: Vector3 in points:
		projected.append(Vector2(point.x, point.y))
	var signed_area := 0.0
	for i in range(projected.size()):
		var next := projected[(i + 1) % projected.size()]
		signed_area += projected[i].cross(next)
	var orientation := 1.0 if signed_area > 0.0 else -1.0
	var indices := Geometry2D.triangulate_polygon(projected)
	for i in range(0, indices.size(), 3):
		var a := points[indices[i]]
		var c := points[indices[i + 1]]
		var d := points[indices[i + 2]]
		b._triangle(a, c, d, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, material, bone)
		b._triangle(a + Vector3(0, 0, 0.008), c + Vector3(0, 0, 0.008), d + Vector3(0, 0, 0.008), Vector3.BACK, Vector3.BACK, Vector3.BACK, material, bone)
	for i in range(points.size()):
		var a := points[i]
		var c := points[(i + 1) % points.size()]
		var d := c + Vector3(0, 0, 0.008)
		var e := a + Vector3(0, 0, 0.008)
		var normal := Vector3(c.y - a.y, a.x - c.x, 0).normalized() * orientation
		b._triangle(a, c, d, normal, normal, normal, material, bone)
		b._triangle(a, d, e, normal, normal, normal, material, bone)
