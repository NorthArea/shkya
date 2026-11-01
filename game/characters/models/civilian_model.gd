extends RefCounted
## Solid 3D translations of the approved character drawings. Soles=0, top=1, forward=-Z.
## Clothing, face silhouettes and expressions follow the previous authored SVGs.
const Builder = preload("res://game/characters/models/uniform_mesh_builder.gd")
const Police = preload("res://game/characters/models/police_model.gd")
const Guard = preload("res://game/characters/models/guard_model.gd")
const Residents = preload("res://game/characters/models/legacy_resident_models.gd")
# Historical foot_* names now identify civilian knee/lower-leg joints.
# Uniform models/variants retain their authored ankle rigs.
const CIVILIAN_KNEE_Y := 0.22
const GRANNY_DRESS_YOKE := Vector3(0, 0.615, 0.03)
const GRANNY_DRESS_YOKE_RADII := Vector3(0.20, 0.10, 0.13)
const DRAWINGS: Array[String] = ["ilyusha", "babka", "vendor", "officer", "resident_babka", "resident_man", "resident_woman", "resident_boy", "resident_shuba", "resident_beret", "resident_violet", "resident_ushanka", "resident_ushanka_walk", "resident_tourist", "resident_kid", "resident_kid2", "resident_dog", "resident_kolpak", "resident_bow", "resident_turban", "police_long", "police_round", "guard_alt"]
static var _models: Dictionary = {}
static var _materials: Dictionary = {}

static func supports(drawing: String) -> bool:
	return drawing in DRAWINGS

func build_model(drawing: String = "ilyusha") -> Node3D:
	if not supports(drawing):
		push_error("Unknown City N character drawing: " + drawing)
		return null
	if _models.has(drawing):
		var cached := (_models[drawing] as PackedScene).instantiate() as Node3D
		_initialize_rest(cached)
		return cached
	var model: Node3D
	if drawing in ["police_long", "police_round", "guard_alt"]:
		model = _uniform_variant(drawing)
	else:
		var b := Builder.new()
		b.palette = _palette()
		if Residents.handles(drawing):
			Residents.append_to(b, drawing)
		else:
			var design := _design(drawing)
			_bones(b, design)
			_approved_hero(b, drawing)
			_weight_coat_skirt(b, design)
			_weight_lower_legs(b)
		_quantize_skin_weights(b)
		model = b.build_node("Citizen_" + drawing)
	_initialize_rest(model)
	model.set_meta("drawing", drawing)
	model.set_meta("forward_axis", "-Z")
	model.set_meta("design_status", "previous approved drawings translated to solid 3D; visual acceptance required")
	_own(model, model)
	var packed := PackedScene.new()
	if packed.pack(model) == OK:
		_models[drawing] = packed
	else:
		push_error("Could not cache City N visual: " + drawing)
	return model

func _quantize_skin_weights(b: Builder) -> void:
	# ArrayMesh stores weights as UNORM16. Quantizing each influence separately
	# truncates .5/.5 to 32767+32767. Allocate the residual in integer units first.
	const MAX_WEIGHT := 65535
	var units := PackedInt32Array([0, 0, 0, 0])
	for part: Dictionary in b._parts.values():
		var weights: PackedFloat32Array = part["weights"]
		for offset in range(0, weights.size(), 4):
			var total := 0
			var largest := 0
			for influence in 4:
				units[influence] = clampi(roundi(float(weights[offset + influence]) * MAX_WEIGHT), 0, MAX_WEIGHT)
				total += units[influence]
				if units[influence] > units[largest]: largest = influence
			units[largest] += MAX_WEIGHT - total
			for influence in 4:
				weights[offset + influence] = float(units[influence]) / MAX_WEIGHT
		part["weights"] = weights

func _initialize_rest(model: Node3D) -> void:
	# Godot 4 pose positions are absolute local transforms. set_bone_rest alone
	# leaves new bones at zero, so every returned instance must begin at rest.
	var skeleton := model.get_node("Skeleton3D") as Skeleton3D
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()

func _own(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)

func _palette() -> Dictionary:
	if _materials.is_empty():
		for key: String in ["cloth", "accent", "ink", "skin", "eye", "trim"]:
			var mat := StandardMaterial3D.new()
			mat.resource_name = "City N " + key
			mat.albedo_color = Color.WHITE if key == "eye" else Color("211f27") if key == "ink" else Color.WHITE
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.roughness = 1.0
			mat.metallic = 0.0
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY if key in ["skin", "ink"] else BaseMaterial3D.DIFFUSE_TOON
			_materials[key] = mat
	return _materials

func _design(drawing: String) -> Dictionary:
	match drawing:
		"ilyusha": return {"drawing": drawing, "hem": 0.27, "shoulder": 0.55, "width": 0.20, "head_y": 0.63}
		"babka": return {"drawing": drawing, "hem": 0.045, "shoulder": 0.615, "width": 0.265, "head_y": 0.74}
		"vendor": return {"drawing": drawing, "hem": 0.04, "shoulder": 0.59, "width": 0.23, "head_y": 0.72}
	assert(false, "No approved hero drawing: " + drawing)
	return {}

func _bones(b: Builder, d: Dictionary) -> void:
	var shoulder: float = d.shoulder
	var x: float = d.width + 0.022
	b.add_bone("root", -1, Vector3.ZERO)
	b.add_bone("hips", 0, Vector3(0, 0.36, 0))
	b.add_bone("spine", 1, Vector3(0, 0.54, 0))
	b.add_bone("head", 2, Vector3(0, d.head_y - 0.10, -0.005))
	for side: float in [1.0, -1.0]:
		var suffix := "_l" if side > 0 else "_r"
		var vendor: bool = d.drawing == "vendor"
		var upper_at := Vector3(side * 0.17, 0.55, 0) if vendor else Vector3(side * x, shoulder, 0)
		var elbow_at := Vector3(side * 0.245, 0.45, -0.035) if vendor else Vector3(side * (x + 0.022), shoulder - 0.17, -0.005)
		var hand_at := Vector3(side * 0.114, 0.394, -0.20) if vendor else Vector3(side * (x + 0.027), shoulder - 0.285, -0.015)
		var upper := b.add_bone("upper_arm" + suffix, 2, upper_at)
		var lower := b.add_bone("lower_arm" + suffix, upper, elbow_at)
		b.add_bone("hand" + suffix, lower, hand_at)
	for side: float in [1.0, -1.0]:
		var suffix := "_l" if side > 0 else "_r"
		var leg := b.add_bone("leg" + suffix, 1, Vector3(side * 0.092, 0.355, 0))
		b.add_bone("foot" + suffix, leg, Vector3(side * 0.092, CIVILIAN_KNEE_Y, 0))

func _weight_lower_legs(b: Builder) -> void:
	# Keep every authored position/normal/color and triangle unchanged. Only the
	# lower trouser vertices join the knee chain already carrying the shoes.
	for part: Dictionary in b._parts.values():
		var vertices: PackedVector3Array = part["positions"]
		var bones: PackedInt32Array = part["bones"]
		for index in vertices.size():
			var bone := bones[index * 4]
			if bone in [10, 12] and vertices[index].y < CIVILIAN_KNEE_Y:
				bones[index * 4] = bone + 1
		part["bones"] = bones

func _weight_coat_skirt(b: Builder, d: Dictionary) -> void:
	if d.drawing == "ilyusha" or d.hem >= 0.30: return
	# Long hems follow the complete thigh envelope below the seat. The upper
	# rear coat stays with the torso so seated hips remain covered.
	for part: Dictionary in b._parts.values():
		var vertices: PackedVector3Array = part["positions"]
		var bones: PackedInt32Array = part["bones"]
		var weights: PackedFloat32Array = part["weights"]
		for index in vertices.size():
			if bones[index * 4] != 2 or vertices[index].y >= 0.44: continue
			var front_weight := 1.0 if d.hem < 0.15 and vertices[index].y < 0.355 else 1.0 - smoothstep(-0.08, 0.025, vertices[index].z)
			var thigh_weight := clampf((0.44 - vertices[index].y) / 0.12, 0, 1) * front_weight
			var left_weight := smoothstep(-0.045, 0.045, vertices[index].x)
			bones[index * 4 + 1] = 10
			bones[index * 4 + 2] = 12
			weights[index * 4] = 1.0 - thigh_weight
			weights[index * 4 + 1] = thigh_weight * left_weight
			weights[index * 4 + 2] = thigh_weight * (1.0 - left_weight)
		part["bones"] = bones
		part["weights"] = weights

func _sleeve(b: Builder, d: Dictionary, side: float, upper: int, lower: int) -> void:
	var x: float = d.width + 0.022
	var shoulder: float = d.shoulder
	# A single cloth envelope runs from the shoulder inside the coat to the cuff.
	# There is no separate shoulder ball or oval forearm to expose a toy joint.
	var levels: Array[Vector4] = [Vector4(x + 0.025, 0.0, 0.045, 0.051), Vector4(x + 0.025, 0.14, 0.050, 0.059), Vector4(x + 0.02, 0.44, 0.054, 0.064), Vector4(x + 0.006, 0.68, 0.061, 0.072), Vector4(x - 0.02, 0.90, 0.068, 0.076), Vector4(x - 0.045, 1.0, 0.045, 0.057)]
	for j in levels.size():
		levels[j].y = lerpf(d.cuff_y, shoulder - 0.005, levels[j].y)
	var points: Array[Vector3] = []
	var normals: Array[Vector3] = []
	const SIDES := 16
	for j in levels.size():
		var previous := levels[maxi(j - 1, 0)]
		var next := levels[mini(j + 1, levels.size() - 1)]
		var dy := maxf(next.y - previous.y, 0.0001)
		for i in SIDES:
			var angle := TAU * float(i) / SIDES
			var c := cos(angle)
			var z := sin(angle)
			points.append(Vector3(side * (levels[j].x + c * levels[j].z), levels[j].y, z * levels[j].w - 0.007))
			var slope := -(next.x - previous.x) / dy * c / levels[j].z - (next.z - previous.z) / dy * c * c / levels[j].z - (next.w - previous.w) / dy * z * z / levels[j].w
			normals.append(Vector3(side * c / levels[j].z, slope, z / levels[j].w).normalized())
	for j in range(levels.size() - 1):
		for i in SIDES:
			var a := j * SIDES + i
			var c := j * SIDES + (i + 1) % SIDES
			b._triangle(points[a], points[a + SIDES], points[c + SIDES], normals[a], normals[a + SIDES], normals[c + SIDES], "cloth", upper)
			b._triangle(points[a], points[c + SIDES], points[c], normals[a], normals[c + SIDES], normals[c], "cloth", upper)
	for j in [0, levels.size() - 1]:
		var center := Vector3(side * levels[j].x, levels[j].y, -0.007)
		var normal := Vector3.DOWN if j == 0 else Vector3.UP
		for i in SIDES:
			b._triangle(center, points[j * SIDES + i], points[j * SIDES + (i + 1) % SIDES], normal, normal, normal, "cloth", upper)
	for part: Dictionary in b._parts.values():
		var vertices: PackedVector3Array = part["positions"]
		var bones: PackedInt32Array = part["bones"]
		var weights: PackedFloat32Array = part["weights"]
		for index in vertices.size():
			if bones[index * 4] != upper: continue
			var elbow_y: float = shoulder - 0.14
			var elbow_weight := clampf((elbow_y - vertices[index].y) / 0.08, 0, 1)
			bones[index * 4 + 1] = lower
			weights[index * 4] = 1.0 - elbow_weight
			weights[index * 4 + 1] = elbow_weight
		part["bones"] = bones
		part["weights"] = weights

func _vendor_sleeve(b: Builder, side: float, upper: int, lower: int) -> void:
	var start: int = (b._parts["cloth"]["positions"] as PackedVector3Array).size()
	b.tube(PackedVector3Array([Vector3(side * 0.15, 0.54, 0), Vector3(side * 0.23, 0.50, -0.01), Vector3(side * 0.252, 0.455, -0.04), Vector3(side * 0.213, 0.419, -0.12), Vector3(side * 0.15, 0.397, -0.18)]), 0.047, "cloth", upper, 16)
	var part: Dictionary = b._parts["cloth"]
	var vertices: PackedVector3Array = part["positions"]
	var bones: PackedInt32Array = part["bones"]
	var weights: PackedFloat32Array = part["weights"]
	for index in range(start, vertices.size()):
		var elbow_weight := clampf((0.51 - vertices[index].y) / 0.075, 0, 1)
		bones[index * 4 + 1] = lower
		weights[index * 4] = 1.0 - elbow_weight
		weights[index * 4 + 1] = elbow_weight
	part["bones"] = bones
	part["weights"] = weights

func _front_jabot(b: Builder, dress: Array[Vector3]) -> void:
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	const SEGMENTS := 52
	const THICKNESS := Vector3(0, 0, 0.004)
	for index in range(SEGMENTS + 1):
		var t := float(index) / SEGMENTS
		var angle := PI - PI * t
		var curve := sin(angle)
		var x := cos(angle) * 0.145 * (0.8 + 0.2 * curve)
		var inner_point := Vector3(x * 0.98, 0.704 - 0.085 * curve, 0)
		var outer_point := Vector3(x, 0.69 - 0.105 * curve - pow(sin(t * PI * 13.0), 2) * 0.006, 0)
		inner_point.z = _jabot_depth(inner_point, dress)
		outer_point.z = _jabot_depth(outer_point, dress)
		inner.append(inner_point)
		outer.append(outer_point)
	for index in SEGMENTS:
		var a := inner[index]
		var c := outer[index]
		var d := outer[index + 1]
		var e := inner[index + 1]
		_jabot_quad(b, a, c, d, e, Vector3.FORWARD)
		_jabot_quad(b, a + THICKNESS, e + THICKNESS, d + THICKNESS, c + THICKNESS, Vector3.BACK)
		_jabot_quad(b, a, e, e + THICKNESS, a + THICKNESS, Vector3.UP)
		_jabot_quad(b, c, c + THICKNESS, d + THICKNESS, d, Vector3.DOWN)
	for index in [0, SEGMENTS]:
		_jabot_quad(b, inner[index], inner[index] + THICKNESS, outer[index] + THICKNESS, outer[index], Vector3.LEFT if index == 0 else Vector3.RIGHT)

func _jabot_depth(point: Vector3, dress: Array[Vector3]) -> float:
	var front := INF
	var shoulder_cross_section := 1.0 - pow((point.x - GRANNY_DRESS_YOKE.x) / GRANNY_DRESS_YOKE_RADII.x, 2) - pow((point.y - GRANNY_DRESS_YOKE.y) / GRANNY_DRESS_YOKE_RADII.y, 2)
	if shoulder_cross_section >= 0:
		front = GRANNY_DRESS_YOKE.z - GRANNY_DRESS_YOKE_RADII.z * sqrt(shoulder_cross_section)
	if point.y >= dress[0].y and point.y <= dress[-1].y:
		front = minf(front, _face_z(dress, 1.0, point.x, point.y) + 0.006)
	# The tips disappear behind the cheeks; the rest lies on the dress surface.
	return -0.035 if is_inf(front) else front - 0.004

func _jabot_quad(b: Builder, a: Vector3, c: Vector3, d: Vector3, e: Vector3, outward: Vector3) -> void:
	var normal := (c - a).cross(d - a).normalized()
	if normal.dot(outward) < 0: normal = -normal
	b._triangle(a, c, d, normal, normal, normal, "trim", 2)
	b._triangle(a, d, e, normal, normal, normal, "trim", 2)

func _face_z(levels: Array[Vector3], exponent: float, x: float, y: float) -> float:
	var level := levels[0] if y <= levels[0].y else levels[-1]
	for j in range(levels.size() - 1):
		if y >= levels[j].y and y <= levels[j + 1].y:
			level = levels[j].lerp(levels[j + 1], (y - levels[j].y) / (levels[j + 1].y - levels[j].y))
			break
	var cross_section := pow(maxf(0, 1.0 - pow(absf(x) / level.x, 2.0 / exponent)), exponent * 0.5)
	return -0.006 - level.z * cross_section

func _face_line(b: Builder, levels: Array[Vector3], exponent: float, points: PackedVector3Array, radius: float, material: String = "ink", offset: float = 0.0014) -> void:
	for index in points.size():
		points[index].z = _face_z(levels, exponent, points[index].x, points[index].y) - offset
	b.tube(points, radius, material, 3, 6)

func _head_cage(b: Builder, levels: Array[Vector3], exponent: float) -> void:
	var points: Array[Vector3] = []
	var normals: Array[Vector3] = []
	const SIDES := 20
	for j in levels.size():
		for i in SIDES:
			var a := TAU * float(i) / SIDES
			var c := cos(a)
			var s := sin(a)
			points.append(Vector3(signf(c) * pow(absf(c), exponent) * levels[j].x, levels[j].y, signf(s) * pow(absf(s), exponent) * levels[j].z - 0.006))
			var normal := Vector3(signf(c) * pow(absf(c), 2.0 - exponent) / levels[j].x, 0, signf(s) * pow(absf(s), 2.0 - exponent) / levels[j].z).normalized()
			normals.append(normal)
	for j in range(levels.size() - 1):
		for i in SIDES:
			var a := j * SIDES + i
			var next := j * SIDES + (i + 1) % SIDES
			b._triangle(points[a], points[a + SIDES], points[next + SIDES], normals[a], normals[a + SIDES], normals[next + SIDES], "skin", 3)
			b._triangle(points[a], points[next + SIDES], points[next], normals[a], normals[next + SIDES], normals[next], "skin", 3)
	for j in [0, levels.size() - 1]:
		var center := Vector3(0, levels[j].y, -0.006)
		var n := Vector3.DOWN if j == 0 else Vector3.UP
		for i in SIDES:
			b._triangle(center, points[j * SIDES + i], points[j * SIDES + (i + 1) % SIDES], n, n, n, "skin", 3)

func _approved_hero(b: Builder, drawing: String) -> void:
	var hero := drawing == "ilyusha"
	var granny := drawing == "babka"
	b.vertex_tints["cloth"] = Color("a2f03a") if hero else Color("b6ba78") if granny else Color("4e3b2d")
	b.vertex_tints["skin"] = Color("f4b3cd") if hero else Color("fffde2") if granny else Color("ebd198")
	b.vertex_tints["accent"] = Color("ebc458") if hero else Color("a9ad6e") if granny else Color("8c3b3b")
	b.vertex_tints["trim"] = Color("f6f3ea") if hero else Color.WHITE if granny else Color("b9b2a0")
	var hem := 0.27 if hero else 0.045 if granny else 0.04
	var shoulder := 0.55 if hero else 0.615 if granny else 0.59
	var width := 0.20 if hero else 0.265 if granny else 0.23
	var levels: Array[Vector3] = [Vector3(width * 0.83, hem, 0.11), Vector3(width, hem + 0.06, 0.14), Vector3(width * 1.06, (hem + shoulder) * 0.5, 0.15), Vector3(width, shoulder - 0.045, 0.14), Vector3(width * 0.70, shoulder, 0.095)]
	b.body_profile(levels, "cloth", 2, 24)
	if drawing == "vendor":
		# The apron shares the coat envelope and skin triangles, so opposing steps
		# cannot send a separate flat panel through the garment underneath.
		var part: Dictionary = b._parts["cloth"]
		var vertices: PackedVector3Array = part["positions"]
		var colors: PackedColorArray = part["colors"]
		for index in range(0, vertices.size(), 3):
			var center := (vertices[index] + vertices[index + 1] + vertices[index + 2]) / 3.0
			if center.z < -0.08 and absf(center.x) < 0.105 and center.y < 0.545:
				for corner in 3: colors[index + corner] = Color("b9b2a0")
		part["colors"] = colors
	# Hips and legs remain separate solids with the existing animation skeleton.
	for side: float in [-1.0, 1.0]:
		var leg := 10 if side > 0 else 12
		var foot := leg + 1
		var upper := 4 if side > 0 else 7
		var lower := upper + 1
		var hand := upper + 2
		b.vertex_tints["cloth"] = Color("2f8a36") if hero else Color("68635b")
		b.ellipsoid(Vector3(side * 0.087, 0.166, 0.012), Vector3(0.079 if hero else 0.045, 0.14, 0.077), "cloth", leg, 12, 8)
		b.vertex_tints["cloth"] = Color("a2f03a") if hero else Color("b6ba78") if granny else Color("4e3b2d")
		b.ellipsoid(Vector3(side * 0.087, 0.038, -0.025), Vector3(0.082 if hero else 0.045, 0.038, 0.093), "ink", foot, 14, 8)
		b.box(Vector3(side * 0.087, 0.008, -0.027), Vector3(0.15 if hero else 0.08, 0.016, 0.15), "ink", foot)
		var x := side * (width + 0.018)
		if drawing == "vendor":
			_vendor_sleeve(b, side, upper, lower)
			b.ellipsoid(Vector3(side * 0.114, 0.394, -0.20), Vector3(0.058, 0.033, 0.037), "skin", hand, 14, 8)
			for finger in 4:
				var finger_x := side * 0.114 + (finger - 1.5) * 0.021
				b.tube(PackedVector3Array([Vector3(finger_x, 0.39, -0.232), Vector3(finger_x, 0.376, -0.234)]), 0.0018, "ink", hand, 5)
		else:
			_sleeve(b, {"width": width - 0.004, "shoulder": shoulder, "cuff_y": shoulder - 0.24}, side, upper, lower)
			b.ellipsoid(Vector3(x, shoulder - 0.285, -0.016), Vector3(0.040, 0.047, 0.044), "skin", hand, 14, 8)
		if granny:
			b.ellipsoid(Vector3(x, shoulder - 0.24, -0.012), Vector3(0.05, 0.016, 0.053), "trim", lower, 12, 6)
			for finger in 4:
				b.ellipsoid(Vector3(x + (finger - 1.5) * 0.015, shoulder - 0.325, -0.022), Vector3(0.009, 0.036, 0.013), "skin", hand, 8, 6)
	if hero:
		# Quilted bands wrap around the full jacket rather than lying on a card.
		for y: float in [0.36, 0.45]:
			var seam := PackedVector3Array()
			for i in 33:
				var a := TAU * i / 32.0
				seam.append(Vector3(cos(a) * 0.213, y, sin(a) * 0.151))
			b.tube(seam, 0.0022, "ink", 2, 5)
		b.tube(PackedVector3Array([Vector3(0, 0.28, -0.143), Vector3(0, 0.41, -0.153), Vector3(0, 0.55, -0.113)]), 0.0022, "ink", 2, 5)
		for i in 20:
			var a := TAU * i / 20.0
			b.ellipsoid(Vector3(cos(a) * 0.153, 0.553 + sin(a) * 0.012, sin(a) * 0.108), Vector3(0.036, 0.035, 0.032), "trim", 2, 10, 6)
	elif granny:
		for i in 10:
			var y := 0.12 + i * 0.046
			b.ellipsoid(Vector3(0, y, -0.153), Vector3(0.0034, 0.004, 0.003), "ink", 2, 8, 4)
		# The back of the loose dress rises behind the cheeks, as in the back SVG.
		b.ellipsoid(GRANNY_DRESS_YOKE, GRANNY_DRESS_YOKE_RADII, "cloth", 2, 20, 10)
		_front_jabot(b, levels)
	else:
		for side: float in [-1.0, 1.0]:
			b.tube(PackedVector3Array([Vector3(side * 0.11, 0.54, -0.149), Vector3(side * 0.14, 0.61, -0.10)]), 0.008, "trim", 2, 6)
		b.vertex_tints["cloth"] = Color("c9433a")
		for side: float in [-1.0, 1.0]:
			b.ellipsoid(Vector3(side * 0.035, 0.594, -0.124), Vector3(0.042, 0.019, 0.012), "cloth", 2, 12, 6)
			b.tube(PackedVector3Array([Vector3(side * 0.009, 0.582, -0.13), Vector3(side * 0.028, 0.52, -0.151)]), 0.011, "cloth", 2, 6)
		b.ellipsoid(Vector3(0, 0.59, -0.14), Vector3(0.018, 0.018, 0.011), "cloth", 2, 12, 6)
		b.vertex_tints["cloth"] = Color("4e3b2d")
	var face: Array[Vector3]
	if hero:
		face = [Vector3(0.025, 0.53, 0.04), Vector3(0.105, 0.55, 0.08), Vector3(0.16, 0.60, 0.106), Vector3(0.177, 0.69, 0.117), Vector3(0.16, 0.78, 0.112), Vector3(0.118, 0.87, 0.086), Vector3(0.06, 0.918, 0.05), Vector3(0.015, 0.925, 0.015)]
	elif granny:
		face = [Vector3(0.02, 0.64, 0.035), Vector3(0.08, 0.65, 0.073), Vector3(0.123, 0.68, 0.099), Vector3(0.129, 0.73, 0.109), Vector3(0.106, 0.80, 0.103), Vector3(0.096, 0.87, 0.09), Vector3(0.082, 0.901, 0.071), Vector3(0.02, 0.91, 0.025)]
	else:
		face = [Vector3(0.025, 0.62, 0.035), Vector3(0.105, 0.635, 0.076), Vector3(0.15, 0.67, 0.098), Vector3(0.159, 0.72, 0.11), Vector3(0.14, 0.79, 0.103), Vector3(0.12, 0.86, 0.086), Vector3(0.09, 0.902, 0.068), Vector3(0.02, 0.909, 0.022)]
	if not hero:
		# Closed cap/back of headscarf with hanging side panels; face stays exposed.
		if granny:
			b.body_profile([Vector3(0.095, 0.78, 0.065), Vector3(0.11, 0.86, 0.09), Vector3(0.11, 0.97, 0.09), Vector3(0.10, 0.993, 0.08), Vector3(0.07, 1.0, 0.04)], "accent", 3, 20)
			var cap: Dictionary = b._parts["accent"]
			var cap_vertices: PackedVector3Array = cap["positions"]
			for index in cap_vertices.size(): cap_vertices[index].z += 0.03
			cap["positions"] = cap_vertices
		else:
			b.ellipsoid(Vector3(0, 0.931, 0.022), Vector3(0.154, 0.069, 0.10), "accent", 3, 20, 10)
		if not granny:
			b.ellipsoid(Vector3(0, 0.765, 0.065), Vector3(0.168, 0.18, 0.095), "accent", 3, 20, 12)
			for side: float in [-1.0, 1.0]:
				b.ellipsoid(Vector3(side * 0.143, 0.727, 0.006), Vector3(0.028, 0.112, 0.07), "accent", 3, 12, 8)
	if not hero:
		b.ellipsoid(Vector3(0, 0.642 if granny else 0.621, 0), Vector3(0.058, 0.035, 0.068), "skin", 3, 12, 8)
	_head_cage(b, face, 1.0)
	var eye_y := 0.703 if hero else 0.822 if granny else 0.797
	var eye_x := 0.069 if hero else 0.044
	for side: float in [-1.0, 1.0]:
		var ex := eye_x * side
		var ez := _face_z(face, 1.0, ex, eye_y)
		b.ellipsoid(Vector3(ex, eye_y, ez - 0.004), Vector3(0.019 if hero else 0.016, 0.009 if hero else 0.006, 0.006), "ink", 3, 12, 6)
		b.ellipsoid(Vector3(ex, eye_y, ez - 0.009), Vector3(0.015 if hero else 0.012, 0.006 if hero else 0.003, 0.003), "eye", 3, 12, 6)
		b.ellipsoid(Vector3(ex + side * 0.003, eye_y, ez - 0.012), Vector3(0.005, 0.005 if hero else 0.003, 0.002), "ink", 3, 8, 4)
		if hero:
			_face_line(b, face, 1.0, PackedVector3Array([Vector3(ex - 0.033, eye_y + 0.056, 0), Vector3(ex, eye_y + 0.067, 0), Vector3(ex + 0.033, eye_y + 0.054, 0)]), 0.0026)
			b.vertex_tints["trim"] = Color("ee8da8")
			var cx := side * 0.112
			var cy := 0.648
			b.ellipsoid(Vector3(cx, cy, _face_z(face, 1.0, cx, cy) - 0.002), Vector3(0.026, 0.020, 0.004), "trim", 3, 12, 6)
			b.vertex_tints["trim"] = Color("f6f3ea")
		else:
			_face_line(b, face, 1.0, PackedVector3Array([Vector3(ex - 0.017, eye_y - 0.014, 0), Vector3(ex, eye_y - 0.018, 0), Vector3(ex + 0.017, eye_y - 0.014, 0)]), 0.0017)
			_face_line(b, face, 1.0, PackedVector3Array([Vector3(side * 0.025, eye_y - 0.012, 0), Vector3(side * 0.035, eye_y - 0.051, 0), Vector3(side * 0.042, eye_y - 0.091, 0)]), 0.0020)
		var ear_y := 0.71 if hero else 0.82
		var ear_x := (0.179 if hero else 0.123 if granny else 0.152) * side
		b.ellipsoid(Vector3(ear_x, ear_y, 0.008), Vector3(0.017, 0.035, 0.027), "skin", 3, 12, 8)
	if hero:
		# The curled trunk is a real curved volume, visible in profile too.
		var trunk := PackedVector3Array([Vector3(0, 0.737, -0.12), Vector3(-0.006, 0.708, -0.14), Vector3(-0.006, 0.674, -0.151), Vector3(0.002, 0.654, -0.16), Vector3(0.021, 0.649, -0.169), Vector3(0.043, 0.66, -0.167), Vector3(0.049, 0.68, -0.16)])
		b.tube(trunk, 0.022, "skin", 3, 12)
		b.ellipsoid(Vector3(0.049, 0.68, -0.178), Vector3(0.0045, 0.0045, 0.003), "ink", 3, 8, 4)
		var mouth_y := 0.607
		var mouth_z := _face_z(face, 1.0, 0, mouth_y)
		b.ellipsoid(Vector3(0, mouth_y, mouth_z - 0.005), Vector3(0.062, 0.013, 0.009), "ink", 3, 16, 6)
		b.ellipsoid(Vector3(0, mouth_y, mouth_z - 0.013), Vector3(0.056, 0.008, 0.004), "eye", 3, 16, 6)
		for x: float in [-0.036, -0.018, 0.0, 0.018, 0.036]:
			b.tube(PackedVector3Array([Vector3(x, mouth_y - 0.007, mouth_z - 0.016), Vector3(x, mouth_y + 0.007, mouth_z - 0.016)]), 0.0012, "ink", 3, 5)
		_face_line(b, face, 1.0, PackedVector3Array([Vector3(-0.039, 0.577, 0), Vector3(0, 0.563, 0), Vector3(0.039, 0.577, 0)]), 0.0022)
		# A small yellow tuft, with no invented wool hat or dark hairstyle.
		for item: Vector4 in [Vector4(-0.045, 0.938, 0.041, 0.040), Vector4(0.0, 0.958, 0.046, 0.042), Vector4(0.045, 0.944, 0.042, 0.034)]:
			b.ellipsoid(Vector3(item.x, item.y, 0.0), Vector3(item.z, item.w, 0.061), "accent", 3, 14, 8)
	else:
		var nose_top := eye_y + 0.011
		var nose := PackedVector3Array([Vector3(-0.011, nose_top, -0.112), Vector3(-0.012, eye_y - 0.023, -0.135), Vector3(0, eye_y - 0.028, -0.144), Vector3(0.011, eye_y - 0.023, -0.135), Vector3(0.011, nose_top, -0.112)])
		b.tube(nose, 0.008, "skin", 3, 10)
		var mouth_y := eye_y - 0.052
		var mz := _face_z(face, 1.0, 0, mouth_y)
		b.ellipsoid(Vector3(0, mouth_y, mz - 0.005), Vector3(0.024 if granny else 0.032, 0.008 if granny else 0.012, 0.006), "ink", 3, 12, 6)
		if not granny:
			b.box(Vector3(0, mouth_y + 0.005, mz - 0.011), Vector3(0.038, 0.004, 0.003), "eye", 3)
		for x: float in [-0.07, 0.0, 0.07]:
			_face_line(b, face, 1.0, PackedVector3Array([Vector3(x - 0.027, 0.69 if granny else 0.677, 0), Vector3(x, 0.681 if granny else 0.667, 0), Vector3(x + 0.027, 0.69 if granny else 0.677, 0)]), 0.0021)
		if granny:
			for i in 9:
				var x := (i - 4) * 0.017
				var y := 0.91 + sqrt(maxf(0.0, 1.0 - pow(x / 0.095, 2))) * 0.017
				b.ellipsoid(Vector3(x, y, -0.083), Vector3(0.011, 0.012, 0.01), "trim", 3, 10, 6)

func _uniform_variant(drawing: String) -> Node3D:
	# The body is the existing approved uniform mesh; faces/hat/props are distinct
	# authored volumes. Source mesh/Skin/material resources remain immutable.
	var guard := drawing == "guard_alt"
	var source_model: Node3D = Guard.new().build_model() if guard else Police.new().build_model()
	var skeleton := source_model.get_node("Skeleton3D") as Skeleton3D
	var source := (skeleton.get_node("UniformMesh") as MeshInstance3D).mesh as ArrayMesh
	var b := Builder.new()
	for surface in source.get_surface_count():
		b.palette[source.surface_get_name(surface)] = source.surface_get_material(surface)
	var x_scale := 0.9 if drawing == "police_long" else 1.0
	var transforms: Dictionary = {}
	if drawing == "police_long":
		# His notebook arm hangs down; the other hand no longer writes on the page.
		for chain: Array in [[4, 5, 6, -0.90], [7, 8, 9, 1.02]]:
			var pivot := skeleton.get_bone_global_rest(chain[0]).origin
			var basis := Basis(Vector3.BACK, float(chain[3]))
			for index in range(3): transforms[chain[index]] = Transform3D(basis, pivot - basis * pivot)
	if guard:
		# Bend one forearm up to the chest radio, preserving the padded upper arm.
		var elbow := skeleton.get_bone_global_rest(5).origin
		var bend := Basis(Vector3.RIGHT, 2.30)
		transforms[5] = Transform3D(bend, elbow - bend * elbow)
		transforms[6] = transforms[5]
	for i in skeleton.get_bone_count():
		var origin := skeleton.get_bone_global_rest(i).origin
		if transforms.has(i): origin = (transforms[i] as Transform3D) * origin
		origin.x *= x_scale
		b.add_bone(skeleton.get_bone_name(i), skeleton.get_bone_parent(i), origin)
	for surface in source.get_surface_count():
		var key := source.surface_get_name(surface)
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for index in range(0, vertices.size(), 3):
			var bone := bones[index * 4]
			if bone == 3: continue
			# Young officer has a notebook, no writing pencil or projecting graphite.
			if drawing == "police_long" and bone == 9 and key in ["brass_pencil", "paper_eye", "piping"]: continue
			var points: Array[Vector3] = []
			var directions: Array[Vector3] = []
			for offset in 3:
				var point := vertices[index + offset]
				var normal := normals[index + offset]
				if transforms.has(bone):
					point = (transforms[bone] as Transform3D) * point
					normal = (transforms[bone] as Transform3D).basis * normal
				point.x *= x_scale
				normal = (normal / Vector3(x_scale, 1, 1)).normalized()
				points.append(point)
				directions.append(normal)
			b.vertex_tints[key] = colors[index]
			b._triangle(points[0], points[1], points[2], directions[0], directions[1], directions[2], key, bone)
	b.vertex_tints.clear()
	_variant_head(b, drawing)
	if guard:
		# Wool watch cap replaces the beret; compact radio has a solid antenna.
		b.ellipsoid(Vector3(0, 0.955, -0.015), Vector3(0.11, 0.045, 0.083), "armour", 3, 20, 10)
		b.vertex_tints["beret"] = Color("b3999d")
		b.ellipsoid(Vector3(0, 0.931, -0.017), Vector3(0.113, 0.018, 0.087), "beret", 3, 20, 6)
		b.vertex_tints.clear()
		for i in range(-4, 5):
			var x := float(i) * 0.021
			b.tube(PackedVector3Array([Vector3(x, 0.92, -0.083), Vector3(x, 0.938, -0.086)]), 0.0017, "suit", 3, 5)
		b.box(Vector3(0.14, 0.693, -0.181), Vector3(0.062, 0.10, 0.035), "ink", 2)
		b.tube(PackedVector3Array([Vector3(0.126, 0.74, -0.18), Vector3(0.12, 0.787, -0.182)]), 0.003, "ink", 2)
		for y in [0.692, 0.707, 0.722]: b.box(Vector3(0.14, y, -0.201), Vector3(0.044, 0.004, 0.006), "suit", 2)
	else:
		_variant_ushanka(b, drawing == "police_long")
	var model := b.build_node("Uniform_" + drawing)
	model.set_meta("variant_status", "authored face/hat/pose conversion; native comparison with approved variant SVG required")
	source_model.free()
	return model

func _variant_head(b: Builder, drawing: String) -> void:
	var guard := drawing == "guard_alt"
	var young := drawing == "police_long"
	var skin := "skin" if guard else "ochre_skin"
	var ink := "ink" if guard else "fur_leather_ink"
	var eye := "eye" if guard else "paper_eye"
	var y := 0.847 if guard else 0.815
	var w := 0.119 if guard else 0.112 if young else 0.15
	var jaw := w * (0.83 if young else 0.99)
	var bottom := 0.757 if guard else 0.69
	var levels: Array[Vector3] = [Vector3(jaw * 0.55, bottom, 0.05), Vector3(jaw, bottom + 0.018, 0.085), Vector3(w, y - 0.035, 0.105), Vector3(w * 0.87, y + 0.035, 0.104), Vector3(w * 0.78, y + 0.075, 0.08), Vector3(w * 0.48, y + 0.09, 0.045)]
	Police.new()._soft_volume(b, levels, skin, 3, Vector3(0, 0, -0.035), 2.7)
	for side: float in [-1.0, 1.0]:
		var x := side * 0.034
		var eye_y := y + 0.02 + side * 0.002
		b.ellipsoid(Vector3(x, eye_y, -0.139), Vector3(0.017, 0.008 if young or guard else 0.005, 0.005), eye, 3, 12, 6)
		b.ellipsoid(Vector3(x + 0.002, eye_y, -0.144), Vector3(0.0033, 0.0042, 0.002), ink, 3, 8, 4)
		b.tube(PackedVector3Array([Vector3(x - 0.021, eye_y + 0.011, -0.139), Vector3(x, eye_y + (0.02 if young and side < 0 else 0.014), -0.143), Vector3(x + 0.019, eye_y + 0.01, -0.138)]), 0.0031, ink, 3)
		b.ellipsoid(Vector3(side * w * 0.94, y + 0.016, -0.004), Vector3(0.017, 0.026, 0.02), skin, 3, 12, 6)
	b.ellipsoid(Vector3(0, y - 0.002, -0.144), Vector3(0.015, 0.028, 0.025 if young else 0.02), skin, 3, 12, 8)
	b.tube(PackedVector3Array([Vector3(-0.03, y - 0.046, -0.139), Vector3(0.004, y - 0.043, -0.147), Vector3(0.031, y - 0.049, -0.137)]), 0.002, ink, 3)
	if not young and not guard:
		# Two drooping grey moustache lobes distinguish the older round officer.
		for side: float in [-1.0, 1.0]:
			b.vertex_tints["paper_eye"] = Color("b7b6ae")
			b.ellipsoid(Vector3(side * 0.027, y - 0.022, -0.147), Vector3(0.027, 0.014, 0.012), "paper_eye", 3, 12, 6)
			b.ellipsoid(Vector3(side * 0.042, y - 0.037, -0.144), Vector3(0.013, 0.025, 0.01), "paper_eye", 3, 12, 6)
			b.tube(PackedVector3Array([Vector3(side * 0.05, y + 0.006, -0.132), Vector3(side * 0.071, y - 0.025, -0.129), Vector3(side * 0.082, y - 0.058, -0.117)]), 0.0016, ink, 3)
		b.vertex_tints.clear()
	if guard:
		for x: float in [-0.055, -0.036, -0.018, 0.0, 0.02, 0.041, 0.06]:
			b.ellipsoid(Vector3(x, y - 0.067 + absf(x) * 0.12, -0.13), Vector3(0.0016, 0.0024, 0.0015), ink, 3, 6, 4)

func _variant_ushanka(b: Builder, young: bool) -> void:
	var police := Police.new()
	var w := 0.15 if young else 0.176
	var levels: Array[Vector3] = [Vector3(w * 0.8, 0.889, 0.099), Vector3(w, 0.923, 0.123), Vector3(w * 0.95, 0.965, 0.119), Vector3(w * 0.64, 0.994, 0.08), Vector3(w * 0.24, 1.0, 0.03)]
	police._soft_volume(b, levels, "fur_leather_ink", 3, Vector3(0, 0, -0.033), 2.8)
	b.ellipsoid(Vector3(0, 0.909, -0.142), Vector3(w * 0.76, 0.031, 0.026), "fur_leather_ink", 3, 20, 8)
	b.ellipsoid(Vector3(0, 0.918, -0.169), Vector3(0.011, 0.011, 0.003), "brass_pencil", 3, 10, 6)
	for side: float in [-1.0, 1.0]:
		var raised := young and side < 0
		var y := 0.928 if raised else 0.827
		b.ellipsoid(Vector3(side * w * 0.88, y, -0.003), Vector3(0.033, 0.067 if raised else 0.096, 0.068), "fur_leather_ink", 3, 16, 8)
		for k in range(4):
			b.tube(PackedVector3Array([Vector3(side * w * 0.87 - 0.009, y - 0.035 + k * 0.02, -0.064), Vector3(side * w * 0.87 + 0.006, y - 0.032 + k * 0.02, -0.067)]), 0.0011, "navy", 3, 4)
