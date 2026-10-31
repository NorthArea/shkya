extends RefCounted
## Authored solid geometry for the two uniformed figures. Coordinates are bind-space,
## +Y up and -Z forward. Each part is rigid-weighted to its anatomical bone.

var palette: Dictionary = {}
# Optional per-material tint for newly emitted vertices; default keeps consumer materials intact.
var vertex_tints: Dictionary = {}
var _parts: Dictionary = {}
var _bone_names: Array[String] = []
var _bone_parents: Array[int] = []
var _bone_origins: Array[Vector3] = []

func add_bone(bone_name: String, parent: int, origin: Vector3) -> int:
	assert(parent >= -1 and parent < _bone_names.size())
	assert(not bone_name in _bone_names)
	_bone_names.append(bone_name)
	_bone_parents.append(parent)
	_bone_origins.append(origin)
	return _bone_names.size() - 1

func ellipsoid(center: Vector3, radii: Vector3, material: String, bone: int = 0, segments: int = 16, rings: int = 10) -> void:
	assert(radii.x > 0.0 and radii.y > 0.0 and radii.z > 0.0)
	segments = maxi(segments, 4)
	rings = maxi(rings, 3)
	for j in range(rings):
		for i in range(segments):
			var u0 := TAU * float(i) / segments
			var u1 := TAU * float(i + 1) / segments
			var v0 := PI * float(j) / rings
			var v1 := PI * float(j + 1) / rings
			var directions := [Vector3(sin(v0) * cos(u0), cos(v0), sin(v0) * sin(u0)),
				Vector3(sin(v1) * cos(u0), cos(v1), sin(v1) * sin(u0)),
				Vector3(sin(v1) * cos(u1), cos(v1), sin(v1) * sin(u1)),
				Vector3(sin(v0) * cos(u1), cos(v0), sin(v0) * sin(u1))]
			var p: Array[Vector3] = []
			var n: Array[Vector3] = []
			for d: Vector3 in directions:
				p.append(center + d * radii)
				n.append((d / radii).normalized())
			if j > 0:
				_triangle(p[0], p[1], p[3], n[0], n[1], n[3], material, bone)
			if j < rings - 1:
				_triangle(p[1], p[2], p[3], n[1], n[2], n[3], material, bone)

func box(center: Vector3, size: Vector3, material: String, bone: int = 0, rotation: Basis = Basis.IDENTITY) -> void:
	var half := size * 0.5
	for axis in range(3):
		for sign_value in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sign_value
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			v[(axis + 2) % 3] = 1.0
			var p: Array[Vector3] = []
			for pair: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				p.append(center + rotation * ((n + u * pair.x + v * pair.y) * half))
			var normal := (rotation * n).normalized()
			_triangle(p[0], p[1], p[2], normal, normal, normal, material, bone)
			_triangle(p[0], p[2], p[3], normal, normal, normal, material, bone)

func body_profile(levels: Array[Vector3], material: String, bone: int = 0, sides: int = 20) -> void:
	assert(levels.size() >= 2)
	sides = maxi(sides, 4)
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for j in range(levels.size()):
		var current := levels[j]
		var previous := levels[maxi(j - 1, 0)]
		var following := levels[mini(j + 1, levels.size() - 1)]
		var dy := maxf(following.y - previous.y, 0.00001)
		var dx := (following.x - previous.x) / dy
		var dz := (following.z - previous.z) / dy
		assert(current.x > 0.0 and current.z > 0.0)
		for i in range(sides):
			var a := TAU * float(i) / sides
			var c := cos(a)
			var s := sin(a)
			vertices.append(Vector3(c * current.x, current.y, s * current.z))
			normals.append(Vector3(c / current.x, -dx / current.x * c * c - dz / current.z * s * s, s / current.z).normalized())
	for j in range(levels.size() - 1):
		for i in range(sides):
			var a := j * sides + i
			var b := (j + 1) * sides + i
			var c := (j + 1) * sides + (i + 1) % sides
			var d := j * sides + (i + 1) % sides
			_triangle(vertices[a], vertices[b], vertices[c], normals[a], normals[b], normals[c], material, bone)
			_triangle(vertices[a], vertices[c], vertices[d], normals[a], normals[c], normals[d], material, bone)
	for j in [0, levels.size() - 1]:
		var center := Vector3(0.0, levels[j].y, 0.0)
		var normal := Vector3.DOWN if j == 0 else Vector3.UP
		for i in range(sides):
			_triangle(center, vertices[j * sides + i], vertices[j * sides + (i + 1) % sides], normal, normal, normal, material, bone)

func tube(points: PackedVector3Array, radius: float, material: String, bone: int = 0, sides: int = 6) -> void:
	assert(radius > 0.0)
	if points.size() < 2:
		return
	sides = maxi(sides, 3)
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for j in range(points.size()):
		var tangent: Vector3
		if j == 0:
			tangent = (points[1] - points[0]).normalized()
		elif j == points.size() - 1:
			tangent = (points[j] - points[j - 1]).normalized()
		else:
			tangent = (points[j + 1] - points[j - 1]).normalized()
		assert(tangent.length_squared() > 0.1)
		var reference := Vector3.UP if absf(tangent.y) < 0.9 else Vector3.RIGHT
		var u := tangent.cross(reference).normalized()
		var v := tangent.cross(u).normalized()
		for i in range(sides):
			var a := TAU * float(i) / sides
			var n := u * cos(a) + v * sin(a)
			vertices.append(points[j] + n * radius)
			normals.append(n)
	for j in range(points.size() - 1):
		for i in range(sides):
			var a := j * sides + i
			var b := (j + 1) * sides + i
			var c := (j + 1) * sides + (i + 1) % sides
			var d := j * sides + (i + 1) % sides
			_triangle(vertices[a], vertices[b], vertices[c], normals[a], normals[b], normals[c], material, bone)
			_triangle(vertices[a], vertices[c], vertices[d], normals[a], normals[c], normals[d], material, bone)
	for j in [0, points.size() - 1]:
		var normal := (points[0] - points[1]).normalized() if j == 0 else (points[-1] - points[-2]).normalized()
		for i in range(sides):
			_triangle(points[j], vertices[j * sides + i], vertices[j * sides + (i + 1) % sides], normal, normal, normal, material, bone)

func _triangle(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, material: String, bone: int) -> void:
	assert(palette.has(material))
	assert(bone >= 0 and bone < _bone_names.size())
	if (b - a).cross(c - a).length_squared() < 1.0e-20:
		return
	if not _parts.has(material):
		_parts[material] = {"positions": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(), "bones": PackedInt32Array(), "weights": PackedFloat32Array()}
	var part: Dictionary = _parts[material]
	var tint: Color = vertex_tints.get(material, Color.WHITE)
	# Godot's front face winding is clockwise, while supplied normals point out.
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		_append_vertex(part, a, na, bone, tint)
		_append_vertex(part, c, nc, bone, tint)
		_append_vertex(part, b, nb, bone, tint)
	else:
		_append_vertex(part, a, na, bone, tint)
		_append_vertex(part, b, nb, bone, tint)
		_append_vertex(part, c, nc, bone, tint)

func _append_vertex(part: Dictionary, vertex: Vector3, normal: Vector3, bone: int, tint: Color) -> void:
	part["positions"].append(vertex)
	part["normals"].append(normal)
	part["colors"].append(tint)
	part["bones"].append_array(PackedInt32Array([bone, 0, 0, 0]))
	part["weights"].append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))

func triangle_count() -> int:
	var count := 0
	for part: Dictionary in _parts.values():
		count += int(float(part["positions"].size()) / 3.0)
	return count

func build_node(model_name: String) -> Node3D:
	assert(not _bone_names.is_empty())
	var root := Node3D.new()
	root.name = model_name
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	var skin := Skin.new()
	var bone_map: Dictionary = {}
	for i in range(_bone_names.size()):
		skeleton.add_bone(_bone_names[i])
		skeleton.set_bone_parent(i, _bone_parents[i])
		var parent_origin := Vector3.ZERO if _bone_parents[i] == -1 else _bone_origins[_bone_parents[i]]
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, _bone_origins[i] - parent_origin))
		skin.add_bind(i, Transform3D(Basis.IDENTITY, -_bone_origins[i]))
		bone_map[_bone_names[i]] = i
	var mesh := ArrayMesh.new()
	mesh.resource_name = model_name + "_AuthoredMesh"
	for key: String in _parts:
		var part: Dictionary = _parts[key]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = part["positions"]
		arrays[Mesh.ARRAY_NORMAL] = part["normals"]
		arrays[Mesh.ARRAY_COLOR] = part["colors"]
		arrays[Mesh.ARRAY_BONES] = part["bones"]
		arrays[Mesh.ARRAY_WEIGHTS] = part["weights"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface := mesh.get_surface_count() - 1
		mesh.surface_set_material(surface, palette[key])
		mesh.surface_set_name(surface, key)
	var instance := MeshInstance3D.new()
	instance.name = "UniformMesh"
	instance.mesh = mesh
	instance.skin = skin
	skeleton.add_child(instance)
	instance.skeleton = NodePath("..")
	root.set_meta("bone_names", bone_map)
	root.set_meta("visible_height", 1.0)
	root.set_meta("triangle_count", triangle_count())
	root.set_meta("authored_source", "Godot procedural solid geometry; no external textures")
	return root
