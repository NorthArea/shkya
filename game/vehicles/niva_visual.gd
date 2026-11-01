extends RefCounted
## ВАЗ-2121 до 1994 года: три двери, малая крышка задка и горизонтальные фонари.
## Собственная геометрия по фото https://www.zr.ru/content/articles/922713/ .
## Габариты 3740×1680×1640, база 2200: https://www.drom.ru/catalog/lada/2121_4x4_niva/309773/ .
## Только облик; перед −Z, колёса касаются y=0. SIZE не включает зеркала и снег.

const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")

const SIZE := Vector3(1.68, 1.64, 3.74)
const WHEEL_RADIUS := 0.347
const WHEELBASE := 2.20
const WHEEL_WIDTH := 0.175
const AXLES := [-1.165, 1.035]
const TRACK_HALF := [0.715, 0.70]
const HULL_LENGTH := 3.54
const HALF_WIDTH := 0.84
const ARCH_RADIUS := 0.412
const BELT := 1.07
const ROOF_Y := 1.64
const GLASS_HALF_WIDTH := 0.795
const ROOF_HALF_WIDTH := 0.705
const TOP := [[-1.77, 1.025], [-1.71, 1.065], [-1.50, 1.085], [-0.75, 1.095],
	[-0.65, BELT], [1.58, BELT], [1.67, 1.06], [1.77, 0.835]]
const BOTTOM := [[-1.77, 0.43], [-1.62, 0.34], [-0.7, 0.30], [1.55, 0.31], [1.77, 0.42]]


static func build(paint: Color, plate: String = "", snow_depth: float = 0.08) -> Node3D:
	var visual := Node3D.new()
	visual.name = "Visual"
	var body := Node3D.new()
	body.name = "Body"
	visual.add_child(body)
	var meshes := body_meshes()
	var paint_material: ShaderMaterial = VehicleMesh.paint(paint, 0.32, 0.8, clampf(snow_depth * 4.0, 0.0, 0.8), 0.58).duplicate()
	VehicleMesh.instance(body, "BodyMesh", meshes["body"], {"paint": paint_material})
	var glass := VehicleMesh.instance(body, "Glass", meshes["glass"], {}, false)
	glass.sorting_offset = -0.5
	var interior := VehicleMesh.instance(body, "Interior", meshes["interior"], {}, false)
	interior.visibility_range_end = 45.0
	if snow_depth > 0.0:
		VehicleMesh.instance(body, "Snow", snow_mesh(snow_depth))
	for spot in wheel_spots():
		var pivot := Node3D.new()
		pivot.name = "WheelPivot%d" % (visual.get_child_count() - 1)
		pivot.position = spot
		visual.add_child(pivot)
		var wheel := VehicleMesh.instance(pivot, "Wheel", wheel_mesh())
		wheel.rotation.z = PI * 0.5
		wheel.visibility_range_end = 120.0
	if not plate.is_empty():
		_plate_label(body, Vector3(0.0, 0.54, -1.874), PI, plate)
		_plate_label(body, Vector3(0.0, 0.665, 1.799), 0.0, plate)
	return visual


static func wheel_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for axle in AXLES.size():
		for side in [-1.0, 1.0]:
			spots.append(Vector3(side * TRACK_HALF[axle], WHEEL_RADIUS, AXLES[axle]))
	return spots


static func wheel_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = VehicleMesh.cached("niva2121_wheel")
	if mesh != null:
		return mesh
	var wheel := VehicleMesh.Builder.new()
	var hw := WHEEL_WIDTH * 0.5
	var rim := 0.206
	wheel.lathe("rubber", PackedVector2Array([
		Vector2(rim, -hw + 0.01), Vector2(WHEEL_RADIUS - 0.04, -hw),
		Vector2(WHEEL_RADIUS - 0.008, -hw + 0.02), Vector2(WHEEL_RADIUS, -hw * 0.44),
		Vector2(WHEEL_RADIUS, hw * 0.44), Vector2(WHEEL_RADIUS - 0.008, hw - 0.02),
		Vector2(WHEEL_RADIUS - 0.04, hw), Vector2(rim, hw - 0.01),
	]), 36, Vector3.ZERO, PackedInt32Array([3, 4]), 0.016)
	for side in [-1.0, 1.0]:
		var s: float = side
		wheel.lathe("alu", PackedVector2Array([
			Vector2(rim + 0.006, s * (hw - 0.013)), Vector2(rim * 0.90, s * (hw - 0.024)),
			Vector2(rim * 0.78, s * (hw - 0.036)), Vector2(rim * 0.50, s * (hw - 0.046)),
			Vector2(rim * 0.38, s * (hw - 0.028)), Vector2(0.001, s * (hw - 0.028)),
		]), 24, Vector3.ZERO)
		wheel.lathe("alu", PackedVector2Array([
			Vector2(0.061, s * (hw - 0.027)), Vector2(0.056, s * hw),
			Vector2(0.043, s * (hw + 0.012)), Vector2(0.001, s * (hw + 0.015)),
		]), 16, Vector3.ZERO)
		for k in 5:
			var angle := TAU * k / 5.0
			var bolt := Vector3(cos(angle) * 0.081, s * (hw - 0.029), sin(angle) * 0.081)
			wheel.box("chrome", Vector3(0.019, 0.021, 0.019), bolt)
			var vent_angle := angle + PI / 5.0
			var vent := Vector3(cos(vent_angle) * 0.148, s * (hw - 0.030), sin(vent_angle) * 0.148)
			var points := PackedVector3Array()
			for j in 10:
				var a := TAU * j / 10.0
				points.append(vent + Vector3(cos(a) * 0.026, 0.0, sin(a) * 0.026))
			wheel.poly("dark", points, Vector3.UP * s)
	mesh = VehicleMesh.finish(wheel)
	return VehicleMesh.store("niva2121_wheel", mesh)


static func body_meshes() -> Dictionary:
	var found: Variant = VehicleMesh.cached("niva2121_body")
	if found != null:
		return found
	var body := VehicleMesh.Builder.new()
	var glass := VehicleMesh.Builder.new()
	var interior := VehicleMesh.Builder.new()
	body.loft("paint", VehicleMesh.hull_stations(HULL_LENGTH, HALF_WIDTH, TOP, BOTTOM, AXLES,
		WHEEL_RADIUS, ARCH_RADIUS, 0.055, 0.055, 0.015, 0.025, 0.035, 0.10))
	_greenhouse(body, glass)
	_front(body)
	_rear(body)
	_sides(body)
	_cabin(interior)
	var meshes := {
		"body": VehicleMesh.finish(body, {"paint": VehicleMesh.paint(Color(0.76, 0.35, 0.15))}),
		"glass": VehicleMesh.finish(glass, {"glass": VehicleMesh.glass(0.035)}),
		"interior": VehicleMesh.finish(interior),
	}
	return VehicleMesh.store("niva2121_body", meshes)


static func _greenhouse(body: VehicleMesh.Builder, glass: VehicleMesh.Builder) -> void:
	body.loft("paint", [
		[-0.41, 1.545, 1.60, 0.697, 0.674, 0.012, 0.034],
		[-0.34, 1.545, ROOF_Y - 0.008, 0.719, 0.695, 0.012, 0.052],
		[0.47, 1.545, ROOF_Y, 0.723, 0.698, 0.012, 0.055],
		[1.26, 1.545, ROOF_Y - 0.01, 0.719, 0.695, 0.012, 0.052],
		[1.39, 1.535, 1.59, 0.699, 0.674, 0.012, 0.034],
	], true, 3)
	for side in [-1.0, 1.0]:
		var s: float = side
		var outward := Vector3(s, 0.19, 0.0).normalized()
		var a0 := Vector3(s * GLASS_HALF_WIDTH, BELT, -0.745)
		var a1 := Vector3(s * ROOF_HALF_WIDTH, 1.565, -0.365)
		body.tube("paint", a0, a1, 0.029, 6)
		body.tube("trim", a0 + Vector3(s * 0.006, 0.01, 0.025),
			a1 + Vector3(s * 0.006, -0.005, 0.025), 0.009, 4)
		# Один длинный дверной проём; позади него — неподвижное боковое стекло.
		body.poly("paint", PackedVector3Array([
			Vector3(s * GLASS_HALF_WIDTH, BELT, 0.315), Vector3(s * GLASS_HALF_WIDTH, BELT, 0.388),
			Vector3(s * ROOF_HALF_WIDTH, 1.55, 0.388), Vector3(s * ROOF_HALF_WIDTH, 1.55, 0.315),
		]), outward, true)
		body.poly("paint", PackedVector3Array([
			Vector3(s * GLASS_HALF_WIDTH, BELT, 1.47), Vector3(s * GLASS_HALF_WIDTH, 0.835, 1.778),
			Vector3(s * GLASS_HALF_WIDTH, 1.10, 1.719),
			Vector3(s * ROOF_HALF_WIDTH, 1.55, 1.385), Vector3(s * ROOF_HALF_WIDTH, 1.55, 1.26),
		]), outward, true)
		glass.pane("glass", Vector3(s * GLASS_HALF_WIDTH, BELT + 0.012, -0.695),
			Vector3(s * GLASS_HALF_WIDTH, BELT + 0.012, 0.319),
			Vector3(s * ROOF_HALF_WIDTH, 1.545, 0.319), Vector3(s * ROOF_HALF_WIDTH, 1.545, -0.326),
			outward, 0.0, 3, 2)
		glass.pane("glass", Vector3(s * GLASS_HALF_WIDTH, BELT + 0.012, 0.386),
			Vector3(s * GLASS_HALF_WIDTH, BELT + 0.012, 1.478),
			Vector3(s * ROOF_HALF_WIDTH, 1.545, 1.263), Vector3(s * ROOF_HALF_WIDTH, 1.545, 0.386),
			outward, 0.0, 3, 2)
		body.tube("chrome", Vector3(s * (GLASS_HALF_WIDTH + 0.004), BELT + 0.014, -0.454),
			Vector3(s * (ROOF_HALF_WIDTH + 0.004), 1.535, -0.218), 0.007, 4)
		body.tube("chrome", Vector3(s * 0.803, BELT + 0.005, -0.706),
			Vector3(s * 0.803, BELT + 0.005, 1.46), 0.007, 4)
		body.tube("chrome", Vector3(s * 0.733, 1.574, -0.385),
			Vector3(s * 0.733, 1.574, 1.37), 0.01, 5)
		# Штатные три вытяжные прорези за задним боковым стеклом.
		for k in 3:
			var y := 1.23 + k * 0.063
			var t := (y - BELT) / (1.55 - BELT)
			var x := lerpf(GLASS_HALF_WIDTH, ROOF_HALF_WIDTH, t) + 0.003
			var z := lerpf(1.47, 1.26, t) + 0.055
			body.box("trim", Vector3(0.008, 0.043, 0.015), Vector3(s * x, y, z))
	var front_out := Vector3(0.0, 0.38, -0.49).normalized()
	glass.pane("glass", Vector3(-0.76, 1.095, -0.744), Vector3(0.76, 1.095, -0.744),
		Vector3(0.677, 1.562, -0.378), Vector3(-0.677, 1.562, -0.378), front_out, 0.018, 6, 3)
	# Маленькая крышка ранней 2121 заканчивается над фонарями, её нижняя часть наклонна.
	body.poly("paint", PackedVector3Array([
		Vector3(-0.76, 0.835, 1.778), Vector3(0.76, 0.835, 1.778),
		Vector3(0.765, 1.105, 1.675), Vector3(-0.765, 1.105, 1.675),
	]), Vector3(0.0, 0.36, 0.94))
	var rear_out := Vector3(0.0, 0.30, 0.47).normalized()
	glass.pane("glass", Vector3(-0.697, 1.105, 1.683), Vector3(0.697, 1.105, 1.683),
		Vector3(0.645, 1.535, 1.391), Vector3(-0.645, 1.535, 1.391), rear_out, 0.012, 6, 3)
	body.poly("paint", PackedVector3Array([
		Vector3(-0.705, 1.535, 1.39), Vector3(0.705, 1.535, 1.39),
		Vector3(0.69, 1.57, 1.378), Vector3(-0.69, 1.57, 1.378),
	]), rear_out)
	for side in [-1.0, 1.0]:
		body.poly("paint", PackedVector3Array([
			Vector3(side * 0.697, 1.105, 1.683), Vector3(side * GLASS_HALF_WIDTH, 1.10, 1.719),
			Vector3(side * 0.705, 1.55, 1.385), Vector3(side * 0.645, 1.535, 1.391),
		]), rear_out, true)
		body.tube("trim", Vector3(side * 0.759, 0.84, 1.787),
			Vector3(side * 0.768, 1.10, 1.689), 0.0035, 4)
	for edge in [
		[Vector3(-0.76, 1.095, -0.75), Vector3(0.76, 1.095, -0.75)],
		[Vector3(-0.677, 1.562, -0.382), Vector3(0.677, 1.562, -0.382)],
		[Vector3(-0.697, 1.105, 1.69), Vector3(0.697, 1.105, 1.69)],
	]:
		body.tube("trim", edge[0], edge[1], 0.009, 5)


static func _front(body: VehicleMesh.Builder) -> void:
	# Две фары и решётка образуют одну невысокую чёрную маску.
	body.rbox("chrome", Vector3(1.53, 0.31, 0.018), Vector3(0.0, 0.815, -1.775), 0.018)
	body.rbox("trim", Vector3(1.49, 0.28, 0.022), Vector3(0.0, 0.815, -1.789), 0.015)
	for k in 7:
		body.box("trim", Vector3(0.97, 0.010, 0.025), Vector3(0.0, 0.705 + k * 0.036, -1.807))
		if k < 6:
			body.box("dark", Vector3(0.97, 0.017, 0.003), Vector3(0.0, 0.723 + k * 0.036, -1.822))
	for side in [-1.0, 1.0]:
		_disc(body, "chrome", Vector3(side * 0.615, 0.815, -1.813), 0.121, true)
		_disc(body, "lens_white", Vector3(side * 0.615, 0.815, -1.824), 0.105)
		body.rbox("trim", Vector3(0.231, 0.10, 0.024), Vector3(side * 0.63, 1.003, -1.77), 0.013)
		body.box("lens_amber", Vector3(0.137, 0.066, 0.014), Vector3(side * 0.659, 1.003, -1.789))
		body.box("lens_white", Vector3(0.052, 0.066, 0.015), Vector3(side * 0.558, 1.003, -1.789))
	_bumper(body, -1.0)
	_plate(body, Vector3(0.0, 0.54, -1.857))
	# Воздухозаборник у основания лобового и две короткие щётки.
	for side in [-1.0, 1.0]:
		for k in 6:
			body.box("trim", Vector3(0.20, 0.005, 0.012), Vector3(side * 0.43, 1.098, -0.91 + k * 0.021))
	for x in [-0.59, -0.02]:
		body.tube("trim", Vector3(x, 1.115, -0.727), Vector3(x + 0.44, 1.135, -0.711), 0.008, 4)
		body.tube("trim", Vector3(x + 0.04, 1.101, -0.76), Vector3(x + 0.18, 1.132, -0.715), 0.006, 4)


static func _rear(body: VehicleMesh.Builder) -> void:
	_bumper(body, 1.0)
	_plate(body, Vector3(0.0, 0.665, 1.782))
	for side in [-1.0, 1.0]:
		body.rbox("chrome", Vector3(0.43, 0.17, 0.018), Vector3(side * 0.544, 0.67, 1.774), 0.009)
		body.box("lens_red", Vector3(0.245, 0.137, 0.014), Vector3(side * 0.51, 0.67, 1.79))
		body.box("lens_amber", Vector3(0.092, 0.137, 0.015), Vector3(side * 0.696, 0.67, 1.79))
		body.box("lens_white", Vector3(0.088, 0.043, 0.016), Vector3(side * 0.46, 0.665, 1.794))
		body.box("trim", Vector3(0.045, 0.15, 0.021), Vector3(side * 0.314, 0.67, 1.788))
		body.rbox("chrome", Vector3(0.13, 0.016, 0.028), Vector3(side * 0.52, 1.591, 1.384), 0.005)
	body.tube("trim", Vector3(-0.756, 0.835, 1.784), Vector3(0.756, 0.835, 1.784), 0.004, 4)
	body.rbox("chrome", Vector3(0.095, 0.028, 0.023), Vector3(0.0, 0.89, 1.765), 0.008)
	body.rbox("trim", Vector3(0.024, 0.034, 0.016), Vector3(0.0, 0.865, 1.779), 0.005)
	body.tube("dark", Vector3(-0.48, 0.28, 1.63), Vector3(-0.48, 0.27, 1.82), 0.025, 8, true)


static func _bumper(body: VehicleMesh.Builder, end: float) -> void:
	body.rbox("alu", Vector3(1.59, 0.107, 0.093), Vector3(0.0, 0.49, end * 1.815), 0.019)
	body.rbox("trim", Vector3(1.49, 0.029, 0.011), Vector3(0.0, 0.501, end * 1.864), 0.004)
	for side in [-1.0, 1.0]:
		body.rbox("trim", Vector3(0.17, 0.13, 0.14), Vector3(side * 0.743, 0.489, end * 1.80), 0.015)
		body.box("dark", Vector3(0.055, 0.04, 0.12), Vector3(side * 0.49, 0.46, end * 1.72))


static func _plate(body: VehicleMesh.Builder, at: Vector3) -> void:
	body.box("trim", Vector3(0.53, 0.123, 0.012), at)
	body.box("plate", Vector3(0.515, 0.109, 0.014), at + Vector3(0.0, 0.0, signf(at.z) * 0.006))


static func _sides(body: VehicleMesh.Builder) -> void:
	for side in [-1.0, 1.0]:
		var s: float = side
		# Две боковые двери, без ложных швов задней пассажирской двери.
		for z in [-0.71, 0.35]:
			var low := _bottom_at(z) + 0.02
			body.tube("trim", Vector3(s * 0.837, low, z), Vector3(s * 0.832, BELT - 0.015, z), 0.003, 4)
		body.tube("trim", Vector3(s * 0.837, 0.324, -0.68), Vector3(s * 0.837, 0.324, 0.35), 0.003, 4)
		body.rbox("chrome", Vector3(0.016, 0.034, 0.123), Vector3(s * 0.832, 0.981, 0.205), 0.007)
		body.box("trim", Vector3(0.018, 0.018, 0.081), Vector3(s * 0.831, 0.979, 0.205))
		body.tube("paint", Vector3(s * 0.834, 0.934, -1.62), Vector3(s * 0.834, 0.934, 1.62), 0.006, 4)
		body.rbox("lens_amber", Vector3(0.012, 0.032, 0.063), Vector3(s * 0.834, 1.001, -1.47), 0.004)
		var mirror := Vector3(s * 0.91, 1.145, -0.535)
		body.tube("chrome", Vector3(s * 0.81, 1.105, -0.55), mirror, 0.010, 4)
		body.rbox("chrome", Vector3(0.064, 0.10, 0.137), mirror, 0.012)
		body.box("trim", Vector3(0.06, 0.091, 0.012), mirror + Vector3(0.0, 0.0, 0.065))
		body.box("lens_white", Vector3(0.052, 0.081, 0.013), mirror + Vector3(0.0, 0.0, 0.071))
		for axle in AXLES:
			body.box("dark", Vector3(0.008, 0.37, 0.77), Vector3(s * 0.60, 0.48, axle))
			body.box("rubber", Vector3(0.18, 0.20, 0.013), Vector3(s * 0.715, 0.26, axle + ARCH_RADIUS + 0.02))
		# Узкая отбортовка арок повторяет вырез, не расширяет кузов накладкой Urban.
		for axle in AXLES:
			var previous := Vector3(s * 0.831, WHEEL_RADIUS, axle - ARCH_RADIUS)
			for k in range(1, 19):
				var angle := PI - PI * k / 18.0
				var current := Vector3(s * 0.831, WHEEL_RADIUS + sin(angle) * ARCH_RADIUS,
					axle + cos(angle) * ARCH_RADIUS)
				body.tube("paint", previous, current, 0.009, 4)
				previous = current
	# Бензобак у правого заднего крыла: тонкий шов, панель в цвет кузова.
	var fuel := Vector3(0.838, 0.901, 1.08)
	for dy in [-0.064, 0.064]:
		body.box("trim", Vector3(0.004, 0.003, 0.12), fuel + Vector3(0, dy, 0))
	for dz in [-0.06, 0.06]:
		body.box("trim", Vector3(0.004, 0.128, 0.003), fuel + Vector3(0, 0, dz))
	body.box("dark", Vector3(1.16, 0.055, 2.78), Vector3(0.0, 0.25, 0.0))


static func _bottom_at(z: float) -> float:
	var low := VehicleMesh.profile(BOTTOM, z)
	for axle in AXLES:
		var dz: float = z - axle
		if absf(dz) < ARCH_RADIUS:
			low = maxf(low, WHEEL_RADIUS + sqrt(ARCH_RADIUS * ARCH_RADIUS - dz * dz))
	return low


static func _cabin(cabin: VehicleMesh.Builder) -> void:
	cabin.box("dark", Vector3(1.49, 0.01, 2.31), Vector3(0.0, BELT + 0.005, 0.49))
	cabin.rbox("dark", Vector3(1.43, 0.13, 0.24), Vector3(0.0, 1.12, -0.56), 0.025)
	for side in [-1.0, 1.0]:
		cabin.rbox("cloth", Vector3(0.47, 0.255, 0.11), Vector3(side * 0.36, 1.165, 0.23), 0.033)
	cabin.rbox("cloth", Vector3(1.28, 0.13, 0.14), Vector3(0.0, 1.12, 1.18), 0.025)
	var center := Vector3(-0.36, 1.19, -0.28)
	var up := Vector3(0.0, 0.85, -0.53)
	for k in 12:
		var a := TAU * k / 12.0
		var next := TAU * (k + 1) / 12.0
		cabin.tube("trim", center + (Vector3.RIGHT * cos(a) + up * sin(a)) * 0.17,
			center + (Vector3.RIGHT * cos(next) + up * sin(next)) * 0.17, 0.012, 4)
	cabin.tube("trim", center - Vector3.RIGHT * 0.16, center + Vector3.RIGHT * 0.16, 0.011, 4)
	cabin.rbox("dark", Vector3(0.19, 0.055, 0.024), Vector3(0.0, 1.50, -0.32), 0.008)


static func _disc(body: VehicleMesh.Builder, slot: String, at: Vector3, radius: float, ring := false) -> void:
	var keep := body.xf
	body.xf = keep * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at)
	if ring:
		body.lathe(slot, PackedVector2Array([Vector2(radius * 0.86, 0.004), Vector2(radius, 0.0),
			Vector2(radius, -0.008)]), 20, Vector3.ZERO)
	else:
		body.lathe(slot, PackedVector2Array([Vector2(radius, 0.0), Vector2(radius * 0.72, 0.01),
			Vector2(0.001, 0.014)]), 20, Vector3.ZERO)
	body.xf = keep


static func snow_mesh(depth: float) -> ArrayMesh:
	var d := maxf(0.02, snappedf(depth, 0.02))
	var key := "niva2121_snow_" + VehicleMesh.snf(d)
	var mesh: ArrayMesh = VehicleMesh.cached(key)
	if mesh != null:
		return mesh
	var snow := VehicleMesh.Builder.new()
	snow.pillow("snow", Vector3(0.0, 0.0, 0.47), 1.31, 1.64, d, 1.633, 1.631, 41)
	snow.pillow("snow", Vector3(0.0, 0.0, -1.23), 1.43, 0.84, d * 0.62, 1.077, 1.096, 42)
	snow.pillow("snow", Vector3(0.0, 0.0, -0.78), 1.37, 0.10, d * 0.63, 1.097, 1.10, 43, 7, 3)
	mesh = VehicleMesh.finish(snow)
	return VehicleMesh.store(key, mesh)


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
