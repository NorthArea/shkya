extends RefCounted
## Ранняя ГАЗель (1995–2002): 2705, пассажирская 32213 и обычная 32214.
## Своя геометрия, без внешних моделей/текстур. Не 3302 с будкой, не Business/Next.
## Габариты/свесы: https://www.drom.ru/catalog/lcv/gaz/gazelle/272216/ .
## Схема компоновки/свесов: https://www.logistikmsk.ru/gabariti_mashin/gab_gaz_celnomet.html ;
## её поздний передок не переносится, колея сдвоенной оси берётся из руководства ниже.
## Форма передка: https://s.auto.drom.ru/i24241/c/photos/fullsize/gaz/gazelle/gaz_gazelle_938508.jpg .
## Панели/корма: https://oldcarfoto.ru/photo/92234/ ; окна грузового отделения не переносим.
## Шины 185/75 R16C и колея между серединами сдвоенных пар — руководство ГАЗ-2705 1995+:
## https://sinref.ru/avtomobili/0000_YY1_15_4600_raznie_2_sin_2026-06/400_06_GAZ_2705_1995_gazel/003.htm .
## Размеры отдельных панелей/салона приблизительны. Перед −Z; шины касаются y=0.
## SIZE без зеркал/снега; разрешённые руководством шины 185/75 R16C дают радиус 0.34195 м.

const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const SIZE := Vector3(2.075, 2.2, 5.47)
const WHEELBASE := 2.9
const WHEEL_RADIUS := 0.34195
const WHEEL_WIDTH := 0.185
const AXLES := [-1.705, 1.195]
const TRACK_HALF := [0.85, 0.78]
const REAR_TWIN_OFFSET := 0.102
const HALF_WIDTH := 1.0375
const ARCH_RADIUS := 0.41
const HULL_LENGTH := 5.24
const ROOF_Y := 2.2
const TOP := [[-2.62, 1.075], [-2.48, 1.13], [-1.95, 1.345], [-1.86, 1.18],
	[-0.45, 1.18], [2.54, 1.18], [2.62, 1.15]]
const BOTTOM := [[-2.62, 0.45], [-2.30, 0.34], [-1.0, 0.305], [2.48, 0.31], [2.62, 0.38]]
const CAB_GLASS_HALF_WIDTH := 0.953
const CAB_ROOF_HALF_WIDTH := 0.871
const CARGO := &"2705"
const PASSENGER := &"32213"
const AMBULANCE := &"32214"
const DOOR_INNER_X := 0.95
const DOOR_BOTTOM := 0.83
const DOOR_TOP := 2.025
const DOOR_FRONT := -0.37
const DOOR_REAR := 1.03
const DOOR_SLIDE := Vector3(0.08, 0.0, 1.4)
const OPEN_DOOR_SIGN := Vector3(HALF_WIDTH + DOOR_SLIDE.x + 0.015, 1.65, (DOOR_FRONT + DOOR_REAR) * 0.5 + DOOR_SLIDE.z)
const SIDE_WINDOWS := [[-0.32, 0.73], [0.84, 1.76], [1.87, 2.43]]


static func build(paint: Color, plate: String = "", snow_depth: float = 0.08, model: StringName = CARGO, door_open: bool = false) -> Node3D:
	assert(model in [CARGO, PASSENGER, AMBULANCE], "Unknown GAZelle model")
	var visual := Node3D.new()
	visual.name = "Visual"
	var body := Node3D.new()
	body.name = "Body"
	visual.add_child(body)
	var meshes := body_meshes(model, door_open)
	var paint_material: ShaderMaterial = VehicleMesh.paint(paint, 0.20, 0.68,
		clampf(snow_depth * 3.0, 0.0, 0.7), 0.54).duplicate()
	VehicleMesh.instance(body, "BodyMesh", meshes["body"], {"paint": paint_material,
		"head": VehicleMesh.mat("lens_white").duplicate(),
		"tail": VehicleMesh.mat("lens_red").duplicate(),
		"lens_amber": VehicleMesh.mat("lens_amber").duplicate()})
	var glass := VehicleMesh.instance(body, "Glass", meshes["glass"], {}, false)
	glass.sorting_offset = -0.5
	var interior := VehicleMesh.instance(body, "Interior", meshes["interior"], {}, false)
	interior.visibility_range_end = 45.0
	if snow_depth > 0.0:
		VehicleMesh.instance(body, "Snow", snow_mesh(snow_depth))
	var spots := wheel_spots()
	for index in spots.size():
		var pivot := Node3D.new()
		pivot.name = "WheelPivot%d" % index
		pivot.position = spots[index]
		visual.add_child(pivot)
		var wheel := VehicleMesh.instance(pivot, "Wheel", wheel_mesh())
		wheel.rotation.z = PI * 0.5
		wheel.visibility_range_end = 120.0
	if not plate.is_empty():
		_plate_label(body, Vector3(0, 0.655, -2.748), PI, plate)
		_plate_label(body, Vector3(-0.435, 0.805, 2.663), 0.0, plate)
	return visual


static func wheel_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		spots.append(Vector3(side * TRACK_HALF[0], WHEEL_RADIUS, AXLES[0]))
	for side in [-1.0, 1.0]:
		for offset in [-REAR_TWIN_OFFSET, REAR_TWIN_OFFSET]:
			spots.append(Vector3(side * (TRACK_HALF[1] + offset), WHEEL_RADIUS, AXLES[1]))
	return spots


static func wheel_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = VehicleMesh.cached("gazelle2705_wheel")
	if mesh != null:
		return mesh
	var wheel := VehicleMesh.Builder.new()
	var hw := WHEEL_WIDTH * 0.5
	var rim := 0.2032
	wheel.lathe("rubber", PackedVector2Array([
		Vector2(rim, -hw + 0.012), Vector2(WHEEL_RADIUS - 0.031, -hw),
		Vector2(WHEEL_RADIUS - 0.006, -hw + 0.018), Vector2(WHEEL_RADIUS, -hw * 0.46),
		Vector2(WHEEL_RADIUS, hw * 0.46), Vector2(WHEEL_RADIUS - 0.006, hw - 0.018),
		Vector2(WHEEL_RADIUS - 0.031, hw), Vector2(rim, hw - 0.012),
	]), 48, Vector3.ZERO, PackedInt32Array([3, 4]), 0.010)
	for side in [-1.0, 1.0]:
		var s: float = side
		wheel.lathe("steel", PackedVector2Array([
			Vector2(rim + 0.006, s * (hw - 0.013)), Vector2(rim * 0.92, s * (hw - 0.022)),
			Vector2(rim * 0.73, s * (hw - 0.059)), Vector2(rim * 0.50, s * (hw - 0.063)),
			Vector2(rim * 0.32, s * (hw - 0.044)), Vector2(0.001, s * (hw - 0.044)),
		]), 40, Vector3.ZERO)
		for k in 6:
			var angle := TAU * k / 6.0
			var at := Vector3(cos(angle) * 0.142, s * (hw - 0.031), sin(angle) * 0.142)
			var points := PackedVector3Array()
			for j in 14:
				var a := TAU * j / 14.0
				points.append(at + Vector3(cos(a) * 0.022, 0, sin(a) * 0.022))
			wheel.poly("dark", points, Vector3.UP * s)
			wheel.box("chrome", Vector3(0.021, 0.016, 0.021),
				Vector3(cos(angle) * 0.085, s * (hw - 0.039), sin(angle) * 0.085))
		wheel.lathe("steel", PackedVector2Array([
			Vector2(0.060, s * (hw - 0.045)), Vector2(0.049, s * (hw + 0.012)),
			Vector2(0.001, s * (hw + 0.014)),
		]), 24, Vector3.ZERO)
	mesh = VehicleMesh.finish(wheel)
	return VehicleMesh.store("gazelle2705_wheel", mesh)


static func body_meshes(model: StringName = CARGO, door_open: bool = false) -> Dictionary:
	if door_open:
		assert(model == PASSENGER, "Open side door is supported by the passenger shell")
		var opened: Variant = VehicleMesh.cached("gazelle32213_open_body")
		if opened != null:
			return opened
		var closed := body_meshes(model)
		var meshes := closed.duplicate()
		meshes["body"] = _open_door_mesh(closed["body"])
		meshes["glass"] = _open_door_mesh(closed["glass"])
		return VehicleMesh.store("gazelle32213_open_body", meshes)
	assert(model in [CARGO, PASSENGER, AMBULANCE], "Unknown GAZelle model")
	# Standard-roof 32214 uses the same production windowed shell, not a department-specific body.
	if model == AMBULANCE:
		var medical := body_meshes(PASSENGER).duplicate()
		medical["interior"] = _medical_interior()
		return medical
	var key := "gazelle2705_body" if model == CARGO else "gazelle32213_body"
	var found: Variant = VehicleMesh.cached(key)
	if found != null:
		return found
	var body := VehicleMesh.Builder.new()
	var glass := VehicleMesh.Builder.new()
	var interior := VehicleMesh.Builder.new()
	_lower_shell(body)
	_cab(body, glass)
	if model == CARGO:
		_cargo_shell(body)
	else:
		_passenger_shell(body, glass)
	_front(body)
	_rear(body, glass, model != CARGO)
	_sides(body)
	_cabin(interior, model != CARGO)
	var meshes := {
		"body": VehicleMesh.finish(body, {"paint": VehicleMesh.paint(Color(0.76, 0.77, 0.72)),
			"head": VehicleMesh.mat("lens_white"), "tail": VehicleMesh.mat("lens_red")}),
		"glass": VehicleMesh.finish(glass, {"glass": VehicleMesh.glass(0.018)}),
		"interior": VehicleMesh.finish(interior),
	}
	return VehicleMesh.store(key, meshes)


static func _lower_shell(body: VehicleMesh.Builder) -> void:
	var stations := VehicleMesh.hull_stations(HULL_LENGTH, HALF_WIDTH, TOP, BOTTOM,
		AXLES, WHEEL_RADIUS, ARCH_RADIUS, 0.10, 0.075, 0.027, 0.025, 0.045, 0.075)
	# The hood is closed; behind the cowl the lower shell is a U, not a painted
	# horizontal lid through the seats. Keep the original rounded outer sections.
	var cowl_z := -1.86
	stations.append([cowl_z, _bottom_at(cowl_z), 1.18, HALF_WIDTH, HALF_WIDTH - 0.027, 0.025, 0.045])
	stations.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var hood_rows: Array = []
	var hood_refs := PackedVector3Array()
	var open_rows: Array = []
	var open_refs := PackedVector3Array()
	var last_section := PackedVector3Array()
	for station in stations:
		var ring := body.section(station[0], station[1], station[2], station[3], station[4], station[5], station[6])
		var center := Vector3(0, (float(station[1]) + float(station[2])) * 0.5, station[0])
		if station[0] <= cowl_z:
			hood_rows.append(ring)
			hood_refs.append(center)
		if station[0] >= cowl_z:
			# section(): top center is halfway around the symmetric ring. Start
			# after it and finish before it, preserving both shoulders and floor.
			var top_center := ring.size() / 2
			var open := PackedVector3Array()
			for index in range(top_center + 1, ring.size()):
				open.append(ring[index])
			for index in range(top_center):
				open.append(ring[index])
			open_rows.append(open)
			open_refs.append(center)
		last_section = ring
	body.grid("paint", hood_rows, true, hood_refs)
	body.grid("paint", open_rows, false, open_refs)
	body.cap("paint", hood_rows[0], Vector3.FORWARD)
	body.cap("paint", last_section, Vector3.BACK)


static func _passenger_shell(body: VehicleMesh.Builder, glass: VehicleMesh.Builder) -> void:
	# The roof and belt stop at the window edges: no painted wall behind the glass.
	body.loft("paint", [
		[-0.44, 2.02, 2.19, 0.995, 0.995, 0.018, 0.18],
		[0.0, 2.02, ROOF_Y, 0.995, 0.995, 0.018, 0.18],
		[1.30, 2.02, ROOF_Y, 0.995, 0.995, 0.018, 0.18],
		[2.47, 2.02, 2.19, 0.995, 0.995, 0.018, 0.18],
		[2.61, 2.02, 2.135, 0.966, 0.966, 0.018, 0.15],
	], true, 5)
	for side in [-1.0, 1.0]:
		var s: float = side
		_side_sheet(body, s, -0.44, 2.47, 1.145, 1.35)
		_side_sheet(body, s, -0.44, 2.47, 1.98, 2.02)
		for span in [[-0.44, -0.32], [0.73, 0.84], [1.76, 1.87], [2.43, 2.47]]:
			_side_sheet(body, s, span[0], span[1], 1.35, 1.98)
		for window in SIDE_WINDOWS:
			var z0: float = window[0]
			var z1: float = window[1]
			glass.pane("glass", Vector3(s * _side_x(1.35), 1.35, z0),
				Vector3(s * _side_x(1.35), 1.35, z1),
				Vector3(s * _side_x(1.98), 1.98, z1),
				Vector3(s * _side_x(1.98), 1.98, z0), Vector3(s, 0.05, 0).normalized(), 0.006, 5, 3)
		# Curved rear corner remains metal beside the two glazed rear doors.
		body.poly("paint", PackedVector3Array([
			Vector3(s * _side_x(1.145), 1.145, 2.47), Vector3(s * 1.015, 1.145, 2.61),
			Vector3(s * 0.966, 2.02, 2.61), Vector3(s * _side_x(2.02), 2.02, 2.47),
		]), Vector3(s, 0, 0.2).normalized(), true)
		body.tube("paint", Vector3(s * 0.994, 2.025, -0.40), Vector3(s * 0.994, 2.025, 2.48), 0.012, 6)
	body.box("paint", Vector3(1.93, 0.205, 0.018), Vector3(0, 1.2475, 2.612))
	body.box("paint", Vector3(1.93, 0.04, 0.018), Vector3(0, 2.0, 2.612))
	for span in [[-0.965, -0.79], [-0.10, 0.10], [0.79, 0.965]]:
		body.box("paint", Vector3(span[1] - span[0], 0.63, 0.018), Vector3((span[0] + span[1]) * 0.5, 1.665, 2.612))


static func _side_sheet(body: VehicleMesh.Builder, side: float, z0: float, z1: float, y0: float, y1: float) -> void:
	body.poly("paint", PackedVector3Array([
		Vector3(side * _side_x(y0), y0, z0), Vector3(side * _side_x(y0), y0, z1),
		Vector3(side * _side_x(y1), y1, z1), Vector3(side * _side_x(y1), y1, z0),
	]), Vector3(side, 0.05, 0).normalized(), true)


static func _cargo_shell(body: VehicleMesh.Builder) -> void:
	# Единая штампованная оболочка, крыша продолжается над кабиной; нет отдельного грузового ящика.
	body.loft("paint", [
		[-0.44, 1.145, 2.19, HALF_WIDTH, 0.995, 0.018, 0.18],
		[0.00, 1.145, ROOF_Y, HALF_WIDTH, 0.995, 0.018, 0.18],
		[1.30, 1.145, ROOF_Y, HALF_WIDTH, 0.995, 0.018, 0.18],
		[2.47, 1.145, 2.19, HALF_WIDTH, 0.995, 0.018, 0.18],
		[2.61, 1.145, 2.135, 1.015, 0.966, 0.018, 0.15],
	], true, 5)
	for side in [-1.0, 1.0]:
		var s: float = side
		for panel in SIDE_WINDOWS:
			_side_panel(body, s, panel[0], panel[1], 1.35, 1.98)
		body.tube("paint", Vector3(s * 0.994, 2.025, -0.40), Vector3(s * 0.994, 2.025, 2.48), 0.012, 6)
		for z in [-0.35, 0.81, 1.82, 2.47]:
			body.tube("paint", Vector3(s * 0.825, 2.185, z), Vector3(s * 0.94, 2.147, z), 0.009, 5)


static func _side_x(y: float) -> float:
	return lerpf(HALF_WIDTH, 0.995, clampf((y - 1.163) / (2.02 - 1.163), 0.0, 1.0))


static func _side_panel(body: VehicleMesh.Builder, side: float, z0: float, z1: float, y0: float, y1: float) -> void:
	# A stamped crease follows the metal sheet. A round tube gives these nearly
	# vertical panels upward-facing facets, which incorrectly collect snow.
	var points := PackedVector3Array()
	var radius := minf(0.07, (z1 - z0) * 0.18)
	for corner in [Vector2(z0 + radius, y0 + radius), Vector2(z1 - radius, y0 + radius),
		Vector2(z1 - radius, y1 - radius), Vector2(z0 + radius, y1 - radius)]:
		var index := points.size() / 5
		for k in 5:
			var angle := PI + index * PI * 0.5 + k * PI * 0.5 / 4.0
			var z: float = corner.x + cos(angle) * radius
			var y: float = corner.y + sin(angle) * radius
			points.append(Vector3(side * (_side_x(y) + 0.005), y, z))
	var inside := PackedVector3Array()
	var outside := PackedVector3Array()
	for k in points.size():
		var tangent := points[(k + 1) % points.size()] - points[(k - 1 + points.size()) % points.size()]
		var across := Vector3(0, -tangent.z, tangent.y).normalized() * 0.008
		var inner := points[k] - across
		var outer := points[k] + across
		inner.x = side * (_side_x(inner.y) + 0.005)
		outer.x = side * (_side_x(outer.y) + 0.005)
		inside.append(inner)
		outside.append(outer)
	for k in points.size():
		var next := (k + 1) % points.size()
		body.poly("paint", PackedVector3Array([inside[k], inside[next], outside[next], outside[k]]),
			Vector3(side, 0.05, 0).normalized())


static func _cab(body: VehicleMesh.Builder, glass: VehicleMesh.Builder) -> void:
	body.loft("paint", [
		[-1.27, 2.01, 2.10, 0.858, 0.84, 0.015, 0.035],
		[-1.11, 2.01, 2.175, 0.908, 0.884, 0.018, 0.095],
		[-0.44, 2.01, 2.19, 0.995, 0.975, 0.018, 0.13],
	], true, 4)
	for side in [-1.0, 1.0]:
		var s: float = side
		var outward := Vector3(s, 0.12, 0).normalized()
		body.poly("trim", PackedVector3Array([
			Vector3(s * 0.977, 1.31, -1.95), Vector3(s * 0.97, 1.31, -1.58),
			Vector3(s * 0.874, 2.02, -1.12), Vector3(s * 0.851, 2.02, -1.26),
		]), outward, true)
		body.poly("paint", PackedVector3Array([
			Vector3(s * 1.011, 1.162, -1.86), Vector3(s * 1.011, 1.162, -0.435),
			Vector3(s * 0.970, 1.323, -0.435), Vector3(s * 0.970, 1.323, -1.58),
		]), outward, true)
		body.tube("paint", Vector3(s * 0.978, 1.28, -0.43), Vector3(s * 0.948, 2.035, -0.43), 0.035, 6)
		glass.pane("glass", Vector3(s * CAB_GLASS_HALF_WIDTH, 1.32, -1.52),
			Vector3(s * 0.965, 1.32, -0.467), Vector3(s * 0.938, 2.018, -0.467),
			Vector3(s * CAB_ROOF_HALF_WIDTH, 2.018, -1.09), outward, 0.006, 5, 3)
		# Узкая передняя неподвижная секция бокового стекла.
		body.tube("trim", Vector3(s * 0.958, 1.324, -1.24), Vector3(s * 0.897, 2.018, -0.94), 0.010, 5)
		body.tube("trim", Vector3(s * 0.962, 1.315, -1.54), Vector3(s * 0.970, 1.315, -0.46), 0.012, 6)
	var out := Vector3(0, 0.74, -0.68).normalized()
	glass.pane("glass", Vector3(-0.931, 1.383, -1.936), Vector3(0.931, 1.383, -1.936),
		Vector3(0.820, 2.012, -1.265), Vector3(-0.820, 2.012, -1.265), out, 0.026, 8, 4)
	body.poly("paint", PackedVector3Array([
		Vector3(-0.96, 1.345, -1.96), Vector3(0.96, 1.345, -1.96),
		Vector3(0.931, 1.383, -1.936), Vector3(-0.931, 1.383, -1.936),
	]), out)
	body.tube("trim", Vector3(-0.936, 1.382, -1.944), Vector3(0.936, 1.382, -1.944), 0.014, 6)
	body.tube("trim", Vector3(-0.822, 2.022, -1.27), Vector3(0.822, 2.022, -1.27), 0.012, 6)
	for side in [-1.0, 1.0]:
		body.tube("trim", Vector3(side * 0.936, 1.382, -1.944),
			Vector3(side * 0.822, 2.022, -1.27), 0.012, 6)
	for x in [-0.80, -0.08]:
		body.tube("trim", Vector3(x, 1.407, -1.917), Vector3(x + 0.56, 1.441, -1.879), 0.010, 5)
		body.tube("trim", Vector3(x + 0.07, 1.372, -1.96), Vector3(x + 0.23, 1.438, -1.884), 0.007, 4)
	for side in [-1.0, 1.0]:
		for k in 6:
			body.box("trim", Vector3(0.23, 0.005, 0.014), Vector3(side * 0.44, 1.350, -1.99 + k * 0.012))


static func _front(body: VehicleMesh.Builder) -> void:
	# Ранняя плоская решётка с двумя рядами прямоугольных ячеек и прямоугольными фарами.
	body.rbox("trim", Vector3(1.02, 0.25, 0.033), Vector3(0, 0.939, -2.629), 0.013)
	body.rbox("chrome", Vector3(1.035, 0.014, 0.014), Vector3(0, 1.063, -2.649), 0.004)
	body.rbox("chrome", Vector3(1.035, 0.014, 0.014), Vector3(0, 0.814, -2.649), 0.004)
	for k in range(-3, 4):
		body.box("chrome", Vector3(0.015, 0.246, 0.013), Vector3(k * 0.163, 0.939, -2.651))
	body.box("chrome", Vector3(1.02, 0.012, 0.013), Vector3(0, 0.939, -2.651))
	body.rbox("lens_red", Vector3(0.044, 0.059, 0.013), Vector3(0, 1.025, -2.663), 0.01)
	for side in [-1.0, 1.0]:
		var s: float = side
		body.rbox("trim", Vector3(0.329, 0.255, 0.035), Vector3(s * 0.704, 0.939, -2.611), 0.012)
		body.rbox("head", Vector3(0.295, 0.218, 0.018), Vector3(s * 0.704, 0.939, -2.635), 0.008)
		body.rbox("lens_amber", Vector3(0.089, 0.218, 0.025), Vector3(s * 0.924, 0.939, -2.628), 0.013)
		for k in 7:
			body.box("chrome", Vector3(0.003, 0.188, 0.002), Vector3(s * 0.704 + (k - 3.0) * 0.037, 0.939, -2.646))
	body.rbox("trim", Vector3(2.035, 0.225, 0.18), Vector3(0, 0.643, -2.645), 0.032)
	for side in [-1.0, 1.0]:
		body.rbox("trim", Vector3(0.155, 0.225, 0.30), Vector3(side * 0.94, 0.643, -2.48), 0.026)
	_plate(body, Vector3(0, 0.655, -2.731))
	for x in [-0.64, -0.25, 0.25, 0.64]:
		body.rbox("dark", Vector3(0.27, 0.062, 0.014), Vector3(x, 0.438, -2.620), 0.012)
	for side in [-1.0, 1.0]:
		var previous := Vector3(side * 0.756, 1.087, -2.61)
		for z in [-2.48, -2.30, -2.12, -1.96]:
			var at := Vector3(side * 0.756, VehicleMesh.profile(TOP, z) + 0.004, z)
			body.tube("trim", previous, at, 0.003, 4)
			previous = at


static func _rear(body: VehicleMesh.Builder, glass: VehicleMesh.Builder, windowed: bool) -> void:
	body.tube("trim", Vector3(0, 0.575, 2.632), Vector3(0, 2.077, 2.625), 0.004, 5)
	# Рельеф двух глухих распашных дверей, а не дверцы накладного промтоварного фургона.
	for side in [-1.0, 1.0]:
		var s: float = side
		if windowed:
			glass.pane("glass", Vector3(s * 0.10, 1.35, 2.624), Vector3(s * 0.79, 1.35, 2.624),
				Vector3(s * 0.79, 1.98, 2.624), Vector3(s * 0.10, 1.98, 2.624), Vector3.BACK, 0.006, 5, 3)
		else:
			body.rbox("paint", Vector3(0.69, 0.65, 0.014), Vector3(s * 0.445, 1.635, 2.624), 0.065)
		body.rbox("paint", Vector3(0.70, 0.26, 0.014), Vector3(s * 0.445, 0.825, 2.626), 0.035)
		body.tube("trim", Vector3(s * 0.84, 0.57, 2.636), Vector3(s * 0.84, 1.997, 2.626), 0.003, 4)
		for y in [0.78, 1.76]:
			body.rbox("steel", Vector3(0.118, 0.085, 0.035), Vector3(s * 0.856, y, 2.648), 0.009)
			body.tube("steel", Vector3(s * 0.865, y - 0.050, 2.674), Vector3(s * 0.865, y + 0.050, 2.674), 0.013, 8)
		body.rbox("trim", Vector3(0.13, 0.48, 0.035), Vector3(s * 0.936, 1.046, 2.613), 0.018)
		body.rbox("tail", Vector3(0.105, 0.432, 0.016), Vector3(s * 0.936, 1.046, 2.638), 0.012)
		body.box("lens_amber", Vector3(0.105, 0.085, 0.014), Vector3(s * 0.936, 1.080, 2.651))
		body.box("lens_white", Vector3(0.105, 0.055, 0.014), Vector3(s * 0.936, 0.999, 2.651))
		body.rbox("trim", Vector3(0.16, 0.18, 0.105), Vector3(s * 0.938, 0.455, 2.668), 0.018)
		body.box("tail", Vector3(0.105, 0.047, 0.012), Vector3(s * 0.81, 0.475, 2.682))
	_plate(body, Vector3(-0.435, 0.805, 2.646))
	for x in [-0.61, -0.26]:
		body.rbox("trim", Vector3(0.059, 0.022, 0.033), Vector3(x, 0.881, 2.66), 0.005)
	body.rbox("trim", Vector3(0.040, 0.137, 0.026), Vector3(0.073, 1.15, 2.645), 0.007)
	body.rbox("trim", Vector3(0.018, 0.025, 0.019), Vector3(0.073, 1.045, 2.648), 0.006)
	body.rbox("steel", Vector3(1.45, 0.065, 0.16), Vector3(0, 0.448, 2.655), 0.01)
	body.rbox("dark", Vector3(0.42, 0.087, 0.045), Vector3(0, 0.45, 2.70), 0.008)
	for x in [-0.15, -0.05, 0.05, 0.15]:
		body.box("steel", Vector3(0.012, 0.006, 0.105), Vector3(x, 0.487, 2.663))


static func _sides(body: VehicleMesh.Builder) -> void:
	for side in [-1.0, 1.0]:
		var s: float = side
		# Кабинная дверь заканчивается на той же оболочке, что и грузовой отсек.
		body.tube("trim", Vector3(s * 1.036, 0.347, -0.435), Vector3(s * 0.980, 1.31, -0.435), 0.003, 4)
		body.tube("trim", Vector3(s * 1.031, 0.35, -0.435), Vector3(s * 1.031, 0.35, -1.23), 0.003, 4)
		body.rbox("trim", Vector3(0.022, 0.034, 0.13), Vector3(s * 1.021, 1.18, -0.58), 0.006)
		body.rbox("lens_amber", Vector3(0.013, 0.035, 0.08), Vector3(s * 1.024, 1.218, -1.64), 0.005)
		var mirror := Vector3(s * 1.15, 1.495, -1.45)
		body.tube("trim", Vector3(s * 0.973, 1.35, -1.48), mirror + Vector3(0, -0.10, 0), 0.015, 6)
		body.tube("trim", Vector3(s * 0.945, 1.65, -1.35), mirror + Vector3(0, 0.10, 0), 0.015, 6)
		body.rbox("trim", Vector3(0.12, 0.285, 0.18), mirror, 0.028)
		body.rbox("lens_white", Vector3(0.094, 0.252, 0.009), mirror + Vector3(0, 0, 0.092), 0.018)
		body.tube("paint", Vector3(s * 1.035, 1.135, -1.84), Vector3(s * 1.035, 1.135, 2.55), 0.009, 5)
		for span in [[-1.23, 0.72], [1.64, 2.48]]:
			body.tube("paint", Vector3(s * 1.037, 0.65, span[0]), Vector3(s * 1.037, 0.65, span[1]), 0.010, 5)
		for axle in AXLES:
			body.box("dark", Vector3(0.01, 0.36, 0.78), Vector3(s * 0.58, 0.48, axle))
			body.box("rubber", Vector3(0.34, 0.23, 0.012), Vector3(s * 0.80, 0.25, axle + ARCH_RADIUS + 0.018))
			var previous := Vector3(s * 1.034, WHEEL_RADIUS, axle - ARCH_RADIUS)
			for k in range(1, 25):
				var angle := PI - PI * k / 24.0
				var at := Vector3(s * 1.034, WHEEL_RADIUS + sin(angle) * ARCH_RADIUS, axle + cos(angle) * ARCH_RADIUS)
				body.tube("paint", previous, at, 0.011, 5)
				previous = at
	# Сдвижная дверь только справа, без симметричной выдуманной двери слева.
	for z in [-0.37, 1.03]:
		body.tube("trim", Vector3(1.040, _bottom_at(z) + 0.02, z), Vector3(0.996, 2.025, z), 0.003, 4)
	body.tube("trim", Vector3(1.035, 0.34, -0.36), Vector3(1.035, 0.34, 0.78), 0.003, 4)
	body.rbox("trim", Vector3(0.022, 0.154, 0.042), Vector3(1.027, 1.285, 0.89), 0.006)
	body.rbox("steel", Vector3(0.021, 0.025, 1.48), Vector3(1.040, 1.197, 1.77), 0.005)
	body.rbox("trim", Vector3(0.022, 0.012, 1.44), Vector3(1.053, 1.199, 1.77), 0.003)
	# Бензобак в нижней левой панели за кабиной.
	var fuel := Vector3(-1.039, 0.85, -0.18)
	for dy in [-0.078, 0.078]:
		body.box("trim", Vector3(0.003, 0.006, 0.17), fuel + Vector3(0, dy, 0))
	for dz in [-0.085, 0.085]:
		body.box("trim", Vector3(0.003, 0.162, 0.006), fuel + Vector3(0, 0, dz))
	body.box("dark", Vector3(1.18, 0.05, 4.44), Vector3(0, 0.23, 0))
	body.tube("dark", Vector3(-0.70, 0.29, 0.60), Vector3(-0.95, 0.255, 0.72), 0.027, 10, true)


static func _bottom_at(z: float) -> float:
	var low := VehicleMesh.profile(BOTTOM, z)
	for axle in AXLES:
		var dz: float = z - axle
		if absf(dz) < ARCH_RADIUS:
			low = maxf(low, WHEEL_RADIUS + sqrt(ARCH_RADIUS * ARCH_RADIUS - dz * dz))
	return low


static func _cabin(cabin: VehicleMesh.Builder, windowed: bool) -> void:
	cabin.box("dark", Vector3(1.82, 0.02, 1.48), Vector3(0, 1.06, -1.18))
	cabin.rbox("dark", Vector3(1.79, 0.17, 0.29), Vector3(0, 1.365, -1.73), 0.028)
	if not windowed:
		cabin.box("dark", Vector3(1.87, 0.94, 0.04), Vector3(0, 1.61, -0.40))
	else:
		cabin.box("dark", Vector3(1.90, 0.035, 2.94), Vector3(0, 0.83, 1.04))
		for z in [0.13, 0.88, 1.66, 2.25]:
			for x in ([-0.48, 0.48] if z > 2.0 else [-0.66, -0.12, 0.62]):
				cabin.rbox("cloth", Vector3(0.43, 0.12, 0.43), Vector3(x, 1.02, z), 0.025)
				cabin.rbox("cloth", Vector3(0.43, 0.48, 0.12), Vector3(x, 1.30, z + 0.19), 0.025)
	for x in ([-0.48, 0.12] if windowed else [-0.48, 0.12, 0.63]):
		cabin.rbox("cloth", Vector3(0.46, 0.43, 0.14), Vector3(x, 1.40, -0.66), 0.034)
		cabin.rbox("cloth", Vector3(0.24, 0.15, 0.10), Vector3(x, 1.735, -0.65), 0.024)
	var center := Vector3(-0.48, 1.496, -1.40)
	var up := Vector3(0, 0.73, -0.68)
	for k in 20:
		var a := TAU * k / 20.0
		var next := TAU * (k + 1) / 20.0
		cabin.tube("trim", center + (Vector3.RIGHT * cos(a) + up * sin(a)) * 0.196,
			center + (Vector3.RIGHT * cos(next) + up * sin(next)) * 0.196, 0.013, 5)
	cabin.tube("trim", center - Vector3.RIGHT * 0.18, center + Vector3.RIGHT * 0.18, 0.014, 4)
	cabin.rbox("dark", Vector3(0.22, 0.06, 0.026), Vector3(0, 1.95, -1.24), 0.009)


static func _medical_interior() -> ArrayMesh:
	var found: ArrayMesh = VehicleMesh.cached("gazelle32214_interior")
	if found != null:
		return found
	# Ordinary-roof production shell with a simple unoccupied medical compartment.
	var cabin := VehicleMesh.Builder.new()
	_cabin(cabin, false)
	cabin.box("dark", Vector3(1.90, 0.035, 2.94), Vector3(0, 0.83, 1.04))
	cabin.rbox("cloth", Vector3(0.62, 0.10, 1.92), Vector3(-0.35, 1.02, 1.16), 0.035)
	for z in [0.42, 1.86]:
		cabin.box("steel", Vector3(0.50, 0.17, 0.035), Vector3(-0.35, 0.92, z))
	cabin.rbox("cloth", Vector3(0.37, 0.12, 1.36), Vector3(0.70, 1.03, 1.27), 0.025)
	cabin.rbox("cloth", Vector3(0.10, 0.40, 1.36), Vector3(0.87, 1.26, 1.27), 0.025)
	return VehicleMesh.store("gazelle32214_interior", VehicleMesh.finish(cabin))


static func _plate(body: VehicleMesh.Builder, at: Vector3) -> void:
	body.box("trim", Vector3(0.53, 0.123, 0.012), at)
	body.box("plate", Vector3(0.515, 0.109, 0.014), at + Vector3(0, 0, signf(at.z) * 0.006))


static func _plate_label(parent: Node3D, at: Vector3, yaw: float, text: String) -> void:
	var label := Label3D.new()
	label.name = "PlateText"
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.0016
	label.modulate = Color(0.05, 0.05, 0.05)
	label.outline_size = 0
	label.position = at
	label.rotation.y = yaw
	label.double_sided = false
	label.visibility_range_end = 30.0
	parent.add_child(label)


static func snow_mesh(depth: float) -> ArrayMesh:
	var d := maxf(0.02, snappedf(depth, 0.02))
	var key := "gazelle2705_snow_" + VehicleMesh.snf(d)
	var mesh: ArrayMesh = VehicleMesh.cached(key)
	if mesh != null:
		return mesh
	var snow := VehicleMesh.Builder.new()
	snow.pillow("snow", Vector3(0, 0, 0.71), 1.62, 3.49, d, 2.17, 2.18, 91, 11, 13)
	snow.pillow("snow", Vector3(0, 0, -2.26), 1.60, 0.58, d * 0.52, 1.10, 1.34, 92)
	mesh = VehicleMesh.finish(snow)
	return VehicleMesh.store(key, mesh)


# The sliding door is a state of the shared passenger shell. Split the existing
# triangles, preserving their normals/UVs; default closed meshes stay untouched.
static func _open_door_mesh(mesh: ArrayMesh) -> ArrayMesh:
	var builder := VehicleMesh.Builder.new()
	var materials := {}
	var slots: Array = mesh.get_meta("slots", [])
	for surface in mesh.get_surface_count():
		var slot: String = slots[surface]
		materials[slot] = mesh.surface_get_material(surface)
		var arrays: Array = mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index in positions.size():
				indices.append(index)
		for index in range(0, indices.size(), 3):
			var panel: Array = []
			for corner in 3:
				var vertex := indices[index + corner]
				panel.append([positions[vertex], normals[vertex], uvs[vertex], uv2s[vertex]])
			for plane in [[0, DOOR_INNER_X, true], [1, DOOR_BOTTOM, true],
				[1, DOOR_TOP, false], [2, DOOR_FRONT, true], [2, DOOR_REAR, false]]:
				var outside := _door_clip(panel, plane[0], plane[1], not plane[2])
				_door_polygon(builder, slot, outside, Vector3.ZERO)
				panel = _door_clip(panel, plane[0], plane[1], plane[2])
				if panel.size() < 3:
					break
			_door_polygon(builder, slot, panel, DOOR_SLIDE)
	return VehicleMesh.finish(builder, materials)


static func _door_clip(polygon: Array, axis: int, boundary: float, positive: bool) -> Array:
	var result: Array = []
	if polygon.is_empty():
		return result
	var previous: Array = polygon[-1]
	var previous_d: float = (previous[0][axis] - boundary) * (1.0 if positive else -1.0)
	var previous_inside := previous_d >= 0.0 if positive else previous_d > 0.0
	for vertex: Array in polygon:
		var distance: float = (vertex[0][axis] - boundary) * (1.0 if positive else -1.0)
		var inside := distance >= 0.0 if positive else distance > 0.0
		if inside != previous_inside:
			var weight := previous_d / (previous_d - distance)
			result.append([previous[0].lerp(vertex[0], weight), previous[1].lerp(vertex[1], weight).normalized(),
				previous[2].lerp(vertex[2], weight), previous[3].lerp(vertex[3], weight)])
		if inside:
			result.append(vertex)
		previous = vertex
		previous_d = distance
		previous_inside = inside
	return result


static func _door_polygon(builder: VehicleMesh.Builder, slot: String, polygon: Array, offset: Vector3) -> void:
	for index in range(1, polygon.size() - 1):
		var a: Array = polygon[0]
		var b: Array = polygon[index]
		var c: Array = polygon[index + 1]
		if (b[0] - a[0]).cross(c[0] - a[0]).length_squared() < 1.0e-20:
			continue
		builder.tri(slot, a[0] + offset, b[0] + offset, c[0] + offset,
			a[1], b[1], c[1], a[2], b[2], c[2], a[3])
