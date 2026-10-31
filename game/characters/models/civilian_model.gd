extends RefCounted
## Original City N visual models. Bind space: soles=0, top=1, forward=-Z.
## These drawing IDs preserve callers' gameplay roles, not the old borrowed designs.
const Builder = preload("res://game/characters/models/uniform_mesh_builder.gd")
const Police = preload("res://game/characters/models/police_model.gd")
const Guard = preload("res://game/characters/models/guard_model.gd")
# Historical foot_* names now identify civilian knee/lower-leg joints.
# Uniform models/variants retain their authored ankle rigs.
const CIVILIAN_KNEE_Y := 0.22
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
		var design := _design(drawing)
		var b := Builder.new()
		b.palette = _palette()
		for key: String in ["cloth", "accent", "skin", "trim"]:
			b.vertex_tints[key] = design[key]
		_bones(b, design)
		_body(b, design)
		_weight_coat_skirt(b, design)
		_limbs(b, design)
		_weight_lower_legs(b)
		_head(b, design)
		_accessories(b, design)
		_quantize_skin_weights(b)
		model = b.build_node("Citizen_" + drawing)
	_initialize_rest(model)
	model.set_meta("drawing", drawing)
	model.set_meta("forward_axis", "-Z")
	model.set_meta("design_status", "original authored geometry; visual and runtime acceptance required")
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
			mat.albedo_color = Color("eee6d6") if key == "eye" else Color("211f27") if key == "ink" else Color.WHITE
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.roughness = 1.0
			mat.metallic = 0.0
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY if key in ["skin", "ink"] else BaseMaterial3D.DIFFUSE_TOON
			_materials[key] = mat
	return _materials

func _design(drawing: String) -> Dictionary:
	var d := {"cloth": Color("445f75"), "accent": Color("a18d62"), "skin": Color("c69e80"), "trim": Color("ddd2b6"), "width": 0.19, "hem": 0.37, "shoulder": 0.72, "head_y": 0.84, "head_w": 0.098, "jaw": 0.079, "nose": 0.033, "hat": "knit", "face": "long", "glasses": false, "old": false, "apron": false, "bag": false, "backpack": false, "dog": false}
	match drawing:
		"ilyusha":
			d.merge({"width": 0.173, "hem": 0.35, "shoulder": 0.73, "head_w": 0.087, "jaw": 0.067, "nose": 0.042, "cloth": Color("3e5d73"), "accent": Color("bd834a"), "face": "angular"}, true)
		"babka":
			d.merge({"width": 0.235, "hem": 0.21, "shoulder": 0.69, "head_y": 0.835, "head_w": 0.1, "jaw": 0.084, "cloth": Color("675267"), "accent": Color("ba8c65"), "hat": "scarf", "old": true, "glasses": true, "face": "square"}, true)
		"vendor":
			d.merge({"width": 0.225, "hem": 0.28, "head_w": 0.108, "jaw": 0.101, "nose": 0.026, "cloth": Color("376864"), "accent": Color("b8a17c"), "hat": "hair", "apron": true, "face": "square"}, true)
		"officer":
			d.merge({"width": 0.185, "hem": 0.20, "head_w": 0.083, "jaw": 0.072, "hat": "cap", "old": true, "cloth": Color("716958"), "accent": Color("805458"), "bag": true}, true)
		_:
			var role := drawing.trim_prefix("resident_")
			match role:
				"babka": d.merge({"width": 0.218, "hem": 0.24, "old": true, "hat": "scarf", "cloth": Color("697971"), "accent": Color("bfaa78"), "bag": true}, true)
				"man": d.merge({"width": 0.23, "head_w": 0.11, "jaw": 0.105, "hat": "cap", "face": "square", "cloth": Color("766557"), "accent": Color("71918d")}, true)
				"woman": d.merge({"width": 0.195, "hem": 0.26, "hat": "scarf", "cloth": Color("7c684f"), "accent": Color("709295"), "glasses": true}, true)
				"boy": d.merge({"head_w": 0.112, "jaw": 0.095, "width": 0.19, "hem": 0.38, "cloth": Color("7a855d"), "accent": Color("a96c51"), "hat": "pom", "face": "round"}, true)
				"shuba": d.merge({"width": 0.265, "hem": 0.18, "shoulder": 0.68, "hat": "fur", "cloth": Color("7b6655"), "accent": Color("cfb184"), "old": true, "bag": true}, true)
				"beret": d.merge({"width": 0.205, "hem": 0.25, "hat": "beret", "cloth": Color("43676c"), "accent": Color("b28e71"), "old": true, "glasses": true}, true)
				"violet": d.merge({"width": 0.225, "hem": 0.2, "hat": "knit", "cloth": Color("65576e"), "accent": Color("a5b8aa"), "old": true, "face": "square"}, true)
				"ushanka", "ushanka_walk": d.merge({"width": 0.235, "hat": "fur", "head_w": 0.109, "jaw": 0.101, "cloth": Color("66797c"), "accent": Color("98715b"), "face": "square"}, true)
				"tourist": d.merge({"width": 0.2, "hat": "pom", "cloth": Color("a47c43"), "accent": Color("49746b"), "old": true, "backpack": true, "glasses": true}, true)
				"kid": d.merge({"head_w": 0.113, "jaw": 0.096, "width": 0.191, "cloth": Color("a15e51"), "accent": Color("c7b179"), "hat": "pom", "face": "round"}, true)
				"kid2": d.merge({"head_w": 0.106, "jaw": 0.083, "width": 0.176, "cloth": Color("5e798b"), "accent": Color("bfa15c"), "hat": "ear", "face": "angular"}, true)
				"dog": d.merge({"width": 0.214, "hem": 0.23, "cloth": Color("806c61"), "accent": Color("a7b5a1"), "hat": "beret", "old": true, "dog": true}, true)
				"kolpak": d.merge({"width": 0.194, "hem": 0.22, "cloth": Color("607c7b"), "accent": Color("c7a77c"), "hat": "pom", "old": true}, true)
				"bow": d.merge({"width": 0.24, "hem": 0.22, "cloth": Color("987856"), "accent": Color("638b90"), "hat": "scarf", "old": true, "bag": true, "face": "square"}, true)
				"turban": d.merge({"width": 0.208, "hem": 0.23, "cloth": Color("5d6d7e"), "accent": Color("af8765"), "hat": "wrap", "old": true, "glasses": true}, true)
	var is_child := drawing in ["resident_boy", "resident_kid", "resident_kid2"]
	d["morph"] = "young" if drawing == "ilyusha" else "elder" if d.old else "soft" if drawing in ["vendor", "resident_woman"] else "child" if is_child else "broad"
	return d

func _bones(b: Builder, d: Dictionary) -> void:
	var shoulder: float = d.shoulder
	var x: float = d.width + 0.022
	b.add_bone("root", -1, Vector3.ZERO)
	b.add_bone("hips", 0, Vector3(0, 0.36, 0))
	b.add_bone("spine", 1, Vector3(0, 0.54, 0))
	b.add_bone("head", 2, Vector3(0, d.head_y - 0.10, -0.005))
	for side: float in [1.0, -1.0]:
		var suffix := "_l" if side > 0 else "_r"
		var upper := b.add_bone("upper_arm" + suffix, 2, Vector3(side * x, shoulder, 0))
		var lower := b.add_bone("lower_arm" + suffix, upper, Vector3(side * (x + 0.022), 0.54, -0.005))
		b.add_bone("hand" + suffix, lower, Vector3(side * (x + 0.027), 0.385, -0.015))
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

func _body(b: Builder, d: Dictionary) -> void:
	var w: float = d.width
	var hem: float = d.hem
	var shoulder: float = d.shoulder
	b.body_profile([Vector3(w * 0.85, hem, 0.105), Vector3(w * 1.02, hem + 0.04, 0.13), Vector3(w, 0.46, 0.142), Vector3(w * 0.99, shoulder - 0.10, 0.133), Vector3(w * 1.05, shoulder - 0.052, 0.126), Vector3(w * 0.98, shoulder - 0.016, 0.112), Vector3(w * 0.68, shoulder + 0.014, 0.086)], "cloth", 2, 20)
	b.ellipsoid(Vector3(0, 0.35, 0), Vector3(0.15, 0.08, 0.104), "ink", 1, 14, 8)
	b.ellipsoid(Vector3(0, shoulder + 0.008, -0.006), Vector3(w * 0.64, 0.035, 0.097), "accent", 2, 16, 8)
	b.box(Vector3(0.045, shoulder - 0.065, -0.127), Vector3(0.045, 0.18, 0.016), "accent", 2, Basis(Vector3.FORWARD, -0.13))
	b.tube(PackedVector3Array([Vector3(0, hem + 0.018, -0.133), Vector3(0, 0.47, -0.146), Vector3(0, shoulder - 0.03, -0.129)]), 0.002, "ink", 2)
	if not d.apron:
		for side: float in [-1.0, 1.0]:
			b.box(Vector3(side * w * 0.62, maxf(hem + 0.09, 0.44), -0.113), Vector3(w * 0.46, 0.014, 0.018), "accent", 2, Basis(Vector3.UP, -side * 0.35))
	else:
		_apron_patch(b, [Vector2(0.115, 0.23), Vector2(0.122, 0.28), Vector2(0.125, 0.32), Vector2(0.125, 0.36), Vector2(0.122, 0.40), Vector2(0.12, 0.44), Vector2(0.118, 0.48), Vector2(0.115, 0.54), Vector2(0.11, 0.60), Vector2(0.107, 0.655)], "accent", 0.0)
		for side: float in [-1.0, 1.0]:
			_apron_patch(b, [Vector2(0.012, 0.645), Vector2(0.012, 0.68), Vector2(0.012, 0.73)], "accent", 0.0, side * 0.095)
		_apron_patch(b, [Vector2(0.073, 0.375), Vector2(0.075, 0.40), Vector2(0.075, 0.425), Vector2(0.073, 0.445)], "trim", 0.006)

func _apron_z(y: float) -> float:
	var profile: Array[Vector2] = [Vector2(0.23, -0.13), Vector2(0.28, -0.144), Vector2(0.34, -0.152), Vector2(0.46, -0.158), Vector2(0.52, -0.157), Vector2(0.60, -0.148), Vector2(0.655, -0.132), Vector2(0.68, -0.117), Vector2(0.73, -0.091)]
	for index in range(profile.size() - 1):
		if y <= profile[index + 1].x:
			return lerpf(profile[index].y, profile[index + 1].y, clampf((y - profile[index].x) / (profile[index + 1].x - profile[index].x), 0, 1))
	return profile[-1].y

func _apron_patch(b: Builder, rows: Array[Vector2], material: String, offset: float, center_x: float = 0.0) -> void:
	# Both bib and lap are one subdivided solid cloth panel, including the waist.
	# The pocket uses the same surface/weight profile, so it follows the folds.
	const THICKNESS := 0.008
	for index in range(rows.size() - 1):
		var low := rows[index]
		var high := rows[index + 1]
		var low_z := _apron_z(low.y) - offset
		var high_z := _apron_z(high.y) - offset
		var a := Vector3(center_x - low.x, low.y, low_z)
		var c := Vector3(center_x + low.x, low.y, low_z)
		var d := Vector3(center_x + high.x, high.y, high_z)
		var e := Vector3(center_x - high.x, high.y, high_z)
		var normal := Vector3(0, (high_z - low_z) / (high.y - low.y), -1).normalized()
		b._triangle(a, c, d, normal, normal, normal, material, 2)
		b._triangle(a, d, e, normal, normal, normal, material, 2)
		var back := Vector3(0, 0, THICKNESS)
		b._triangle(a + back, d + back, c + back, -normal, -normal, -normal, material, 2)
		b._triangle(a + back, e + back, d + back, -normal, -normal, -normal, material, 2)
		var slope := (high.x - low.x) / (high.y - low.y)
		for side: float in [-1.0, 1.0]:
			var bottom := a if side < 0 else c
			var top := e if side < 0 else d
			var side_normal := Vector3(side, -slope, 0).normalized()
			b._triangle(bottom, top, top + back, side_normal, side_normal, side_normal, material, 2)
			b._triangle(bottom, top + back, bottom + back, side_normal, side_normal, side_normal, material, 2)
	for index in [0, rows.size() - 1]:
		var row := rows[index]
		var z := _apron_z(row.y) - offset
		var a := Vector3(center_x - row.x, row.y, z)
		var c := Vector3(center_x + row.x, row.y, z)
		var normal := Vector3.DOWN if index == 0 else Vector3.UP
		var back := Vector3(0, 0, THICKNESS)
		b._triangle(a, c, c + back, normal, normal, normal, material, 2)
		b._triangle(a, c + back, a + back, normal, normal, normal, material, 2)

func _weight_coat_skirt(b: Builder, d: Dictionary) -> void:
	if d.hem >= 0.30: return
	# Only the front skirts follow the thighs. Rear cloth remains on the torso
	# around the pelvis; rotating it forward would uncover the back of the hips.
	for part: Dictionary in b._parts.values():
		var vertices: PackedVector3Array = part["positions"]
		var bones: PackedInt32Array = part["bones"]
		var weights: PackedFloat32Array = part["weights"]
		for index in vertices.size():
			if bones[index * 4] != 2 or vertices[index].y >= 0.44: continue
			var front_weight := 1.0 - smoothstep(-0.08, 0.025, vertices[index].z)
			var thigh_weight := clampf((0.44 - vertices[index].y) / 0.12, 0, 1) * front_weight
			var left_weight := smoothstep(-0.045, 0.045, vertices[index].x)
			bones[index * 4 + 1] = 10
			bones[index * 4 + 2] = 12
			weights[index * 4] = 1.0 - thigh_weight
			weights[index * 4 + 1] = thigh_weight * left_weight
			weights[index * 4 + 2] = thigh_weight * (1.0 - left_weight)
		part["bones"] = bones
		part["weights"] = weights

func _limbs(b: Builder, d: Dictionary) -> void:
	var x: float = d.width + 0.022
	var shoulder: float = d.shoulder
	for side: float in [1.0, -1.0]:
		var upper := 4 if side > 0 else 7
		var lower := upper + 1
		var hand := upper + 2
		var leg := 10 if side > 0 else 12
		var foot := leg + 1
		_sleeve(b, d, side, upper, lower)
		b.ellipsoid(Vector3(side * (x + 0.025), 0.391, -0.014), Vector3(0.047, 0.012, 0.053), "accent", lower, 12, 6)
		b.ellipsoid(Vector3(side * (x + 0.027), 0.351, -0.023), Vector3(0.045, 0.05, 0.041), "skin", hand, 12, 8)
		b.ellipsoid(Vector3(side * (x - 0.008), 0.366, -0.045), Vector3(0.019, 0.027, 0.021), "skin", hand, 10, 6)
		b.ellipsoid(Vector3(side * 0.092, 0.224, 0.008), Vector3(0.064, 0.151, 0.075), "ink", leg, 12, 8)
		b.ellipsoid(Vector3(side * 0.092, 0.077, 0), Vector3(0.058, 0.069, 0.064), "ink", foot, 12, 8)
		b.ellipsoid(Vector3(side * 0.092, 0.035, -0.044), Vector3(0.065, 0.033, 0.091), "ink", foot, 12, 8)
		b.box(Vector3(side * 0.092, 0.009, -0.036), Vector3(0.128, 0.018, 0.166), "ink", foot)
		b.box(Vector3(side * 0.092, 0.019, -0.039), Vector3(0.13, 0.009, 0.17), "trim", foot)

func _sleeve(b: Builder, d: Dictionary, side: float, upper: int, lower: int) -> void:
	var x: float = d.width + 0.022
	var shoulder: float = d.shoulder
	# A single cloth envelope runs from the shoulder inside the coat to the cuff.
	# There is no separate shoulder ball or oval forearm to expose a toy joint.
	var levels: Array[Vector4] = [Vector4(x + 0.025, 0.385, 0.045, 0.051), Vector4(x + 0.025, 0.432, 0.050, 0.059), Vector4(x + 0.02, 0.535, 0.054, 0.064), Vector4(x + 0.006, 0.615, 0.061, 0.072), Vector4(x - 0.02, shoulder - 0.032, 0.068, 0.076), Vector4(x - 0.045, shoulder - 0.005, 0.045, 0.057)]
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
			var elbow_weight := clampf((0.575 - vertices[index].y) / 0.08, 0, 1)
			bones[index * 4 + 1] = lower
			weights[index * 4] = 1.0 - elbow_weight
			weights[index * 4 + 1] = elbow_weight
		part["bones"] = bones
		part["weights"] = weights

func _morph_levels(d: Dictionary) -> Array[Vector3]:
	var y: float = d.head_y
	var w: float = d.head_w
	match d.morph:
		"young":
			return [Vector3(w * 0.39, y - 0.109, 0.031), Vector3(w * 0.64, y - 0.088, 0.050), Vector3(w * 0.84, y - 0.048, 0.066), Vector3(w, y - 0.005, 0.076), Vector3(w * 0.92, y + 0.035, 0.073), Vector3(w * 0.86, y + 0.076, 0.065), Vector3(w * 0.46, y + 0.095, 0.037)]
		"elder":
			return [Vector3(w * 0.39, y - 0.126, 0.039), Vector3(w * 0.82, y - 0.114, 0.065), Vector3(w * 1.10, y - 0.087, 0.085), Vector3(w * 1.15, y - 0.047, 0.091), Vector3(w * 1.04, y - 0.009, 0.089), Vector3(w * 0.86, y + 0.034, 0.073), Vector3(w * 0.83, y + 0.074, 0.065), Vector3(w * 0.50, y + 0.095, 0.04)]
		"soft":
			return [Vector3(w * 0.32, y - 0.109, 0.031), Vector3(w * 0.61, y - 0.091, 0.051), Vector3(w * 0.88, y - 0.057, 0.073), Vector3(w * 1.07, y - 0.018, 0.086), Vector3(w * 1.04, y + 0.018, 0.084), Vector3(w * 0.91, y + 0.064, 0.069), Vector3(w * 0.55, y + 0.093, 0.04)]
		"child":
			return [Vector3(w * 0.46, y - 0.101, 0.036), Vector3(w * 0.80, y - 0.078, 0.063), Vector3(w * 1.02, y - 0.025, 0.084), Vector3(w, y + 0.034, 0.082), Vector3(w * 0.85, y + 0.078, 0.062), Vector3(w * 0.46, y + 0.095, 0.035)]
		_:
			return [Vector3(d.jaw * 0.55, y - 0.105, 0.044), Vector3(d.jaw, y - 0.087, 0.066), Vector3(w, y - 0.04, 0.077), Vector3(w, y + 0.025, 0.077), Vector3(w * 0.86, y + 0.075, 0.065), Vector3(w * 0.52, y + 0.092, 0.04)]

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

func _head(b: Builder, d: Dictionary) -> void:
	var y: float = d.head_y
	var w: float = d.head_w
	var young: bool = d.morph == "young"
	var elder: bool = d.morph == "elder"
	var soft: bool = d.morph == "soft"
	var child: bool = d.morph == "child"
	var exponent := 0.78 if young else 0.9 if elder else 1.0 if soft or child else 0.65
	var levels := _morph_levels(d)
	b.ellipsoid(Vector3(0, y - 0.107, 0), Vector3(0.051, 0.036, 0.05), "skin", 3, 12, 6)
	_head_cage(b, levels, exponent)
	for side: float in [-1.0, 1.0]:
		b.ellipsoid(Vector3(side * (w + 0.005), y + 0.005, 0.0), Vector3(0.015, 0.025 if not elder else 0.030, 0.016), "skin", 3, 10, 6)
		var eye_x: float = side * w * (0.43 if not soft else 0.45)
		var eye_y: float = y + (0.019 if not elder else 0.022) + (0.003 if young and side < 0 else 0.0)
		var eye_w := 0.019 if young else 0.018 if elder else 0.023 if soft else 0.021
		var eye_h := 0.008 if young else 0.0055 if elder else 0.0115 if soft or child else 0.008
		var eye_z := _face_z(levels, exponent, eye_x, eye_y) - 0.0035
		b.ellipsoid(Vector3(eye_x, eye_y, eye_z), Vector3(eye_w, eye_h, 0.006), "eye", 3, 12, 6)
		b.ellipsoid(Vector3(eye_x + (0.002 if young else -0.001), eye_y, eye_z - 0.006), Vector3(0.0034 if elder else 0.004, eye_h * 0.70, 0.0025), "ink", 3, 8, 4)
		var brow_y := eye_y + (0.017 if young else 0.014 if soft else 0.011)
		var brow_peak := 0.010 if young and side < 0 else 0.002 if young else 0.004 if soft else 0.001
		_face_line(b, levels, exponent, PackedVector3Array([Vector3(eye_x - eye_w, brow_y, 0), Vector3(eye_x, brow_y + brow_peak, 0), Vector3(eye_x + eye_w, brow_y - (0.004 if young and side > 0 else 0.0), 0)]), 0.0017 if soft or elder else 0.0026)
		# Upper and lower lids belong to the face volume, not floating eye decals.
		_face_line(b, levels, exponent, PackedVector3Array([Vector3(eye_x - eye_w, eye_y + eye_h * 0.7, 0), Vector3(eye_x, eye_y + eye_h * 0.75, 0), Vector3(eye_x + eye_w, eye_y + eye_h * 0.5, 0)]), 0.0027 if elder else 0.0016, "skin", 0.008)
		if elder:
			_face_line(b, levels, exponent, PackedVector3Array([Vector3(eye_x - 0.019, eye_y - 0.009, 0), Vector3(eye_x + 0.003, eye_y - 0.015, 0), Vector3(eye_x + 0.020, eye_y - 0.008, 0)]), 0.0013)
			for crease in 2:
				_face_line(b, levels, exponent, PackedVector3Array([Vector3(eye_x + side * 0.021, eye_y - 0.002 - crease * 0.005, 0), Vector3(eye_x + side * 0.034, eye_y - 0.006 - crease * 0.009, 0)]), 0.0010)
		if d.glasses:
			var ring := PackedVector3Array()
			for i in 13:
				var angle := TAU * float(i) / 12.0
				ring.append(Vector3(eye_x + cos(angle) * 0.027, eye_y + sin(angle) * 0.018, eye_z - 0.012))
			b.tube(ring, 0.0020, "ink", 3, 5)
			b.tube(PackedVector3Array([Vector3(eye_x + side * 0.026, eye_y, eye_z - 0.012), Vector3(side * w, y + 0.01, -0.01)]), 0.0020, "ink", 3, 5)
	var bridge_x := -0.004 if young else 0.0
	var nose_y := y - (0.008 if young else 0.011 if elder else 0.004)
	var nose_z := _face_z(levels, exponent, bridge_x, nose_y) - 0.004
	b.ellipsoid(Vector3(bridge_x, nose_y, nose_z), Vector3(0.009 if young else 0.013 if elder else 0.011, 0.025 if young or elder else 0.017, 0.024 if young else 0.022 if elder else 0.018), "skin", 3, 12, 8)
	b.ellipsoid(Vector3(bridge_x + (0.003 if young else 0), nose_y - 0.018, nose_z - (0.014 if young else 0.011)), Vector3(0.010 if young else 0.018 if elder else 0.015, 0.008 if young else 0.012, 0.012), "skin", 3, 12, 6)
	if elder:
		for side: float in [-1.0, 1.0]:
			_face_line(b, levels, exponent, PackedVector3Array([Vector3(side * 0.022, y - 0.020, 0), Vector3(side * 0.036, y - 0.042, 0), Vector3(side * 0.041, y - 0.074, 0)]), 0.0016)
		_face_line(b, levels, exponent, PackedVector3Array([Vector3(-0.031, y - 0.079, 0), Vector3(-0.014, y - 0.069, 0), Vector3(0.009, y - 0.070, 0), Vector3(0.029, y - 0.081, 0)]), 0.0020)
		_face_line(b, levels, exponent, PackedVector3Array([Vector3(-0.027, y - 0.097, 0), Vector3(0, y - 0.103, 0), Vector3(0.029, y - 0.096, 0)]), 0.0012)
		for forehead_y in [y + 0.061, y + 0.075]:
			_face_line(b, levels, exponent, PackedVector3Array([Vector3(-0.037, forehead_y, 0), Vector3(0, forehead_y + 0.003, 0), Vector3(0.034, forehead_y - 0.001, 0)]), 0.0009)
	else:
		var mouth_y := y - (0.061 if young else 0.059 if soft else 0.054)
		var mouth_w := 0.024 if young else 0.033 if soft else 0.026
		_face_line(b, levels, exponent, PackedVector3Array([Vector3(-mouth_w, mouth_y + (0.002 if young else 0.006 if soft else 0), 0), Vector3(-0.002, mouth_y, 0), Vector3(mouth_w, mouth_y + (0.008 if young else 0.003 if soft else -0.002), 0)]), 0.0017)
		if soft:
			_face_line(b, levels, exponent, PackedVector3Array([Vector3(-0.014, mouth_y - 0.006, 0), Vector3(0.004, mouth_y - 0.008, 0), Vector3(0.017, mouth_y - 0.005, 0)]), 0.0014, "skin", 0.0025)
	if d.glasses:
		var bridge_z := _face_z(levels, exponent, 0, y + 0.022) - 0.017
		b.tube(PackedVector3Array([Vector3(-w * 0.43 + 0.025, y + 0.022, bridge_z), Vector3(0, y + 0.026, bridge_z - 0.002), Vector3(w * 0.43 - 0.025, y + 0.022, bridge_z)]), 0.0018, "ink", 3, 5)
	_hat(b, d)

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

func _hat(b: Builder, d: Dictionary) -> void:
	var w: float = d.head_w
	var y: float = d.head_y
	var hat: String = d.hat
	if hat == "hair":
		b.ellipsoid(Vector3(0, 0.942, 0.002), Vector3(w * 1.06, 0.058, 0.079), "ink", 3, 16, 8)
		b.ellipsoid(Vector3(0, y + 0.032, 0.049), Vector3(w * 1.05, 0.077, 0.045), "ink", 3, 16, 8)
		for side: float in [-1.0, 1.0]:
			b.ellipsoid(Vector3(side * w * 0.95, y + 0.032, 0.018), Vector3(0.025, 0.075, 0.057), "ink", 3, 12, 8)
		b.tube(PackedVector3Array([Vector3(-w * 0.70, y + 0.088, -0.054), Vector3(-w * 0.28, y + 0.085, -0.071), Vector3(w * 0.25, y + 0.068, -0.078), Vector3(w * 0.68, y + 0.040, -0.061)]), 0.012, "ink", 3, 8)
		return
	var hat_color := "accent"
	b.ellipsoid(Vector3(-0.008 if hat == "beret" else 0.0, 0.95, 0.003), Vector3(w * (1.3 if hat == "beret" else 1.11), 0.05, 0.088), hat_color, 3, 16, 8)
	b.ellipsoid(Vector3(0, 0.923, -0.003), Vector3(w * 1.12, 0.019, 0.088), "trim", 3, 16, 6)
	if hat in ["scarf", "wrap"]:
		for side: float in [-1.0, 1.0]:
			b.ellipsoid(Vector3(side * w * 0.85, y - 0.007, 0.026), Vector3(0.035, 0.08, 0.054), "accent", 3, 12, 8)
		b.ellipsoid(Vector3(0.018, y - 0.096, -0.057), Vector3(0.034, 0.024, 0.029), "accent", 3, 12, 6)
	if hat in ["fur", "ear"]:
		for side: float in [-1.0, 1.0]:
			b.ellipsoid(Vector3(side * w * 1.03, y + 0.022, 0.006), Vector3(0.026, 0.063, 0.062), "trim", 3, 12, 8)
	if hat == "cap":
		b.box(Vector3(0, 0.932, -0.075), Vector3(w * 1.95, 0.015, 0.1), "ink", 3, Basis(Vector3.RIGHT, -0.12))
	if hat == "pom":
		# The crown itself reaches 1.0; the pom stays inside that normalized cap.
		b.ellipsoid(Vector3(0.024, 0.981, 0), Vector3(0.023, 0.019, 0.024), "trim", 3, 10, 6)
	if hat in ["knit", "pom", "ear", "wrap"]:
		for i in range(-3, 4):
			var x := float(i) * w * 0.23
			b.tube(PackedVector3Array([Vector3(x, 0.928, -0.087), Vector3(x * 0.84, 0.956, -0.083), Vector3(x * 0.60, 0.976, -0.065)]), 0.0014, "trim", 3, 5)

func _accessories(b: Builder, d: Dictionary) -> void:
	if d.bag:
		var x: float = d.width + 0.035
		b.box(Vector3(x, 0.22, -0.022), Vector3(0.11, 0.14, 0.074), "accent", 6, Basis(Vector3.FORWARD, -0.09))
		b.tube(PackedVector3Array([Vector3(x - 0.03, 0.29, -0.022), Vector3(x - 0.02, 0.346, -0.022), Vector3(x + 0.023, 0.346, -0.022), Vector3(x + 0.033, 0.29, -0.022)]), 0.004, "ink", 6)
	if d.backpack:
		b.ellipsoid(Vector3(0, 0.57, 0.18), Vector3(0.139, 0.15, 0.062), "accent", 2, 16, 8)
		for side: float in [-1.0, 1.0]:
			b.tube(PackedVector3Array([Vector3(side * 0.12, 0.45, 0.11), Vector3(side * 0.15, 0.65, -0.088), Vector3(side * 0.13, 0.745, 0.02), Vector3(side * 0.11, 0.66, 0.20)]), 0.014, "accent", 2, 6)
	if d.dog:
		# A wool tote carries the small companion: no fixed-ground geometry follows gait.
		var x: float = d.width + 0.04
		b.ellipsoid(Vector3(x, 0.25, -0.024), Vector3(0.09, 0.082, 0.054), "accent", 6, 12, 8)
		b.ellipsoid(Vector3(x + 0.006, 0.33, -0.043), Vector3(0.044, 0.04, 0.037), "trim", 6, 12, 8)
		for side: float in [-1.0, 1.0]:
			b.ellipsoid(Vector3(x + side * 0.039, 0.34, -0.031), Vector3(0.017, 0.034, 0.019), "ink", 6, 10, 6)
			b.ellipsoid(Vector3(x + side * 0.017, 0.337, -0.078), Vector3(0.004, 0.005, 0.003), "ink", 6, 8, 4)
		b.ellipsoid(Vector3(x, 0.318, -0.084), Vector3(0.009, 0.006, 0.007), "ink", 6, 8, 4)

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
