extends RefCounted
## Solid 3D translations of the approved character drawings. Soles=0, top=1, forward=-Z.
## Ilyusha and the other civilians follow the project's approved original 2D drawings.
const Builder = preload("res://game/characters/models/uniform_mesh_builder.gd")
const Police = preload("res://game/characters/models/police_model.gd")
const Guard = preload("res://game/characters/models/guard_model.gd")
const Residents = preload("res://game/characters/models/legacy_resident_models.gd")
# Historical foot_* names now identify civilian knee/lower-leg joints.
# Uniform models/variants retain their authored ankle rigs.
const CIVILIAN_KNEE_Y := 0.22
const DRAWINGS: Array[String] = ["ilyusha", "babka", "vendor", "officer", "resident_babka", "resident_man", "resident_woman", "resident_boy", "resident_shuba", "resident_beret", "resident_violet", "resident_ushanka", "resident_ushanka_walk", "resident_tourist", "resident_kid", "resident_kid2", "resident_dog", "resident_kolpak", "resident_bow", "resident_turban", "police_long", "police_round", "guard_alt"]
static var _models: Dictionary = {}
static var _materials: Dictionary = {}
static var _hero_materials: Dictionary = {}

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
			b.palette = _hero_palette()
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
	model.set_meta("design_status", "approved original 2D drawings translated to solid 3D; visual acceptance required")
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
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			_materials[key] = mat
	return _materials

func _hero_palette() -> Dictionary:
	if _hero_materials.is_empty():
		var contour := StandardMaterial3D.new()
		contour.resource_name = "Drawn character silhouette"
		contour.albedo_color = Color("282426")
		contour.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		contour.cull_mode = BaseMaterial3D.CULL_FRONT
		contour.grow = true
		contour.grow_amount = 0.0025
		for key: String in _palette():
			var material: StandardMaterial3D = _materials[key].duplicate()
			if key not in ["ink", "eye"]:
				material.next_pass = contour
			_hero_materials[key] = material
	return _hero_materials

func _design(drawing: String) -> Dictionary:
	match drawing:
		"ilyusha": return {"drawing": drawing, "hem": 0.274, "shoulder": 0.535, "width": 0.18, "head_y": 0.63, "elbow_y": 0.425, "hand_y": 0.293}
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
		var elbow_at := Vector3(side * 0.245, 0.45, -0.035) if vendor else Vector3(side * (x + 0.022), d.get("elbow_y", shoulder - 0.17), -0.005)
		var hand_at := Vector3(side * 0.114, 0.394, -0.20) if vendor else Vector3(side * (x + 0.027), d.get("hand_y", shoulder - 0.285), -0.015)
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
		var center_z := lerpf(d.get("cuff_z", -0.007), -0.007, float(j) / (levels.size() - 1))
		for i in SIDES:
			var angle := TAU * float(i) / SIDES
			var c := cos(angle)
			var z := sin(angle)
			points.append(Vector3(side * (levels[j].x + c * levels[j].z), levels[j].y, z * levels[j].w + center_z))
			var slope := -(next.x - previous.x) / dy * c / levels[j].z - (next.z - previous.z) / dy * c * c / levels[j].z - (next.w - previous.w) / dy * z * z / levels[j].w
			normals.append(Vector3(side * c / levels[j].z, slope, z / levels[j].w).normalized())
	for j in range(levels.size() - 1):
		for i in SIDES:
			var a := j * SIDES + i
			var c := j * SIDES + (i + 1) % SIDES
			b._triangle(points[a], points[a + SIDES], points[c + SIDES], normals[a], normals[a + SIDES], normals[c + SIDES], "cloth", upper)
			b._triangle(points[a], points[c + SIDES], points[c], normals[a], normals[c + SIDES], normals[c], "cloth", upper)
	for j in [0, levels.size() - 1]:
		var center := Vector3(side * levels[j].x, levels[j].y, d.get("cuff_z", -0.007) if j == 0 else -0.007)
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

func _face_oval(b: Builder, face: Array[Vector3], x: float, y: float, rx: float, ry: float, material: String, offset: float, upper_limit: float = INF) -> void:
	var front := Vector3(x, y, _face_z(face, 0.72, x, y) - offset)
	var back := front + Vector3(0, 0, 0.001)
	for i in 20:
		var angle := TAU * float(i) / 20.0
		var next := TAU * float(i + 1) / 20.0
		var a := Vector3(x + cos(angle) * rx, y + sin(angle) * ry, 0)
		var c := Vector3(x + cos(next) * rx, y + sin(next) * ry, 0)
		a.y = minf(a.y, upper_limit)
		c.y = minf(c.y, upper_limit)
		a.z = _face_z(face, 0.72, a.x, a.y) - offset
		c.z = _face_z(face, 0.72, c.x, c.y) - offset
		b._triangle(front, a, c, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, material, 3)
		b._triangle(back, c + Vector3(0, 0, 0.001), a + Vector3(0, 0, 0.001), Vector3.BACK, Vector3.BACK, Vector3.BACK, material, 3)
		var edge_normal := Vector3(cos(angle), sin(angle), 0)
		b._triangle(a, a + Vector3(0, 0, 0.001), c + Vector3(0, 0, 0.001), edge_normal, edge_normal, edge_normal, material, 3)
		b._triangle(a, c + Vector3(0, 0, 0.001), c, edge_normal, edge_normal, edge_normal, material, 3)

func _curve(a: Vector3, control: Vector3, end: Vector3, count: int = 10) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in range(count + 1):
		var t := float(i) / count
		points.append(a * (1 - t) * (1 - t) + control * 2 * t * (1 - t) + end * t * t)
	return points

func _ilyusha_svg_curve(a: Vector2, control_a: Vector2, control_b: Vector2, end: Vector2, steps: int = 12) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(steps + 1):
		var t := float(index) / steps
		points.append(a * pow(1.0 - t, 3) + control_a * 3.0 * pow(1.0 - t, 2) * t + control_b * 3.0 * (1.0 - t) * t * t + end * t * t * t)
	return points

func _ilyusha_svg_rows(outline: PackedVector2Array, depth_ratio: float) -> Array[Vector3]:
	# The drawing's baseline is y=590 and its tuft crest is approximately y=49.
	var rows: Array[Vector3] = []
	for index in range(outline.size() - 1, -1, -1):
		var point := outline[index]
		var width := maxf(absf(point.x - 200.0) / 541.0, 0.002)
		rows.append(Vector3(width, (590.0 - point.y) / 541.0, maxf(width * depth_ratio, 0.004)))
	return rows

func _ilyusha_head_rows() -> Array[Vector3]:
	var outline := _ilyusha_svg_curve(Vector2(200, 86), Vector2(258, 86), Vector2(278, 150), Vector2(294, 206))
	outline.append_array(_ilyusha_svg_curve(Vector2(294, 206), Vector2(308, 264), Vector2(262, 302), Vector2(200, 302)).slice(1))
	return _ilyusha_svg_rows(outline, 0.88)

func _ilyusha_coat_rows() -> Array[Vector3]:
	# Right half of the same cubic paths used by jacket_front(), including its top.
	var outline := _ilyusha_svg_curve(Vector2(200, 286.5), Vector2(243.75, 286.5), Vector2(287.5, 291), Vector2(305, 300), 4)
	outline.append_array(_ilyusha_svg_curve(Vector2(305, 300), Vector2(332, 332), Vector2(328, 420), Vector2(298, 442)).slice(1))
	return _ilyusha_svg_rows(outline, 0.82)

func _fur_collar(b: Builder) -> void:
	const AROUND := 48
	const CROSS := 8
	var points: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for i in AROUND:
		var angle := TAU * i / AROUND
		var outward := Vector3(cos(angle), 0, sin(angle)).normalized()
		var center := Vector3(cos(angle) * 0.164, 0.580 - maxf(0.0, -sin(angle)) * 0.047, sin(angle) * 0.114)
		var lobe := 0.031 + 0.007 * cos(angle * 11.0)
		var vertical_lobe := 0.031 + 0.009 * cos(angle * 11.0)
		for j in CROSS:
			var cross_angle := TAU * j / CROSS
			var normal := outward * cos(cross_angle) + Vector3.UP * sin(cross_angle)
			points.append(center + outward * cos(cross_angle) * lobe + Vector3.UP * sin(cross_angle) * vertical_lobe)
			normals.append(normal.normalized())
	for i in AROUND:
		for j in CROSS:
			var a := i * CROSS + j
			var c := ((i + 1) % AROUND) * CROSS + j
			var d := ((i + 1) % AROUND) * CROSS + (j + 1) % CROSS
			var e := i * CROSS + (j + 1) % CROSS
			b._triangle(points[a], points[c], points[d], normals[a], normals[c], normals[d], "trim", 2)
			b._triangle(points[a], points[d], points[e], normals[a], normals[d], normals[e], "trim", 2)

func _tuft(b: Builder) -> void:
	# One joined lumpy silhouette from the authored tuft, with a rounded front/back.
	var source := _ilyusha_svg_curve(Vector2(156, 106), Vector2(144, 88), Vector2(160, 70), Vector2(176, 74), 6)
	for curve: Array in [[Vector2(176, 74), Vector2(178, 54), Vector2(198, 42), Vector2(210, 54)],
		[Vector2(210, 54), Vector2(228, 50), Vector2(244, 66), Vector2(238, 80)],
		[Vector2(238, 80), Vector2(256, 86), Vector2(254, 106), Vector2(240, 108)],
		[Vector2(240, 108), Vector2(210, 114), Vector2(180, 114), Vector2(156, 106)]]:
		source.append_array(_ilyusha_svg_curve(curve[0], curve[1], curve[2], curve[3], 6).slice(1))
	source.resize(source.size() - 1)
	var outline: Array[Vector2] = []
	for point in source: outline.append(Vector2((200.0 - point.x) / 541.0, minf(1.0, (590.0 - point.y) / 541.0)))
	var center := Vector2(0, (590.0 - 84.0) / 541.0)
	const DEPTH := 0.082
	const RINGS := 8
	var points: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for ring in range(RINGS + 1):
		var t := PI * float(ring) / RINGS
		for point in outline:
			var xy := center + (point - center) * sin(t)
			points.append(Vector3(xy.x, xy.y, -cos(t) * DEPTH))
			var radial := Vector3((point.x - center.x) / 0.09, (point.y - center.y) / 0.06, 0).normalized()
			normals.append((radial * sin(t) + Vector3.FORWARD * cos(t)).normalized())
	for ring in RINGS:
		for i in outline.size():
			var a := ring * outline.size() + i
			var c := ring * outline.size() + (i + 1) % outline.size()
			var d := c + outline.size()
			var e := a + outline.size()
			b._triangle(points[a], points[c], points[d], normals[a], normals[c], normals[d], "accent", 3)
			b._triangle(points[a], points[d], points[e], normals[a], normals[d], normals[e], "accent", 3)
	for spec: Vector4 in [Vector4(-0.041, 0.928, 0.022, 0.016), Vector4(0.011, 0.939, 0.022, 0.016), Vector4(-0.011, 0.969, 0.015, 0.011), Vector4(0.044, 0.913, 0.018, 0.013)]:
		var line := _curve(Vector3(spec.x - spec.z, spec.y, 0), Vector3(spec.x, spec.y + spec.w, 0), Vector3(spec.x + spec.z, spec.y, 0), 6)
		for index in line.size():
			line[index].x = -line[index].x
			var ray := Vector2(line[index].x, line[index].y) - center
			var boundary := INF
			for edge_index in outline.size():
				var a := outline[edge_index] - center
				var edge := outline[(edge_index + 1) % outline.size()] - outline[edge_index]
				var denominator := ray.cross(edge)
				if absf(denominator) < 0.000001: continue
				var along := a.cross(ray) / denominator
				var distance := a.cross(edge) / denominator
				if along >= 0.0 and along <= 1.0 and distance > 0.0: boundary = minf(boundary, distance)
			var fraction := 0.0 if is_inf(boundary) else 1.0 / boundary
			line[index].z = -DEPTH * sqrt(maxf(0.0, 1.0 - fraction * fraction)) - 0.003
		b.tube(line, 0.0022, "ink", 3, 5)

func _cap_lace(b: Builder) -> void:
	const STEPS := 48
	var bottom := PackedVector3Array()
	var top := PackedVector3Array()
	for i in range(STEPS + 1):
		var t := float(i) / STEPS
		var x := lerpf(-0.083, 0.083, t)
		var base_y := 0.902 + 0.018 * sin(t * PI) + x * 0.07
		bottom.append(Vector3(x, base_y, -0.080))
		top.append(Vector3(x, base_y + 0.011 + sin(fmod(t * 6.0, 1.0) * PI) * 0.012, -0.080))
	for i in STEPS:
		for shift in [0.0, 0.004]:
			var dz := Vector3(0, 0, shift)
			var n := Vector3.FORWARD if shift == 0.0 else Vector3.BACK
			b._triangle(bottom[i] + dz, bottom[i + 1] + dz, top[i + 1] + dz, n, n, n, "trim", 3)
			b._triangle(bottom[i] + dz, top[i + 1] + dz, top[i] + dz, n, n, n, "trim", 3)
		for boundary in [bottom, top]:
			var a: Vector3 = boundary[i]
			var c: Vector3 = boundary[i + 1]
			var n := Vector3.DOWN if boundary == bottom else Vector3.UP
			b._triangle(a, c, c + Vector3(0, 0, 0.004), n, n, n, "trim", 3)
			b._triangle(a, c + Vector3(0, 0, 0.004), a + Vector3(0, 0, 0.004), n, n, n, "trim", 3)

func _bow_panel(b: Builder, polygon: PackedVector2Array, z: float) -> void:
	var indices := Geometry2D.triangulate_polygon(polygon)
	for index in range(0, indices.size(), 3):
		var vertices: Array[Vector3] = []
		for corner in 3:
			var xy := polygon[indices[index + corner]]
			vertices.append(Vector3(xy.x, xy.y, z))
		for dz in [0.0, 0.009]:
			var n := Vector3.FORWARD if dz == 0.0 else Vector3.BACK
			b._triangle(vertices[0] + Vector3(0, 0, dz), vertices[1] + Vector3(0, 0, dz), vertices[2] + Vector3(0, 0, dz), n, n, n, "cloth", 2)
	for index in polygon.size():
		var a := Vector3(polygon[index].x, polygon[index].y, z)
		var c := Vector3(polygon[(index + 1) % polygon.size()].x, polygon[(index + 1) % polygon.size()].y, z)
		var normal := Vector3(c.y - a.y, a.x - c.x, 0).normalized()
		b._triangle(a, c, c + Vector3(0, 0, 0.009), normal, normal, normal, "cloth", 2)
		b._triangle(a, c + Vector3(0, 0, 0.009), a + Vector3(0, 0, 0.009), normal, normal, normal, "cloth", 2)

func _offset_new_part(b: Builder, material: String, start: int, offset: Vector3) -> void:
	var part: Dictionary = b._parts[material]
	var points: PackedVector3Array = part["positions"]
	for index in range(start, points.size()): points[index] += offset
	part["positions"] = points

func _ilyusha_row_at(rows: Array[Vector3], y: float) -> Vector3:
	for index in range(rows.size() - 1):
		if y >= rows[index].y and y <= rows[index + 1].y:
			return rows[index].lerp(rows[index + 1], (y - rows[index].y) / (rows[index + 1].y - rows[index].y))
	return rows[0] if y < rows[0].y else rows[-1]

func _ilyusha_boot(b: Builder, side: float, foot: int) -> void:
	var x := side * 48.0 / 541.0
	b.vertex_tints["cloth"] = Color("3a3436")
	b.ellipsoid(Vector3(x, 0.038, -0.025), Vector3(0.085, 0.038, 0.102), "cloth", foot, 20, 10)
	var start: int = b._parts["ink"]["positions"].size() if b._parts.has("ink") else 0
	b.body_profile([Vector3(0.070, 0.0, 0.087), Vector3(0.085, 0.009, 0.102), Vector3(0.084, 0.019, 0.101)], "ink", foot, 20)
	_offset_new_part(b, "ink", start, Vector3(x, 0, -0.025))
	b.tube(PackedVector3Array([Vector3(x - 0.037, 0.051, -0.115), Vector3(x + 0.037, 0.051, -0.115)]), 0.002, "ink", foot, 5)

func _ilyusha_hand(b: Builder, side: float, hand: int) -> void:
	var x := side * 126.0 / 541.0
	b.ellipsoid(Vector3(x, 0.291, -0.013), Vector3(0.038, 0.041, 0.025), "skin", hand, 16, 10)
	b.tube(_curve(Vector3(x - side * 0.011, 0.285, -0.038), Vector3(x - side * 0.004, 0.263, -0.037), Vector3(x + side * 0.007, 0.259, -0.032)), 0.0018, "ink", hand, 5)

func _ilyusha_sleeve(b: Builder, side: float, upper: int, lower: int) -> void:
	var rows: Array[Vector3] = [Vector3(0.035, 0.330, 0.048), Vector3(0.037, 0.373, 0.056), Vector3(0.044, 0.438, 0.064), Vector3(0.047, 0.489, 0.066), Vector3(0.034, 0.534, 0.050)]
	var start: int = b._parts["cloth"]["positions"].size()
	b.body_profile(rows, "cloth", upper, 20)
	var part: Dictionary = b._parts["cloth"]
	var points: PackedVector3Array = part["positions"]
	var bones: PackedInt32Array = part["bones"]
	var weights: PackedFloat32Array = part["weights"]
	for index in range(start, points.size()):
		var upper_amount := clampf((points[index].y - 0.330) / 0.204, 0.0, 1.0)
		points[index].x += side * lerpf(0.233, 0.175, upper_amount)
		var bend := 1.0 - smoothstep(0.400, 0.465, points[index].y)
		bones[index * 4 + 1] = lower
		weights[index * 4] = 1.0 - bend
		weights[index * 4 + 1] = bend
	part["positions"] = points
	part["bones"] = bones
	part["weights"] = weights
	var y := (590.0 - 372.0) / 541.0
	var band := _ilyusha_row_at(rows, y)
	var cx := side * lerpf(0.233, 0.175, (y - 0.330) / 0.204)
	var line := PackedVector3Array()
	for index in 13:
		var x := lerpf(-band.x * 0.88, band.x * 0.88, float(index) / 12.0)
		var curve_y := y - sin(float(index) * PI / 12.0) * 0.008
		var z := -band.z * sqrt(maxf(0.0, 1.0 - pow(x / band.x, 2))) - 0.002
		line.append(Vector3(cx + x, curve_y, z))
	b.tube(line, 0.0018, "ink", lower, 5)

func _approved_hero(b: Builder, drawing: String) -> void:
	var hero := drawing == "ilyusha"
	var granny := drawing == "babka"
	b.vertex_tints["cloth"] = Color("a2f03a") if hero else Color("b6ba78") if granny else Color("4e3b2d")
	b.vertex_tints["skin"] = Color("f4b3cd") if hero else Color("fffde2") if granny else Color("ebd198")
	b.vertex_tints["accent"] = Color("ebc458") if hero else Color("a9ad6e") if granny else Color("8c3b3b")
	b.vertex_tints["trim"] = Color("f6f3ea") if hero else Color.WHITE if granny else Color("b9b2a0")
	var hem := 0.274 if hero else 0.045 if granny else 0.04
	var shoulder := 0.535 if hero else 0.615 if granny else 0.59
	var width := 0.18 if hero else 0.265 if granny else 0.23
	var levels: Array[Vector3] = [Vector3(width * 0.83, hem, 0.11), Vector3(width, hem + 0.06, 0.14), Vector3(width * 1.06, (hem + shoulder) * 0.5, 0.15), Vector3(width, shoulder - 0.045, 0.14), Vector3(width * 0.70, shoulder, 0.095)]
	if granny:
		levels = [Vector3(0.292, hem, 0.125), Vector3(0.315, 0.13, 0.152), Vector3(0.327, 0.32, 0.169), Vector3(0.314, 0.46, 0.163), Vector3(0.280, 0.57, 0.143), Vector3(0.222, 0.64, 0.108), Vector3(0.157, 0.668, 0.080), Vector3(0.151, 0.692, 0.067), Vector3(0.120, 0.715, 0.045), Vector3(0.070, 0.730, 0.030)]
	elif hero:
		levels = _ilyusha_coat_rows()
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
	if hero:
		b.vertex_tints["cloth"] = Color("2f8a36")
		b.box(Vector3(0, 0.261, 0.012), Vector3(172.0 / 541.0, 26.0 / 541.0, 0.146), "cloth", 1)
	# Hips and legs remain separate solids with the existing animation skeleton.
	for side: float in [-1.0, 1.0]:
		var leg := 10 if side > 0 else 12
		var foot := leg + 1
		var upper := 4 if side > 0 else 7
		var lower := upper + 1
		var hand := upper + 2
		b.vertex_tints["cloth"] = Color("2f8a36") if hero else Color("68635b")
		if hero:
			var start: int = b._parts["cloth"]["positions"].size()
			var leg_rows: Array[Vector3] = [Vector3(42.0 / 541.0, 34.0 / 541.0, 0.069), Vector3(45.0 / 541.0, 70.0 / 541.0, 0.074), Vector3(46.4 / 541.0, 110.0 / 541.0, 0.076), Vector3(46.0 / 541.0, 154.0 / 541.0, 0.075)]
			b.body_profile(leg_rows, "cloth", leg, 20)
			var trousers: Dictionary = b._parts["cloth"]
			var trouser_vertices: PackedVector3Array = trousers["positions"]
			for index in range(start, trouser_vertices.size()):
				trouser_vertices[index] += Vector3(side * 48.0 / 541.0, 0, 0.012)
			trousers["positions"] = trouser_vertices
		else:
			b.ellipsoid(Vector3(side * 0.087, 0.166, 0.012), Vector3(0.045, 0.14, 0.077), "cloth", leg, 12, 8)
		if hero:
			_ilyusha_boot(b, side, foot)
		else:
			b.ellipsoid(Vector3(side * 0.087, 0.038, -0.025), Vector3(0.045, 0.038, 0.093), "ink", foot, 14, 8)
			b.box(Vector3(side * 0.087, 0.008, -0.027), Vector3(0.08, 0.016, 0.15), "ink", foot)
		b.vertex_tints["cloth"] = Color("a2f03a") if hero else Color("b6ba78") if granny else Color("4e3b2d")
		var x := side * (width + 0.018)
		if drawing == "vendor":
			_vendor_sleeve(b, side, upper, lower)
			b.ellipsoid(Vector3(side * 0.114, 0.394, -0.20), Vector3(0.058, 0.033, 0.037), "skin", hand, 14, 8)
			for finger in 4:
				var finger_x := side * 0.114 + (finger - 1.5) * 0.021
				b.tube(PackedVector3Array([Vector3(finger_x, 0.39, -0.232), Vector3(finger_x, 0.376, -0.234)]), 0.0018, "ink", hand, 5)
		elif hero:
			_ilyusha_sleeve(b, side, upper, lower)
			_ilyusha_hand(b, side, hand)
		else:
			_sleeve(b, {"width": width - (0.038 if granny else 0.004), "shoulder": shoulder, "cuff_y": shoulder - 0.24, "cuff_z": -0.115 if granny else -0.007}, side, upper, lower)
			b.ellipsoid(Vector3(x, shoulder - 0.285, -0.140 if granny else -0.016), Vector3(0.040, 0.047, 0.024 if granny else 0.044), "skin", hand, 14, 8)
		if granny:
			b.ellipsoid(Vector3(x, shoulder - 0.24, -0.115), Vector3(0.05, 0.016, 0.035), "trim", lower, 12, 6)
			for finger in 4:
				var finger_x := x + (finger - 1.5) * 0.017
				b.ellipsoid(Vector3(finger_x, shoulder - 0.325, -0.147), Vector3(0.009, 0.038, 0.014), "skin", hand, 8, 6)
				b.ellipsoid(Vector3(finger_x, shoulder - 0.350, -0.161), Vector3(0.0038, 0.005, 0.001), "ink", hand, 6, 4)
	if hero:
		# Quilted bands wrap around the full jacket rather than lying on a card.
		for y: float in [(590.0 - 344.0) / 541.0, (590.0 - 392.0) / 541.0]:
			var seam := PackedVector3Array()
			for i in 25:
				var a := TAU * i / 24.0
				var drop := absf(sin(a)) * 8.0 / 541.0
				var row := _ilyusha_row_at(levels, y - drop)
				seam.append(Vector3(cos(a) * (row.x + 0.001), y - drop, sin(a) * (row.z + 0.001)))
			b.tube(seam, 0.0022, "ink", 2, 4)
		var zip := PackedVector3Array()
		for row in levels: zip.append(Vector3(0, row.y, -row.z - 0.002))
		b.tube(zip, 0.0018, "ink", 2, 4)
		_fur_collar(b)
		var hood_center := Vector3(0, (590.0 - 310.0) / 541.0, 0.146)
		var hood_radii := Vector3(64.0 / 541.0, 44.0 / 541.0, 0.060)
		b.ellipsoid(hood_center, hood_radii, "cloth", 2, 20, 10)
		var hood_line := _curve(Vector3(-42.0 / 541.0, (590.0 - 300.0) / 541.0, 0), Vector3(0, (590.0 - 326.0) / 541.0, 0), Vector3(42.0 / 541.0, (590.0 - 300.0) / 541.0, 0))
		for index in hood_line.size():
			var section := 1.0 - pow(hood_line[index].x / hood_radii.x, 2) - pow((hood_line[index].y - hood_center.y) / hood_radii.y, 2)
			hood_line[index].z = hood_center.z + hood_radii.z * sqrt(maxf(0.0, section)) + 0.002
		b.tube(hood_line, 0.0022, "ink", 2, 5)
		b.tube(PackedVector3Array([Vector3(0, 138.0 / 541.0, -0.064), Vector3(0, 128.0 / 541.0, -0.064)]), 0.0018, "ink", 1, 5)
	elif granny:
		for i in 10:
			var y := 0.12 + i * 0.046
			b.ellipsoid(Vector3(0, y, _face_z(levels, 1.0, 0, y) - 0.002), Vector3(0.0034, 0.004, 0.003), "ink", 2, 8, 4)
		_front_jabot(b, levels)
	else:
		for side: float in [-1.0, 1.0]:
			b.tube(PackedVector3Array([Vector3(side * 0.11, 0.54, -0.149), Vector3(side * 0.14, 0.61, -0.10)]), 0.008, "trim", 2, 6)
		b.vertex_tints["cloth"] = Color("c9433a")
		for side: float in [-1.0, 1.0]:
			_bow_panel(b, PackedVector2Array([Vector2(side * 0.006, 0.596), Vector2(side * 0.071, 0.629), Vector2(side * 0.060, 0.568)]), -0.139)
			_bow_panel(b, PackedVector2Array([Vector2(side * 0.011, 0.587), Vector2(side * 0.041, 0.513), Vector2(side * 0.009, 0.524)]), -0.154)
		b.ellipsoid(Vector3(0, 0.59, -0.14), Vector3(0.018, 0.018, 0.011), "cloth", 2, 12, 6)
		b.vertex_tints["cloth"] = Color("4e3b2d")
	var face: Array[Vector3]
	if hero:
		face = _ilyusha_head_rows()
	elif granny:
		face = [Vector3(0.02, 0.64, 0.035), Vector3(0.08, 0.65, 0.073), Vector3(0.123, 0.68, 0.099), Vector3(0.129, 0.73, 0.109), Vector3(0.106, 0.80, 0.103), Vector3(0.096, 0.87, 0.09), Vector3(0.082, 0.901, 0.071), Vector3(0.02, 0.91, 0.025)]
	else:
		face = [Vector3(0.025, 0.635, 0.035), Vector3(0.105, 0.645, 0.076), Vector3(0.155, 0.680, 0.102), Vector3(0.174, 0.715, 0.110), Vector3(0.165, 0.760, 0.108), Vector3(0.145, 0.820, 0.100), Vector3(0.129, 0.865, 0.086), Vector3(0.108, 0.906, 0.071), Vector3(0.065, 0.928, 0.049)]
	if not hero:
		# Closed cap/back of headscarf with hanging side panels; face stays exposed.
		if granny:
			b.body_profile([Vector3(0.095, 0.78, 0.065), Vector3(0.110, 0.86, 0.090), Vector3(0.109, 0.965, 0.089), Vector3(0.095, 0.985, 0.079), Vector3(0.064, 0.996, 0.052), Vector3(0.012, 0.999, 0.012)], "accent", 3, 24)
			var cap: Dictionary = b._parts["accent"]
			var cap_vertices: PackedVector3Array = cap["positions"]
			for index in cap_vertices.size():
				cap_vertices[index].y += cap_vertices[index].x * 0.060
				cap_vertices[index].z += 0.03
			cap["positions"] = cap_vertices
		else:
			b.body_profile([Vector3(0.180, 0.610, 0.082), Vector3(0.188, 0.650, 0.102), Vector3(0.183, 0.760, 0.117), Vector3(0.167, 0.870, 0.112), Vector3(0.153, 0.947, 0.091), Vector3(0.127, 0.978, 0.077), Vector3(0.077, 0.995, 0.046), Vector3(0.010, 1.0, 0.010)], "accent", 3, 28)
			var scarf: Dictionary = b._parts["accent"]
			var scarf_points: PackedVector3Array = scarf["positions"]
			for index in scarf_points.size(): scarf_points[index].z += 0.042
			scarf["positions"] = scarf_points
	if not hero:
		b.ellipsoid(Vector3(0, 0.642 if granny else 0.621, 0), Vector3(0.058, 0.035, 0.068), "skin", 3, 12, 8)
	_head_cage(b, face, 0.72)
	var eye_y := (590.0 - 206.0) / 541.0 if hero else 0.822 if granny else 0.797
	var eye_x := 38.0 / 541.0 if hero else 0.044 if granny else 0.046
	for side: float in [-1.0, 1.0]:
		var ex := eye_x * side
		if hero:
			b.vertex_tints["trim"] = Color("e296b6")
			_face_oval(b, face, ex, eye_y, 17.0 / 541.0, 13.0 / 541.0, "trim", 0.0010)
			b.vertex_tints["trim"] = Color("f6f3ea")
		var eye_w := 9.0 / 541.0 if hero else 0.014 if granny else 0.022
		var eye_h := 5.0 / 541.0 if hero else 0.0055 if granny else 0.009
		var lid_y := eye_y + 0.0015
		var lid_limit := INF if hero else lid_y
		_face_oval(b, face, ex, eye_y, eye_w + 0.0025, eye_h + 0.0025, "ink", 0.0022, lid_limit + 0.003)
		_face_oval(b, face, ex, eye_y, eye_w, eye_h, "eye", 0.0033, lid_limit)
		_face_oval(b, face, ex + side * 0.003, eye_y - 0.0007, 3.2 / 541.0 if hero else 0.0040 if granny else 0.0051, 3.2 / 541.0 if hero else 0.0040 if granny else 0.0051, "ink", 0.0044, lid_limit)
		if hero:
			_face_line(b, face, 0.72, _curve(Vector3(ex - 13.0 / 541.0, 389.0 / 541.0, 0), Vector3(ex, 394.0 / 541.0, 0), Vector3(ex + 13.0 / 541.0, 389.0 / 541.0, 0)), 0.0029, "ink", 0.005)
		else:
			_face_line(b, face, 0.72, _curve(Vector3(ex - eye_w - 0.003, lid_y, 0), Vector3(ex, lid_y + 0.007, 0), Vector3(ex + eye_w + 0.003, lid_y, 0)), 0.0028 if not granny else 0.0020, "ink", 0.005)
		if hero:
			_face_line(b, face, 0.72, _curve(Vector3(ex - 18.0 / 541.0, 414.0 / 541.0, 0), Vector3(ex, 424.0 / 541.0, 0), Vector3(ex + 18.0 / 541.0, 412.0 / 541.0, 0)), 0.0029)
			b.vertex_tints["trim"] = Color("ee8da8")
			var cx := side * 62.0 / 541.0
			var cy := 354.0 / 541.0
			_face_oval(b, face, cx, cy, 15.0 / 541.0, 12.0 / 541.0, "trim", 0.0013)
			b.vertex_tints["trim"] = Color("f6f3ea")
		else:
			_face_line(b, face, 0.72, _curve(Vector3(ex - 0.017, eye_y - 0.015, 0), Vector3(ex, eye_y - 0.024, 0), Vector3(ex + 0.017, eye_y - 0.015, 0)), 0.0019)
			_face_line(b, face, 0.72, _curve(Vector3(side * 0.020, eye_y - 0.010, 0), Vector3(side * 0.035, eye_y - 0.045, 0), Vector3(side * 0.042, eye_y - 0.091, 0)), 0.0023)
		var ear_y := 378.0 / 541.0 if hero else 0.82
		var ear_x := (96.0 / 541.0 if hero else 0.123 if granny else 0.152) * side
		if hero:
			var ear := _curve(Vector3(ear_x, ear_y + 16.0 / 541.0, 0), Vector3(ear_x + side * 0.036, ear_y, -0.006), Vector3(ear_x, ear_y - 16.0 / 541.0, 0))
			b.tube(ear, 0.006, "skin", 3, 8)
			for index in ear.size(): ear[index].z -= 0.007
			b.tube(ear, 0.0018, "ink", 3, 5)
		else:
			b.ellipsoid(Vector3(ear_x, ear_y, 0.008), Vector3(0.017, 0.035, 0.027), "skin", 3, 12, 8)
	if hero:
		# The curled trunk is a real curved volume, visible in profile too.
		var nose_xy := _ilyusha_svg_curve(Vector2(200, 190), Vector2(194, 214), Vector2(194, 236), Vector2(208, 242), 8)
		nose_xy.append_array(_ilyusha_svg_curve(Vector2(208, 242), Vector2(222, 248), Vector2(234, 236), Vector2(230, 222), 8).slice(1))
		var trunk := PackedVector3Array()
		for index in nose_xy.size():
			var t := float(index) / (nose_xy.size() - 1)
			trunk.append(Vector3((200.0 - nose_xy[index].x) / 541.0, (590.0 - nose_xy[index].y) / 541.0, lerpf(-0.151, -0.297, smoothstep(0.0, 1.0, t))))
		b.tube(trunk, 0.0215, "skin", 3, 12)
		b.ellipsoid(trunk[-1], Vector3.ONE * 0.0215, "skin", 3, 12, 7)
		b.ellipsoid(trunk[-1] + Vector3.FORWARD * 0.022, Vector3(0.0059, 0.0059, 0.002), "ink", 3, 8, 4)
		var mouth_y := 332.0 / 541.0
		_face_oval(b, face, 1.0 / 541.0, mouth_y, 33.0 / 541.0, 8.0 / 541.0, "ink", 0.0022)
		_face_oval(b, face, 1.0 / 541.0, mouth_y, 29.0 / 541.0, 4.5 / 541.0, "eye", 0.0034)
		for x: float in [-20.0, -10.0, 0.0, 10.0, 20.0]:
			_face_line(b, face, 0.72, PackedVector3Array([Vector3(x / 541.0, 328.0 / 541.0, 0), Vector3(x / 541.0, 337.0 / 541.0, 0)]), 0.0014, "ink", 0.0048)
		_face_line(b, face, 0.72, _curve(Vector3(-22.0 / 541.0, 314.0 / 541.0, 0), Vector3(0, 300.0 / 541.0, 0), Vector3(22.0 / 541.0, 314.0 / 541.0, 0)), 0.0028)
		_tuft(b)
	else:
		var nose_top := eye_y + 0.011
		var nose := PackedVector3Array([Vector3(-0.011, nose_top, -0.112), Vector3(-0.012, eye_y - 0.023, -0.135), Vector3(0, eye_y - 0.028, -0.144), Vector3(0.011, eye_y - 0.023, -0.135), Vector3(0.011, nose_top, -0.112)])
		b.tube(nose, 0.008, "skin", 3, 10)
		_face_line(b, face, 0.72, _curve(Vector3(-0.011, nose_top, 0), Vector3(-0.018, eye_y - 0.045, 0), Vector3(0.011, eye_y - 0.023, 0)), 0.0022)
		var mouth_y := eye_y - 0.052
		var mz := _face_z(face, 0.72, 0, mouth_y)
		_face_oval(b, face, 0, mouth_y, 0.024 if granny else 0.032, 0.005 if granny else 0.012, "ink", 0.003)
		if not granny:
			b.box(Vector3(0, mouth_y + 0.005, mz - 0.011), Vector3(0.038, 0.004, 0.003), "eye", 3)
		for x: float in [-0.07, 0.0, 0.07]:
			_face_line(b, face, 0.72, _curve(Vector3(x - 0.027, 0.69 if granny else 0.677, 0), Vector3(x, 0.672 if granny else 0.656, 0), Vector3(x + 0.027, 0.69 if granny else 0.677, 0)), 0.0023)
		if granny:
			_cap_lace(b)

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
