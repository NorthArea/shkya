extends RefCounted
## IP-01: current approved guard, sculpted as a skinned mesh.
## Coordinates: soles 0, beret 1; face looks along -Z.

const MeshBuilder = preload("res://game/characters/models/uniform_mesh_builder.gd")

static var _cached_model: PackedScene


func build_model() -> Node3D:
	if _cached_model != null:
		return _cached_model.instantiate() as Node3D
	var mesh = MeshBuilder.new()
	mesh.palette = {
		"suit": _material("Winter slate cloth", Color("4a4e5c")),
		"armour": _material("Charcoal padded armour", Color("36363d")),
		"ink": _material("Boots gloves and facial hair", Color("141213")),
		"skin": _material("Ochre skin", Color("f0d594")),
		"beret": _material("Maroon wool", Color("6a1c26")),
		"eye": _material("Warm eye white", Color("f6f0da")),
	}
	mesh.palette["skin"].diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	mesh.vertex_tints["armour"] = Color("999999")
	_add_skeleton(mesh)
	_add_body(mesh)
	_add_legs(mesh)
	_add_arms(mesh)
	_add_armour(mesh)
	_add_head(mesh)
	var model: Node3D = mesh.build_node("GuardModel")
	_tilt_beret(model)
	model.set_meta("approved_design", "guard_front_idle.svg / guard_side_idle.svg; e03 third figure")
	model.set_meta("forward_axis", "-Z")
	_set_descendant_owners(model, model)
	var packed := PackedScene.new()
	if packed.pack(model) != OK:
		push_error("Could not pack GuardModel for shared visual resources")
		return model
	_cached_model = packed
	return model


func _tilt_beret(model: Node3D) -> void:
	# Rotate the single wool volume, not a hard brim or two intersecting lobes.
	var instance: MeshInstance3D = model.get_node("Skeleton3D/UniformMesh")
	var original: ArrayMesh = instance.mesh as ArrayMesh
	var sculpted := ArrayMesh.new()
	sculpted.resource_name = original.resource_name
	var pivot := Vector3(-0.010, 0.961, -0.025)
	var tilt := Basis(Vector3.BACK, -0.20)
	for surface in range(original.get_surface_count()):
		var arrays: Array = original.surface_get_arrays(surface)
		if original.surface_get_name(surface) == "beret":
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var highest: float = -INF
			for index in range(vertices.size()):
				vertices[index] = pivot + tilt * (vertices[index] - pivot)
				normals[index] = (tilt * normals[index]).normalized()
				highest = maxf(highest, vertices[index].y)
			for index in range(vertices.size()):
				vertices[index].y += 1.0 - highest
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
		sculpted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		sculpted.surface_set_name(surface, original.surface_get_name(surface))
		sculpted.surface_set_material(surface, original.surface_get_material(surface))
	instance.mesh = sculpted


func _set_descendant_owners(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		_set_descendant_owners(child, root)


func _material(label: String, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = label
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


func _add_skeleton(mesh) -> void:
	mesh.add_bone("root", -1, Vector3.ZERO)
	mesh.add_bone("hips", 0, Vector3(0, 0.39, 0))
	mesh.add_bone("spine", 1, Vector3(0, 0.61, 0))
	mesh.add_bone("head", 2, Vector3(0, 0.821, -0.02))
	mesh.add_bone("upper_arm_l", 2, Vector3(0.235, 0.775, 0))
	mesh.add_bone("lower_arm_l", 4, Vector3(0.326, 0.535, 0))
	mesh.add_bone("hand_l", 5, Vector3(0.326, 0.355, -0.005))
	mesh.add_bone("upper_arm_r", 2, Vector3(-0.235, 0.775, 0))
	mesh.add_bone("lower_arm_r", 7, Vector3(-0.326, 0.535, 0))
	mesh.add_bone("hand_r", 8, Vector3(-0.326, 0.355, -0.005))
	mesh.add_bone("leg_l", 1, Vector3(0.126, 0.327, 0))
	mesh.add_bone("foot_l", 10, Vector3(0.126, 0.10, 0))
	mesh.add_bone("leg_r", 1, Vector3(-0.126, 0.327, 0))
	mesh.add_bone("foot_r", 12, Vector3(-0.126, 0.10, 0))


func _add_body(mesh) -> void:
	var torso_levels: Array[Vector3] = [
		Vector3(0.223, 0.355, 0.128),
		Vector3(0.267, 0.402, 0.177),
		Vector3(0.278, 0.515, 0.198),
		Vector3(0.271, 0.650, 0.191),
		Vector3(0.246, 0.759, 0.154),
		Vector3(0.187, 0.829, 0.118),
		Vector3(0.106, 0.864, 0.082),
	]
	mesh.body_profile(torso_levels, "suit", 2, 24)
	var hip_levels: Array[Vector3] = [
		Vector3(0.180, 0.256, 0.133),
		Vector3(0.248, 0.312, 0.168),
		Vector3(0.271, 0.385, 0.183),
		Vector3(0.250, 0.435, 0.171),
	]
	mesh.body_profile(hip_levels, "suit", 1, 24)
	# A broad folded cloth band sits below the jaw, rather than a round hose.
	var collar_line := PackedVector3Array([
		Vector3(-0.137, 0.836, 0.005), Vector3(-0.154, 0.818, -0.050),
		Vector3(-0.169, 0.795, -0.115), Vector3(-0.150, 0.763, -0.166),
		Vector3(-0.092, 0.738, -0.185), Vector3(0, 0.731, -0.190),
		Vector3(0.092, 0.738, -0.185), Vector3(0.150, 0.763, -0.166),
		Vector3(0.169, 0.795, -0.115), Vector3(0.154, 0.818, -0.050),
		Vector3(0.137, 0.836, 0.005),
	])
	_padded_ribbon(mesh, collar_line, 0.058, 0.018, "suit", true)
	var rear_collar := PackedVector3Array([
		Vector3(-0.137, 0.836, 0.005), Vector3(-0.154, 0.810, 0.080),
		Vector3(-0.143, 0.782, 0.147), Vector3(-0.088, 0.764, 0.176),
		Vector3(0, 0.755, 0.184), Vector3(0.088, 0.764, 0.176),
		Vector3(0.143, 0.782, 0.147), Vector3(0.154, 0.810, 0.080),
		Vector3(0.137, 0.836, 0.005),
	])
	_padded_ribbon(mesh, rear_collar, 0.043, 0.018, "suit", true)
	mesh.ellipsoid(Vector3(0.003, 0.732, -0.202), Vector3(0.009, 0.008, 0.003), "ink", 2, 10, 6)
	mesh.ellipsoid(Vector3(0.003, 0.732, -0.205), Vector3(0.005, 0.0045, 0.0015), "suit", 2, 8, 5)



func _add_legs(mesh) -> void:
	for sign_value in [-1.0, 1.0]:
		var leg: int = 10 if sign_value > 0 else 12
		var foot: int = leg + 1
		var x: float = sign_value * 0.126
		_cloth_mass(mesh, Vector3(x, 0.233, 0.007), Vector3(0.121, 0.146, 0.142), "suit", leg, 16, 10)
		_cloth_mass(mesh, Vector3(x, 0.123, 0), Vector3(0.075, 0.031, 0.087), "suit", leg, 12, 6)
		# Small cargo pockets sit on the outside-front of the baggy thighs.
		_bevel_box(mesh, Vector3(x + sign_value * 0.069, 0.246, -0.100), Vector3(0.072, 0.078, 0.030), "armour", leg,
			Basis(Vector3.FORWARD, -sign_value * 0.10))
		_bevel_box(mesh, Vector3(x + sign_value * 0.069, 0.277, -0.119), Vector3(0.072, 0.012, 0.012), "suit", leg)
		_cloth_mass(mesh, Vector3(x, 0.064, 0.006), Vector3(0.052, 0.055, 0.060), "ink", foot, 12, 8)
		_cloth_mass(mesh, Vector3(x, 0.035, -0.038), Vector3(0.060, 0.035, 0.086), "ink", foot, 14, 8)
		_bevel_box(mesh, Vector3(x, 0.009, -0.032), Vector3(0.116, 0.018, 0.165), "ink", foot)
		for y in [0.058, 0.070, 0.082]:
			mesh.tube(PackedVector3Array([
				Vector3(x - 0.022, y, -0.052), Vector3(x + 0.022, y + 0.002, -0.052),
			]), 0.0015, "armour", foot, 5)
		mesh.tube(PackedVector3Array([
			Vector3(x - 0.045, 0.123, -0.060), Vector3(x, 0.114, -0.083), Vector3(x + 0.045, 0.123, -0.060),
		]), 0.002, "armour", leg, 6)


func _add_arms(mesh) -> void:
	for sign_value in [-1.0, 1.0]:
		var upper: int = 4 if sign_value > 0 else 7
		var lower: int = upper + 1
		var hand: int = upper + 2
		_cloth_mass(mesh, Vector3(sign_value * 0.215, 0.744, 0.005), Vector3(0.119, 0.118, 0.119), "suit", upper, 16, 10)
		_cloth_mass(mesh, Vector3(sign_value * 0.276, 0.644, -0.003), Vector3(0.103, 0.166, 0.116), "suit", upper, 16, 10)
		_cloth_mass(mesh, Vector3(sign_value * 0.326, 0.472, -0.006), Vector3(0.083, 0.139, 0.102), "suit", lower, 16, 10)
		_cloth_mass(mesh, Vector3(sign_value * 0.326, 0.365, -0.009), Vector3(0.067, 0.029, 0.077), "armour", lower, 12, 6)
		mesh.ellipsoid(Vector3(sign_value * 0.326, 0.312, -0.014), Vector3(0.057, 0.063, 0.061), "ink", hand, 14, 8)
		mesh.ellipsoid(Vector3(sign_value * 0.284, 0.322, -0.043), Vector3(0.019, 0.033, 0.025), "ink", hand, 10, 6)
		mesh.vertex_tints["suit"] = Color("b9bcc6")
		_bevel_box(mesh, Vector3(sign_value * 0.328, 0.679, -0.093), Vector3(0.054, 0.054, 0.024), "suit", upper,
			Basis(Vector3.FORWARD, -sign_value * 0.25))
		mesh.vertex_tints["suit"] = Color.WHITE
		# Cloth folds and mitten fingers are solid strokes, never image planes.
		for y in [0.459, 0.518]:
			mesh.tube(PackedVector3Array([
				Vector3(sign_value * 0.278, y + 0.006, -0.078),
				Vector3(sign_value * 0.327, y, -0.107),
				Vector3(sign_value * 0.371, y + 0.008, -0.076),
			]), 0.002, "armour", lower, 6)
		for y in [0.285, 0.299, 0.313]:
			mesh.tube(PackedVector3Array([
				Vector3(sign_value * 0.300, y, -0.064),
				Vector3(sign_value * 0.325, y - 0.003, -0.076),
				Vector3(sign_value * 0.351, y, -0.064),
			]), 0.0016, "armour", hand, 5)


func _add_armour(mesh) -> void:
	# Soft side rolls round the carrier into the torso rather than exposing box sides.
	_bevel_box(mesh, Vector3(0, 0.560, -0.182), Vector3(0.340, 0.262, 0.058), "armour", 2)
	_bevel_box(mesh, Vector3(0, 0.579, 0.163), Vector3(0.355, 0.277, 0.061), "armour", 2)
	for sign_value in [-1.0, 1.0]:
		mesh.ellipsoid(Vector3(sign_value * 0.170, 0.560, -0.182), Vector3(0.022, 0.140, 0.033), "armour", 2, 12, 8)
	for y in [0.468, 0.548, 0.628]:
		mesh.vertex_tints["armour"] = Color("dadada")
		_bevel_box(mesh, Vector3(0, y, -0.222), Vector3(0.305, 0.073, 0.026), "armour", 2)
		for x in [-0.151, 0.151]:
			mesh.ellipsoid(Vector3(x, y, -0.222), Vector3(0.013, 0.0365, 0.014), "armour", 2, 10, 6)
		mesh.vertex_tints["armour"] = Color("999999")
		for x in [-0.055, 0.055]:
			mesh.tube(PackedVector3Array([
				Vector3(x, y - 0.032, -0.236), Vector3(x, y + 0.032, -0.236),
			]), 0.0012, "armour", 2, 5)
		mesh.vertex_tints["armour"] = Color("dadada")
		_bevel_box(mesh, Vector3(0, y, 0.204), Vector3(0.324, 0.072, 0.024), "armour", 2)
		mesh.vertex_tints["armour"] = Color("999999")
	for sign_value in [-1.0, 1.0]:
		mesh.ellipsoid(Vector3(sign_value * 0.202, 0.492, -0.148), Vector3(0.037, 0.070, 0.036), "armour", 2, 12, 8)
		_bevel_box(mesh, Vector3(sign_value * 0.202, 0.526, -0.179), Vector3(0.060, 0.024, 0.012), "armour", 2)
		mesh.ellipsoid(Vector3(sign_value * 0.202, 0.512, -0.186), Vector3(0.004, 0.004, 0.002), "ink", 2, 8, 6)
		# Flat padded webbing wraps over the shoulder and meets both carrier faces.
		var strap := PackedVector3Array([
			Vector3(sign_value * 0.166, 0.697, 0.174), Vector3(sign_value * 0.170, 0.786, 0.129),
			Vector3(sign_value * 0.172, 0.850, 0.044), Vector3(sign_value * 0.173, 0.851, -0.029),
			Vector3(sign_value * 0.173, 0.817, -0.105), Vector3(sign_value * 0.167, 0.756, -0.161),
			Vector3(sign_value * 0.159, 0.690, -0.190),
		])
		_padded_ribbon(mesh, strap, 0.063, 0.018, "armour")



func _add_head(mesh) -> void:
	var head_levels: Array[Vector3] = [
		Vector3(0.060, 0.759, 0.108), Vector3(0.112, 0.770, 0.132),
		Vector3(0.145, 0.790, 0.140), Vector3(0.153, 0.821, 0.140),
		Vector3(0.143, 0.852, 0.133), Vector3(0.115, 0.885, 0.119),
		Vector3(0.100, 0.913, 0.098), Vector3(0.088, 0.932, 0.073),
		Vector3(0.054, 0.944, 0.042),
	]
	_head_volume(mesh, head_levels)
	for sign_value in [-1.0, 1.0]:
		mesh.ellipsoid(Vector3(sign_value * 0.111, 0.895, -0.005), Vector3(0.014, 0.020, 0.020), "skin", 3, 12, 8)
		mesh.vertex_tints["skin"] = Color("b99576")
		mesh.ellipsoid(Vector3(sign_value * 0.122, 0.895, -0.007), Vector3(0.003, 0.011, 0.010), "skin", 3, 10, 6)
		mesh.vertex_tints["skin"] = Color.WHITE
		mesh.tube(PackedVector3Array([
			Vector3(sign_value * 0.122, 0.904, -0.018), Vector3(sign_value * 0.128, 0.895, -0.018),
			Vector3(sign_value * 0.122, 0.886, -0.018),
		]), 0.0017, "skin", 3, 6)
	for sign_value in [-1.0, 1.0]:
		var x: float = sign_value * 0.023
		_bevel_box(mesh, Vector3(sign_value * 0.024, 0.900, -0.150), Vector3(0.026, 0.006, 0.008), "ink", 3, Basis(Vector3.FORWARD, sign_value * 0.25))
		mesh.ellipsoid(Vector3(x, 0.888, -0.150), Vector3(0.011, 0.0042, 0.0045), "eye", 3, 12, 6)
		_bevel_box(mesh, Vector3(x, 0.894, -0.149), Vector3(0.025, 0.008, 0.012), "skin", 3)
		mesh.ellipsoid(Vector3(x, 0.882, -0.148), Vector3(0.013, 0.003, 0.006), "skin", 3, 10, 6)
		mesh.ellipsoid(Vector3(x - sign_value * 0.002, 0.888, -0.154), Vector3(0.0023, 0.0024, 0.0017), "ink", 3, 8, 4)
		mesh.tube(PackedVector3Array([
			Vector3(x - 0.012, 0.891, -0.152), Vector3(x, 0.890, -0.155), Vector3(x + 0.012, 0.891, -0.152),
		]), 0.0018, "ink", 3, 6)
		mesh.tube(PackedVector3Array([
			Vector3(sign_value * 0.011, 0.895, -0.154),
			Vector3(sign_value * 0.024, 0.901, -0.150),
			Vector3(sign_value * 0.036, 0.902, -0.146),
		]), 0.003, "ink", 3, 7)
		mesh.tube(PackedVector3Array([
			Vector3(sign_value * 0.016, 0.879, -0.153), Vector3(sign_value * 0.025, 0.877, -0.152),
			Vector3(sign_value * 0.032, 0.879, -0.150),
		]), 0.0011, "skin", 3, 6)
	_bevel_box(mesh, Vector3(0, 0.879, -0.151), Vector3(0.019, 0.024, 0.023), "skin", 3)
	mesh.ellipsoid(Vector3(0, 0.870, -0.153), Vector3(0.014, 0.014, 0.020), "skin", 3, 16, 10)
	for x in [-0.008, 0.008]:
		mesh.ellipsoid(Vector3(x, 0.861, -0.165), Vector3(0.0024, 0.0016, 0.002), "armour", 3, 8, 6)
	# A short, dense brush moustache, with a scalloped bottom edge.
	for x in [-0.020, -0.012, -0.004, 0.004, 0.012, 0.020]:
		mesh.ellipsoid(Vector3(x, 0.854 - absf(x) * 0.04, -0.160), Vector3(0.0052, 0.0055, 0.005), "ink", 3, 6, 4)
	mesh.ellipsoid(Vector3(0, 0.841, -0.167), Vector3(0.024, 0.010, 0.007), "ink", 3, 14, 8)
	mesh.vertex_tints["skin"] = Color("a46555")
	mesh.ellipsoid(Vector3(0, 0.836, -0.173), Vector3(0.015, 0.0024, 0.002), "skin", 3, 10, 4)
	mesh.vertex_tints["skin"] = Color.WHITE
	for sign_value in [-1.0, 1.0]:
		_head_stroke(mesh, head_levels, PackedVector3Array([
			Vector3(sign_value * 0.027, 0.859, 0), Vector3(sign_value * 0.034, 0.840, 0),
			Vector3(sign_value * 0.036, 0.824, 0),
		]), 0.0015)
		_head_stroke(mesh, head_levels, PackedVector3Array([
			Vector3(sign_value * 0.065, 0.801, 0), Vector3(sign_value * 0.080, 0.796, 0),
			Vector3(sign_value * 0.097, 0.795, 0), Vector3(sign_value * 0.113, 0.798, 0),
			Vector3(sign_value * 0.126, 0.804, 0),
		]), 0.0015)
	_head_stroke(mesh, head_levels, PackedVector3Array([
		Vector3(-0.020, 0.794, 0), Vector3(-0.010, 0.790, 0), Vector3(0, 0.789, 0),
		Vector3(0.010, 0.790, 0), Vector3(0.020, 0.794, 0),
	]), 0.0015)
	# A single soft wool volume is tilted after mesh construction.
	mesh.ellipsoid(Vector3(-0.010, 0.961, -0.025), Vector3(0.112, 0.033, 0.080), "beret", 3, 24, 12)


func _padded_ribbon(mesh, line: PackedVector3Array, width: float, thickness: float, material: String, collar: bool = false) -> void:
	var section := [Vector2(-0.5, -0.3), Vector2(-0.3, -0.5), Vector2(0.3, -0.5), Vector2(0.5, -0.3), Vector2(0.5, 0.3), Vector2(0.3, 0.5), Vector2(-0.3, 0.5), Vector2(-0.5, 0.3)]
	var positions: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for j in range(line.size()):
		var tangent: Vector3 = (line[mini(j + 1, line.size() - 1)] - line[maxi(j - 1, 0)]).normalized()
		var across := Vector3(tangent.y, -tangent.x, 0).normalized() if collar else Vector3.RIGHT
		var normal := tangent.cross(across).normalized()
		for pair: Vector2 in section:
			positions.append(line[j] + across * pair.x * width + normal * pair.y * thickness)
			normals.append((across * pair.x + normal * pair.y).normalized())
	for j in range(line.size() - 1):
		for i in range(section.size()):
			var a := j * section.size() + i
			var d := j * section.size() + (i + 1) % section.size()
			var c := d + section.size()
			var next := a + section.size()
			mesh._triangle(positions[a], positions[next], positions[c], normals[a], normals[next], normals[c], material, 2)
			mesh._triangle(positions[a], positions[c], positions[d], normals[a], normals[c], normals[d], material, 2)
	for j: int in [0, line.size() - 1]:
		var normal := (line[0] - line[1]).normalized() if j == 0 else (line[-1] - line[-2]).normalized()
		for i in range(section.size()):
			mesh._triangle(line[j], positions[j * section.size() + i], positions[j * section.size() + (i + 1) % section.size()], normal, normal, normal, material, 2)


func _head_point(level: Vector3, angle: float) -> Vector3:
	const POWER := 3.0
	var c := cos(angle)
	var s := sin(angle)
	return Vector3(signf(c) * pow(absf(c), 2.0 / POWER) * level.x, level.y, signf(s) * pow(absf(s), 2.0 / POWER) * level.z - 0.025)


func _head_volume(mesh, levels: Array[Vector3]) -> void:
	const SIDES := 32
	var positions: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for j in range(levels.size()):
		for i in range(SIDES):
			var angle := TAU * float(i) / SIDES
			positions.append(_head_point(levels[j], angle))
			var tangent := _head_point(levels[j], angle + 0.001) - _head_point(levels[j], angle - 0.001)
			var vertical := _head_point(levels[mini(j + 1, levels.size() - 1)], angle) - _head_point(levels[maxi(j - 1, 0)], angle)
			normals.append(vertical.cross(tangent).normalized())
	for j in range(levels.size() - 1):
		for i in range(SIDES):
			var a := j * SIDES + i
			var d := j * SIDES + (i + 1) % SIDES
			var c := d + SIDES
			var next := a + SIDES
			mesh._triangle(positions[a], positions[next], positions[c], normals[a], normals[next], normals[c], "skin", 3)
			mesh._triangle(positions[a], positions[c], positions[d], normals[a], normals[c], normals[d], "skin", 3)
	for j: int in [0, levels.size() - 1]:
		var center := Vector3(0, levels[j].y, -0.025)
		var normal := Vector3.DOWN if j == 0 else Vector3.UP
		for i in range(SIDES):
			mesh._triangle(center, positions[j * SIDES + i], positions[j * SIDES + (i + 1) % SIDES], normal, normal, normal, "skin", 3)


func _head_stroke(mesh, levels: Array[Vector3], points: PackedVector3Array, radius: float) -> void:
	for index in range(points.size()):
		var p := points[index]
		for j in range(levels.size() - 1):
			if p.y >= levels[j].y and p.y <= levels[j + 1].y:
				var level := levels[j].lerp(levels[j + 1], (p.y - levels[j].y) / (levels[j + 1].y - levels[j].y))
				p.z = -0.025 - level.z * pow(maxf(0.0, 1.0 - pow(absf(p.x) / level.x, 3.0)), 1.0 / 3.0) - 0.001
				break
		points[index] = p
	mesh.vertex_tints["skin"] = Color("b99576")
	mesh.tube(points, radius * 0.78, "skin", 3, 6)
	mesh.vertex_tints["skin"] = Color.WHITE


func _bevel_box(mesh, center: Vector3, size: Vector3, material: String, bone: int = 0, rotation: Basis = Basis.IDENTITY) -> void:
	var half := size * 0.5
	var radius := minf(half.x, minf(half.y, half.z)) * 0.42
	var inner := half - Vector3.ONE * radius
	# Six quiet face planes, twelve chamfers and eight clipped corners (44 triangles).
	for axis in range(3):
		var across := (axis + 1) % 3
		var vertical := (axis + 2) % 3
		for side: float in [-1.0, 1.0]:
			var positions: Array[Vector3] = []
			var normal := Vector3.ZERO
			normal[axis] = side
			for pair: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := normal * half
				point[across] = pair.x * inner[across]
				point[vertical] = pair.y * inner[vertical]
				positions.append(center + rotation * point)
			normal = rotation * normal
			mesh._triangle(positions[0], positions[1], positions[2], normal, normal, normal, material, bone)
			mesh._triangle(positions[0], positions[2], positions[3], normal, normal, normal, material, bone)
		# This axis is the length direction of four distinct chamfer strips.
		for u: float in [-1.0, 1.0]:
			for v: float in [-1.0, 1.0]:
				var positions: Array[Vector3] = []
				var na := Vector3.ZERO
				var nb := Vector3.ZERO
				na[across] = u
				nb[vertical] = v
				for pair: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(1, 1), Vector2(-1, 1)]:
					var point := inner * (na + nb)
					point[axis] = pair.x * inner[axis]
					point += (na if pair.y == 0 else nb) * radius
					positions.append(center + rotation * point)
				na = rotation * na
				nb = rotation * nb
				mesh._triangle(positions[0], positions[1], positions[2], na, na, nb, material, bone)
				mesh._triangle(positions[0], positions[2], positions[3], na, nb, nb, material, bone)
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				var corner := Vector3(x, y, z) * inner
				var na := Vector3(x, 0, 0)
				var nb := Vector3(0, y, 0)
				var nc := Vector3(0, 0, z)
				mesh._triangle(center + rotation * (corner + na * radius), center + rotation * (corner + nb * radius), center + rotation * (corner + nc * radius), rotation * na, rotation * nb, rotation * nc, material, bone)


func _cloth_mass(mesh, center: Vector3, radii: Vector3, material: String, bone: int, segments: int = 16, rings: int = 10) -> void:
	# The superellipsoid keeps the source cardinal extents and soft joint overlaps.
	const POWER := 2.55
	segments = mini(segments, 12)
	rings = mini(rings, 8)
	for j in range(rings):
		for i in range(segments):
			var positions: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for pair: Vector2i in [Vector2i(i, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1), Vector2i(i + 1, j)]:
				var u := TAU * float(pair.x) / segments
				var v := PI * float(pair.y) / rings
				var direction := Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
				var shaped := Vector3.ZERO
				var normal := Vector3.ZERO
				for axis in range(3):
					shaped[axis] = signf(direction[axis]) * pow(absf(direction[axis]), 2.0 / POWER)
					normal[axis] = signf(shaped[axis]) * pow(absf(shaped[axis]), POWER - 1.0) / radii[axis]
				positions.append(center + shaped * radii)
				normals.append(normal.normalized())
			if j > 0:
				mesh._triangle(positions[0], positions[1], positions[3], normals[0], normals[1], normals[3], material, bone)
			if j < rings - 1:
				mesh._triangle(positions[1], positions[2], positions[3], normals[1], normals[2], normals[3], material, bone)
