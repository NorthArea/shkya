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
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
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
	# A padded U-shaped collar frames the whole lower jaw without clipping its cheeks.
	var collar_line := PackedVector3Array([
		Vector3(-0.154, 0.868, 0.005), Vector3(-0.166, 0.846, -0.046),
		Vector3(-0.170, 0.807, -0.082), Vector3(-0.145, 0.765, -0.133),
		Vector3(-0.088, 0.737, -0.160), Vector3(0, 0.730, -0.170),
		Vector3(0.088, 0.737, -0.160), Vector3(0.145, 0.765, -0.133),
		Vector3(0.170, 0.807, -0.082), Vector3(0.166, 0.846, -0.046),
		Vector3(0.154, 0.868, 0.005),
	])
	mesh.tube(collar_line, 0.028, "armour", 2, 8)
	for index in range(collar_line.size()):
		collar_line[index].z -= 0.006
	mesh.tube(collar_line, 0.024, "suit", 2, 8)
	mesh.ellipsoid(Vector3(0.003, 0.733, -0.204), Vector3(0.008, 0.007, 0.003), "ink", 2, 10, 6)



func _add_legs(mesh) -> void:
	for sign_value in [-1.0, 1.0]:
		var leg: int = 10 if sign_value > 0 else 12
		var foot: int = leg + 1
		var x: float = sign_value * 0.126
		mesh.ellipsoid(Vector3(x, 0.233, 0.007), Vector3(0.121, 0.146, 0.142), "suit", leg, 16, 10)
		mesh.ellipsoid(Vector3(x, 0.123, 0), Vector3(0.075, 0.031, 0.087), "suit", leg, 12, 6)
		# Small cargo pockets sit on the outside-front of the baggy thighs.
		mesh.box(Vector3(x + sign_value * 0.069, 0.246, -0.100), Vector3(0.072, 0.078, 0.030), "armour", leg,
			Basis(Vector3.FORWARD, -sign_value * 0.10))
		mesh.box(Vector3(x + sign_value * 0.069, 0.277, -0.119), Vector3(0.072, 0.012, 0.012), "suit", leg)
		mesh.ellipsoid(Vector3(x, 0.064, 0.006), Vector3(0.052, 0.055, 0.060), "ink", foot, 12, 8)
		mesh.ellipsoid(Vector3(x, 0.035, -0.038), Vector3(0.060, 0.035, 0.086), "ink", foot, 14, 8)
		mesh.box(Vector3(x, 0.009, -0.032), Vector3(0.116, 0.018, 0.165), "ink", foot)
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
		mesh.ellipsoid(Vector3(sign_value * 0.215, 0.744, 0.005), Vector3(0.119, 0.118, 0.119), "suit", upper, 16, 10)
		mesh.ellipsoid(Vector3(sign_value * 0.276, 0.644, -0.003), Vector3(0.103, 0.166, 0.116), "suit", upper, 16, 10)
		mesh.ellipsoid(Vector3(sign_value * 0.326, 0.472, -0.006), Vector3(0.083, 0.139, 0.102), "suit", lower, 16, 10)
		mesh.ellipsoid(Vector3(sign_value * 0.326, 0.365, -0.009), Vector3(0.067, 0.029, 0.077), "armour", lower, 12, 6)
		mesh.ellipsoid(Vector3(sign_value * 0.326, 0.312, -0.014), Vector3(0.057, 0.063, 0.061), "ink", hand, 14, 8)
		mesh.ellipsoid(Vector3(sign_value * 0.284, 0.322, -0.043), Vector3(0.019, 0.033, 0.025), "ink", hand, 10, 6)
		mesh.vertex_tints["suit"] = Color("b9bcc6")
		mesh.box(Vector3(sign_value * 0.328, 0.679, -0.093), Vector3(0.054, 0.054, 0.024), "suit", upper,
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
	mesh.box(Vector3(0, 0.560, -0.182), Vector3(0.340, 0.262, 0.058), "armour", 2)
	mesh.box(Vector3(0, 0.579, 0.163), Vector3(0.355, 0.277, 0.061), "armour", 2)
	for sign_value in [-1.0, 1.0]:
		mesh.ellipsoid(Vector3(sign_value * 0.170, 0.560, -0.182), Vector3(0.022, 0.140, 0.033), "armour", 2, 12, 8)
	for y in [0.468, 0.548, 0.628]:
		mesh.vertex_tints["armour"] = Color("dadada")
		mesh.box(Vector3(0, y, -0.222), Vector3(0.305, 0.073, 0.026), "armour", 2)
		for x in [-0.151, 0.151]:
			mesh.ellipsoid(Vector3(x, y, -0.222), Vector3(0.013, 0.0365, 0.014), "armour", 2, 10, 6)
		mesh.vertex_tints["armour"] = Color("999999")
		for x in [-0.055, 0.055]:
			mesh.tube(PackedVector3Array([
				Vector3(x, y - 0.032, -0.236), Vector3(x, y + 0.032, -0.236),
			]), 0.0012, "armour", 2, 5)
		mesh.vertex_tints["armour"] = Color("dadada")
		mesh.box(Vector3(0, y, 0.204), Vector3(0.324, 0.072, 0.024), "armour", 2)
		mesh.vertex_tints["armour"] = Color("999999")
	for sign_value in [-1.0, 1.0]:
		mesh.ellipsoid(Vector3(sign_value * 0.202, 0.492, -0.148), Vector3(0.037, 0.070, 0.036), "armour", 2, 12, 8)
		mesh.box(Vector3(sign_value * 0.202, 0.526, -0.179), Vector3(0.060, 0.024, 0.012), "armour", 2)
		mesh.ellipsoid(Vector3(sign_value * 0.202, 0.512, -0.186), Vector3(0.004, 0.004, 0.002), "ink", 2, 8, 6)
		# One soft volume follows each shoulder into the vest.
		mesh.ellipsoid(Vector3(sign_value * 0.154, 0.759, -0.060), Vector3(0.043, 0.106, 0.127), "armour", 2, 16, 10)
		mesh.box(Vector3(sign_value * 0.154, 0.742, 0.114), Vector3(0.065, 0.156, 0.032), "armour", 2,
			Basis(Vector3.RIGHT, 0.36))


func _add_head(mesh) -> void:
	var head_levels: Array[Vector3] = [
		Vector3(0.052, 0.752, 0.080), Vector3(0.104, 0.766, 0.109),
		Vector3(0.144, 0.790, 0.132), Vector3(0.158, 0.821, 0.140),
		Vector3(0.149, 0.852, 0.135), Vector3(0.122, 0.885, 0.125),
		Vector3(0.098, 0.913, 0.103), Vector3(0.073, 0.932, 0.070),
		Vector3(0.020, 0.944, 0.025),
	]
	mesh.body_profile(head_levels, "skin", 3, 28)
	for sign_value in [-1.0, 1.0]:
		mesh.ellipsoid(Vector3(sign_value * 0.093, 0.884, -0.032), Vector3(0.014, 0.022, 0.019), "skin", 3, 12, 8)
		mesh.tube(PackedVector3Array([
			Vector3(sign_value * 0.097, 0.894, -0.047), Vector3(sign_value * 0.102, 0.886, -0.051),
			Vector3(sign_value * 0.098, 0.876, -0.047),
		]), 0.0017, "armour", 3, 5)
	for sign_value in [-1.0, 1.0]:
		var x: float = sign_value * 0.023
		mesh.ellipsoid(Vector3(x, 0.888, -0.125), Vector3(0.011, 0.0042, 0.0045), "eye", 3, 12, 6)
		mesh.ellipsoid(Vector3(x - sign_value * 0.002, 0.888, -0.129), Vector3(0.0023, 0.0024, 0.0017), "ink", 3, 8, 4)
		mesh.tube(PackedVector3Array([
			Vector3(x - 0.012, 0.891, -0.127), Vector3(x, 0.890, -0.130), Vector3(x + 0.012, 0.891, -0.127),
		]), 0.0018, "ink", 3, 6)
		mesh.tube(PackedVector3Array([
			Vector3(sign_value * 0.011, 0.895, -0.129),
			Vector3(sign_value * 0.024, 0.901, -0.125),
			Vector3(sign_value * 0.036, 0.902, -0.121),
		]), 0.003, "ink", 3, 7)
		mesh.tube(PackedVector3Array([
			Vector3(sign_value * 0.016, 0.879, -0.128), Vector3(sign_value * 0.025, 0.877, -0.127),
			Vector3(sign_value * 0.032, 0.879, -0.125),
		]), 0.0011, "armour", 3, 5)
	mesh.ellipsoid(Vector3(0, 0.870, -0.128), Vector3(0.014, 0.014, 0.020), "skin", 3, 16, 10)
	for x in [-0.008, 0.008]:
		mesh.ellipsoid(Vector3(x, 0.861, -0.140), Vector3(0.0024, 0.0016, 0.002), "armour", 3, 8, 6)
	# A short, dense brush moustache, with a scalloped bottom edge.
	for x in [-0.020, -0.012, -0.004, 0.004, 0.012, 0.020]:
		mesh.ellipsoid(Vector3(x, 0.854 - absf(x) * 0.04, -0.135), Vector3(0.0052, 0.0055, 0.005), "ink", 3, 6, 4)
	mesh.ellipsoid(Vector3(0, 0.841, -0.142), Vector3(0.024, 0.010, 0.007), "ink", 3, 14, 8)
	mesh.vertex_tints["skin"] = Color("a46555")
	mesh.ellipsoid(Vector3(0, 0.836, -0.148), Vector3(0.015, 0.0024, 0.002), "skin", 3, 10, 4)
	mesh.vertex_tints["skin"] = Color.WHITE
	for sign_value in [-1.0, 1.0]:
		mesh.tube(PackedVector3Array([
			Vector3(sign_value * 0.027, 0.859, -0.133), Vector3(sign_value * 0.034, 0.840, -0.136),
			Vector3(sign_value * 0.036, 0.824, -0.138),
		]), 0.0015, "armour", 3, 5)
		mesh.tube(PackedVector3Array([
			Vector3(sign_value * 0.077, 0.802, -0.118), Vector3(sign_value * 0.097, 0.798, -0.104),
			Vector3(sign_value * 0.116, 0.805, -0.090),
		]), 0.0014, "armour", 3, 5)
	mesh.tube(PackedVector3Array([
		Vector3(-0.018, 0.801, -0.135), Vector3(0, 0.797, -0.136), Vector3(0.018, 0.801, -0.135),
	]), 0.0014, "armour", 3, 5)
	# A single soft wool volume is tilted after mesh construction.
	mesh.ellipsoid(Vector3(-0.010, 0.961, -0.025), Vector3(0.112, 0.033, 0.080), "beret", 3, 24, 12)
