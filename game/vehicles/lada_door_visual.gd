extends Node3D
## Player-only presentation of the existing sedan meshes. BodyMesh stays the
## canonical source for VehicleDamage; cached meshes are never edited here.

const LadaVisual = preload("res://game/vehicles/lada_visual.gd")
const Driver = preload("res://game/vehicles/lada_driver.gd")
const Damage = preload("res://game/vehicles/vehicle_damage.gd")
const NODE_NAME := "OccupantDoor"
const OPEN_ANGLE := -1.12
const SWEEP_STEP := PI / 24.0
const SILL_RISE := 0.06
const WHOLE_PARTS := [&"door_glass_l", &"door_quarter_l", &"door_handle_l", &"door_mirror_l"]
const EPSILON := 0.0000001

var _body: Node3D
var _driver: Node3D
var _spec: Dictionary
var _sources: Array[Dictionary] = []
var _hinge := Vector3.ZERO
var _handle := Vector3.ZERO
var _fraction := 0.0
var _pivot: Node3D
var _remainder: Node3D
var _views_ready := false
var _leaf_bounds := AABB()

static func attach(visual: Node3D) -> Node3D:
	var body := visual.get_node("Body") as Node3D
	var existing := body.get_node_or_null(NODE_NAME)
	if existing:
		return existing as Node3D
	var script: Script = load("res://game/vehicles/lada_door_visual.gd")
	var adapter: Node3D = script.new()
	adapter.name = NODE_NAME
	body.add_child(adapter)
	adapter._setup(visual)
	return adapter

func _setup(visual: Node3D) -> void:
	set_physics_process(false)
	_body = visual.get_node("Body")
	_driver = _body.get_node("Driver")
	_spec = LadaVisual.SEDANS[LadaVisual.PLAYER_MODEL]
	var front: float = _spec["ws"][0].y + 0.03
	_hinge = Vector3(-float(_spec["half_w"]), float(_spec["belt"]) - 0.30, front)
	_handle = Vector3(-float(_spec["half_w"]) - 0.008, float(_spec["belt"]) - 0.11, float(_spec["b_z"]) - 0.10)
	for path in ["BodyMesh", "Glass", "Interior"]:
		var part := _body.get_node(path) as MeshInstance3D
		var base: ArrayMesh = part.get_meta(Damage.ORIGINAL) if part.has_meta(Damage.ORIGINAL) else part.mesh
		assert(base.has_meta("triangle_parts"), "Door requires the sedan's semantic triangle ranges")
		assert(part.transform.is_equal_approx(Transform3D.IDENTITY), "Sedan parts must retain Body coordinates")
		_sources.append({"part": part, "base": base, "last_mesh": null, "was_visible": part.visible})

func set_open_fraction(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if next == 0.0:
		reset_closed()
		return
	if _fraction == 0.0:
		for source in _sources:
			source.was_visible = source.part.visible
	_ensure_views()
	_sync_geometry()
	_fraction = next
	_pivot.rotation.y = OPEN_ANGLE * _fraction
	_pivot.show()
	_remainder.show()
	for source in _sources:
		source.part.hide()
		source.static_view.visible = source.was_visible
		source.leaf_view.visible = source.was_visible and source.leaf_view.mesh != null
	set_physics_process(true)

func open_fraction() -> float:
	return _fraction

func anchors() -> Dictionary:
	var door := _door_transform(_fraction)
	var aperture := Vector3(-float(_spec["glass_w"]), (Driver.LADA_FLOOR + float(_spec["belt"])) * 0.5, (float(_spec["ws"][0].y) + float(_spec["b_z"])) * 0.5)
	var approach := Vector3(-float(_spec["half_w"]) - 0.55, 0.0, Driver.LADA_GRIPS[0].z + 0.30)
	return {
		&"hinge": _body.global_transform * Transform3D(door.basis, _hinge),
		&"handle": _body.global_transform * Transform3D(door.basis, door * _handle),
		&"aperture": _body.global_transform * Transform3D(Basis(Vector3.UP, -PI * 0.5), aperture),
		&"seat": _driver.global_transform,
		&"approach": _body.global_transform * Transform3D(Basis(Vector3.UP, -PI * 0.5), approach),
	}

## World-space convex point cloud. The AABB encloses the complete leaf, and
## sagitta expansion includes arcs between the finite angular samples.
func sweep_vertices(from_fraction: float, to_fraction: float) -> PackedVector3Array:
	_ensure_views()
	_sync_geometry()
	var first := clampf(from_fraction, 0.0, 1.0)
	var last := clampf(to_fraction, 0.0, 1.0)
	var angle := absf((last - first) * OPEN_ANGLE)
	var steps := maxi(1, ceili(angle / SWEEP_STEP))
	var radius := 0.0
	for corner in 8:
		var point := _leaf_bounds.get_endpoint(corner) - _hinge
		radius = maxf(radius, Vector2(point.x, point.z).length())
	var sagitta := radius * (1.0 - cos(angle / (2.0 * steps))) + EPSILON
	var result := PackedVector3Array()
	for step in steps + 1:
		var transform := _door_transform(lerpf(first, last, float(step) / steps))
		for corner in 8:
			var point := transform * _leaf_bounds.get_endpoint(corner)
			for x_sign in [-1.0, 1.0]:
				for z_sign in [-1.0, 1.0]:
					result.append(_body.to_global(point + Vector3(x_sign * sagitta, 0.0, z_sign * sagitta)))
	return result

func reset_closed() -> void:
	if _fraction > 0.0:
		for source in _sources:
			if is_instance_valid(source.part):
				source.part.visible = source.was_visible
	_fraction = 0.0
	if _views_ready:
		_pivot.rotation.y = 0.0
		_pivot.hide()
		_remainder.hide()
	set_physics_process(false)

func _physics_process(_delta: float) -> void:
	if _fraction > 0.0:
		_sync_geometry()

func _exit_tree() -> void:
	reset_closed()

func _door_transform(fraction: float) -> Transform3D:
	var basis := Basis(Vector3.UP, OPEN_ANGLE * fraction)
	return Transform3D(basis, _hinge - basis * _hinge)

func _ensure_views() -> void:
	if _views_ready:
		return
	_pivot = Node3D.new()
	_pivot.name = "Hinge"
	_pivot.position = _hinge
	add_child(_pivot)
	_remainder = Node3D.new()
	_remainder.name = "Remainder"
	add_child(_remainder)
	for source in _sources:
		source["plans"] = _partition(source.base)
		var still := MeshInstance3D.new()
		still.name = source.part.name
		_copy_render_settings(source.part, still)
		_remainder.add_child(still)
		var leaf := MeshInstance3D.new()
		leaf.name = source.part.name
		leaf.position = -_hinge
		_copy_render_settings(source.part, leaf)
		_pivot.add_child(leaf)
		source["static_view"] = still
		source["leaf_view"] = leaf
	_views_ready = true
	_pivot.hide()
	_remainder.hide()

func _copy_render_settings(source: MeshInstance3D, target: MeshInstance3D) -> void:
	target.cast_shadow = source.cast_shadow
	target.layers = source.layers
	target.material_override = source.material_override
	target.material_overlay = source.material_overlay
	target.sorting_offset = source.sorting_offset
	target.visibility_range_begin = source.visibility_range_begin
	target.visibility_range_end = source.visibility_range_end
	target.visibility_range_begin_margin = source.visibility_range_begin_margin
	target.visibility_range_end_margin = source.visibility_range_end_margin
	target.visibility_range_fade_mode = source.visibility_range_fade_mode
	target.extra_cull_margin = source.extra_cull_margin
	target.gi_mode = source.gi_mode

func _sync_geometry() -> void:
	var changed := false
	for source in _sources:
		var current: ArrayMesh = source.part.mesh
		if current == source.last_mesh:
			continue
		source.static_view.mesh = _materialize(source, current, &"static")
		source.leaf_view.mesh = _materialize(source, current, &"leaf")
		source.last_mesh = current
		changed = true
	if changed:
		var first := true
		for source in _sources:
			var leaf_mesh: Mesh = source.leaf_view.mesh
			if leaf_mesh:
				_leaf_bounds = leaf_mesh.get_aabb() if first else _leaf_bounds.merge(leaf_mesh.get_aabb())
				first = false
		assert(not first, "Driver door must contain actual sedan surfaces")

func _partition(mesh: ArrayMesh) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	var parts: Array = mesh.get_meta("triangle_parts")
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for index in vertices.size(): indices.append(index)
		var plan := {"surface": surface, "indices": indices, "static": {"refs": [], "weights": []}, "leaf": {"refs": [], "weights": []}}
		var ranges: Array = parts[surface]
		var cursor := 0
		for triangle in indices.size() / 3:
			while cursor < ranges.size() and triangle >= ranges[cursor][0] + ranges[cursor][1]:
				cursor += 1
			var tag: StringName = ranges[cursor][2] if cursor < ranges.size() and triangle >= ranges[cursor][0] else &""
			var original: Array[Vector3] = [vertices[indices[triangle * 3]], vertices[indices[triangle * 3 + 1]], vertices[indices[triangle * 3 + 2]]]
			var polygon: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
			if tag in WHOLE_PARTS:
				_append_polygon(plan.leaf, polygon, triangle, original)
			elif tag in [&"side_shell", &"inner_wall_l", &"belt_trim_l"]:
				for plane: Plane in _cut_planes(tag):
					_append_polygon(plan["static"], _clip(polygon, original, plane, false), triangle, original)
					polygon = _clip(polygon, original, plane, true)
					if polygon.is_empty(): break
				_append_polygon(plan.leaf, polygon, triangle, original)
			else:
				_append_polygon(plan["static"], polygon, triangle, original)
		for key in [&"static", &"leaf"]:
			plan[key].refs = PackedInt32Array(plan[key].refs)
			plan[key].weights = PackedVector3Array(plan[key].weights)
		plans.append(plan)
	return plans

func _cut_planes(tag: StringName) -> Array[Plane]:
	var front: float = _spec["ws"][0].y + 0.03
	var back: float = _spec["b_z"] + 0.01
	var planes: Array[Plane] = [Plane(Vector3.FORWARD, -front), Plane(Vector3.BACK, back)]
	if tag in [&"side_shell", &"inner_wall_l"]:
		planes.append(Plane(Vector3.DOWN, -Driver.LADA_FLOOR - SILL_RISE))
	if tag == &"side_shell":
		planes.append(Plane(Vector3.RIGHT, -float(_spec["glass_w"]) + 0.08))
		planes.append(Plane(Vector3.UP, float(_spec["belt"]) + 0.02))
	return planes

func _clip(polygon: Array[Vector3], original: Array[Vector3], plane: Plane, inside: bool) -> Array[Vector3]:
	var output: Array[Vector3] = []
	if polygon.is_empty(): return output
	var previous: Vector3 = polygon[-1]
	var previous_distance := plane.distance_to(_weighted(original, previous))
	var previous_kept := (previous_distance <= EPSILON) == inside
	for point in polygon:
		var distance := plane.distance_to(_weighted(original, point))
		var kept := (distance <= EPSILON) == inside
		if kept != previous_kept:
			output.append(previous.lerp(point, clampf(previous_distance / (previous_distance - distance), 0.0, 1.0)))
		if kept: output.append(point)
		previous = point
		previous_distance = distance
		previous_kept = kept
	return output

func _append_polygon(bucket: Dictionary, polygon: Array[Vector3], triangle: int, original: Array[Vector3]) -> void:
	for index in range(1, polygon.size() - 1):
		var a := _weighted(original, polygon[0])
		var b := _weighted(original, polygon[index])
		var c := _weighted(original, polygon[index + 1])
		if (b - a).cross(c - a).length_squared() <= 0.00000000000001: continue
		for barycentric: Vector3 in [polygon[0], polygon[index], polygon[index + 1]]:
			bucket.refs.append(triangle)
			bucket.weights.append(barycentric)

func _weighted(points: Array[Vector3], weights: Vector3) -> Vector3:
	return points[0] * weights.x + points[1] * weights.y + points[2] * weights.z

func _materialize(source: Dictionary, current: ArrayMesh, key: StringName) -> ArrayMesh:
	var result := ArrayMesh.new()
	var slots: Array = []
	var original_slots: Array = current.get_meta("slots", [])
	for plan: Dictionary in source.plans:
		var mapping: Dictionary = plan[key]
		var refs: PackedInt32Array = mapping.refs
		if refs.is_empty(): continue
		var barycentric: PackedVector3Array = mapping.weights
		var indices: PackedInt32Array = plan.indices
		var arrays := current.surface_get_arrays(plan.surface)
		var output: Array = []
		output.resize(Mesh.ARRAY_MAX)
		for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			if arrays[attribute] == null or arrays[attribute].is_empty(): continue
			var values = arrays[attribute]
			var mapped = PackedVector3Array() if attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL] else PackedColorArray() if attribute == Mesh.ARRAY_COLOR else PackedVector2Array()
			for index in refs.size():
				var start := refs[index] * 3
				var weight := barycentric[index]
				var value = values[indices[start]] * weight.x + values[indices[start + 1]] * weight.y + values[indices[start + 2]] * weight.z
				if attribute == Mesh.ARRAY_NORMAL: value = value.normalized()
				mapped.append(value)
			output[attribute] = mapped
		result.add_surface_from_arrays(current.surface_get_primitive_type(plan.surface), output)
		var target_surface := result.get_surface_count() - 1
		result.surface_set_material(target_surface, source.part.get_active_material(plan.surface))
		slots.append(original_slots[plan.surface] if plan.surface < original_slots.size() else "")
	if result.get_surface_count() == 0: return null
	result.set_meta("slots", slots)
	return result
