extends RefCounted
## ГАЗ-3110: собственная геометрия раннего седана с узкими чёрными бамперами.
## Габариты — заводское3110-3902008 РЭ1998 (Dimensions); панельная схема «За рулём»,2010:
## https://gaz-3110.ru/docs/volga-gaz-3110.pdf .
## Фото формы: https://1cars.org/uploads/posts/2015-06/1433406336_gaz-3110-10.jpg
## и https://dar-web.ru/images/gaz/old/g3110_2.jpg ; фотографии в модель не включены.
## Размеры/оси по схеме; радиус вычислен из 195/65 R15. Панели/салон — приближение по фото.
## Только облик: перед −Z, колёса касаются y=0. SIZE исключает зеркала и снег.

const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")

const Dimensions = preload("res://game/vehicles/vehicle_dimensions.gd")
const SPEC: Dictionary = Dimensions.SPECS[&"gaz3110"]
const SIZE := Vector3(SPEC["width_m"], SPEC["height_m"], SPEC["length_m"])
const WHEELBASE: float = SPEC["wheelbase_m"]
const WHEEL_RADIUS := 0.31725
const WHEEL_WIDTH := 0.195
const AXLES := [-1.551, 1.249]
const TRACK_HALF := [SPEC["front_track_m"] * 0.5, SPEC["rear_track_m"] * 0.5]
const HULL_LENGTH := 4.70
const HALF_WIDTH: float = SPEC["width_m"] * 0.5
const ARCH_RADIUS := 0.371
const BELT := 0.992
const ROOF_Y: float = SPEC["height_m"]
const ROOF_RISE := ROOF_Y - 1.422
const GLASS_HALF_WIDTH := 0.823
const ROOF_HALF_WIDTH := 0.716
const TOP := [[-2.35, 0.87], [-2.30, 0.94], [-2.12, 0.984], [-1.61, 1.016],
	[-1.06, 1.034], [-0.92, BELT], [1.47, BELT], [1.88, 0.98], [2.22, 0.945], [2.35, 0.847]]
const BOTTOM := [[-2.35, 0.39], [-2.05, 0.29], [-0.96, 0.245], [1.90, 0.25], [2.35, 0.37]]


static func build(paint: Color, plate: String = "", snow_depth: float = 0.08) -> Node3D:
	var visual := Node3D.new()
	visual.name = "Visual"
	var body := Node3D.new()
	body.name = "Body"
	visual.add_child(body)
	var meshes := body_meshes()
	# Overrides belong to this instance; changing its paint must not recolour the shared mesh.
	var paint_material: ShaderMaterial = VehicleMesh.paint(paint, 0.18, 0.62,
		clampf(snow_depth * 3.0, 0.0, 0.7), 0.65).duplicate()
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
		_plate_label(body, Vector3(0.0, 0.565, -2.448), PI, plate)
		_plate_label(body, Vector3(0.0, 0.746, 2.374), 0.0, plate)
	return visual


static func wheel_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for axle in AXLES.size():
		for side in [-1.0, 1.0]:
			spots.append(Vector3(side * TRACK_HALF[axle], WHEEL_RADIUS, AXLES[axle]))
	return spots


static func wheel_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = VehicleMesh.cached("gaz3110_wheel")
	if mesh != null:
		return mesh
	var wheel := VehicleMesh.Builder.new()
	var hw := WHEEL_WIDTH * 0.5
	var rim := 0.1905
	wheel.lathe("rubber", PackedVector2Array([
		Vector2(rim, -hw + 0.012), Vector2(WHEEL_RADIUS - 0.032, -hw),
		Vector2(WHEEL_RADIUS - 0.006, -hw + 0.018), Vector2(WHEEL_RADIUS, -hw * 0.48),
		Vector2(WHEEL_RADIUS, hw * 0.48), Vector2(WHEEL_RADIUS - 0.006, hw - 0.018),
		Vector2(WHEEL_RADIUS - 0.032, hw), Vector2(rim, hw - 0.012),
	]), 48, Vector3.ZERO, PackedInt32Array([3, 4]), 0.009)
	for side in [-1.0, 1.0]:
		var s: float = side
		wheel.lathe("steel", PackedVector2Array([
			Vector2(rim + 0.006, s * (hw - 0.014)), Vector2(rim * 0.93, s * (hw - 0.020)),
			Vector2(rim * 0.78, s * (hw - 0.034)), Vector2(rim * 0.49, s * (hw - 0.041)),
			Vector2(0.001, s * (hw - 0.024)),
		]), 40, Vector3.ZERO)
		# Штатный светлый колпак с радиальными окнами и пятью креплениями.
		wheel.lathe("alu", PackedVector2Array([
			Vector2(rim * 0.91, s * (hw - 0.015)), Vector2(rim * 0.79, s * (hw - 0.002)),
			Vector2(rim * 0.44, s * (hw + 0.004)), Vector2(0.001, s * (hw + 0.012)),
		]), 40, Vector3.ZERO)
		for k in 10:
			var angle := TAU * k / 10.0
			var at := Vector3(cos(angle) * 0.134, s * (hw + 0.001), sin(angle) * 0.134)
			var points := PackedVector3Array()
			for j in 12:
				var a := TAU * j / 12.0
				points.append(at + Vector3(cos(a) * 0.014, 0.0, sin(a) * 0.014))
			wheel.poly("dark", points, Vector3.UP * s)
		for k in 5:
			var angle := TAU * k / 5.0
			wheel.box("chrome", Vector3(0.017, 0.010, 0.017),
				Vector3(cos(angle) * 0.055, s * (hw + 0.012), sin(angle) * 0.055))
	mesh = VehicleMesh.finish(wheel)
	return VehicleMesh.store("gaz3110_wheel", mesh)


static func body_meshes() -> Dictionary:
	var found: Variant = VehicleMesh.cached("gaz3110_body")
	if found != null:
		return found
	var body := VehicleMesh.Builder.new()
	var glass := VehicleMesh.Builder.new()
	var interior := VehicleMesh.Builder.new()
	body.loft("paint", VehicleMesh.hull_stations(HULL_LENGTH, HALF_WIDTH, TOP, BOTTOM,
		AXLES, WHEEL_RADIUS, ARCH_RADIUS, 0.18, 0.18, 0.045, 0.045, 0.105, 0.075))
	_greenhouse(body, glass)
	_front(body)
	_rear(body)
	_sides(body)
	_cabin(interior)
	var meshes := {
		"body": VehicleMesh.finish(body, {"paint": VehicleMesh.paint(Color(0.72, 0.75, 0.72)),
			"head": VehicleMesh.mat("lens_white"), "tail": VehicleMesh.mat("lens_red")}),
		"glass": VehicleMesh.finish(glass, {"glass": VehicleMesh.glass(0.018)}),
		"interior": VehicleMesh.finish(interior),
	}
	return VehicleMesh.store("gaz3110_body", meshes)


static func _greenhouse(body: VehicleMesh.Builder, glass: VehicleMesh.Builder) -> void:
	body.loft("paint", [
		[-0.60, 1.350 + ROOF_RISE, 1.385 + ROOF_RISE, 0.708, 0.690, 0.012, 0.025],
		[-0.49, 1.350 + ROOF_RISE, 1.412 + ROOF_RISE, 0.730, 0.705, 0.015, 0.050],
		[0.10, 1.352 + ROOF_RISE, ROOF_Y, 0.736, 0.711, 0.015, 0.055],
		[0.64, 1.350 + ROOF_RISE, 1.413 + ROOF_RISE, 0.727, 0.702, 0.015, 0.050],
		[0.79, 1.344 + ROOF_RISE, 1.382 + ROOF_RISE, 0.699, 0.678, 0.012, 0.025],
	], true, 4)
	for side in [-1.0, 1.0]:
		var s: float = side
		var outward := Vector3(s, 0.28, 0.0).normalized()
		var a_bottom := Vector3(s * GLASS_HALF_WIDTH, BELT, -0.965)
		var a_top := Vector3(s * ROOF_HALF_WIDTH, 1.365 + ROOF_RISE, -0.555)
		body.tube("paint", a_bottom, a_top, 0.034, 8)
		body.tube("chrome", a_bottom + Vector3(s * 0.005, 0.012, 0.024),
			a_top + Vector3(s * 0.005, 0.0, 0.022), 0.008, 5)
		# Стойка B разделяет именно переднюю и заднюю двери, а не длинное окно купе.
		body.poly("paint", PackedVector3Array([
			Vector3(s * GLASS_HALF_WIDTH, BELT, 0.065), Vector3(s * GLASS_HALF_WIDTH, BELT, 0.145),
			Vector3(s * ROOF_HALF_WIDTH, 1.36 + ROOF_RISE, 0.145), Vector3(s * ROOF_HALF_WIDTH, 1.36 + ROOF_RISE, 0.065),
		]), outward, true)
		body.poly("paint", PackedVector3Array([
			Vector3(s * GLASS_HALF_WIDTH, BELT, 1.14), Vector3(s * 0.845, BELT, 1.51),
			Vector3(s * 0.697, 1.36 + ROOF_RISE, 0.78), Vector3(s * ROOF_HALF_WIDTH, 1.36 + ROOF_RISE, 0.66),
		]), outward, true)
		glass.pane("glass", Vector3(s * GLASS_HALF_WIDTH, BELT + 0.012, -0.915),
			Vector3(s * GLASS_HALF_WIDTH, BELT + 0.012, 0.067),
			Vector3(s * ROOF_HALF_WIDTH, 1.353 + ROOF_RISE, 0.067), Vector3(s * ROOF_HALF_WIDTH, 1.353 + ROOF_RISE, -0.518),
			outward, 0.005, 5, 3)
		glass.pane("glass", Vector3(s * GLASS_HALF_WIDTH, BELT + 0.012, 0.143),
			Vector3(s * GLASS_HALF_WIDTH, BELT + 0.012, 1.142),
			Vector3(s * ROOF_HALF_WIDTH, 1.353 + ROOF_RISE, 0.658), Vector3(s * ROOF_HALF_WIDTH, 1.353 + ROOF_RISE, 0.143),
			outward, 0.004, 5, 3)
		# Неподвижная треугольная форточка в задней двери.
		body.tube("chrome", Vector3(s * 0.828, BELT + 0.01, 0.945),
			Vector3(s * 0.72, 1.352 + ROOF_RISE, 0.555), 0.008, 5)
		body.tube("chrome", Vector3(s * 0.831, BELT + 0.003, -0.94),
			Vector3(s * 0.831, BELT + 0.003, 1.145), 0.008, 5)
		body.tube("chrome", Vector3(s * 0.73, 1.379 + ROOF_RISE, -0.55),
			Vector3(s * 0.73, 1.379 + ROOF_RISE, 0.70), 0.008, 5)
	var front_out := Vector3(0.0, 0.43, -0.37).normalized()
	glass.pane("glass", Vector3(-0.785, 1.027, -0.953), Vector3(0.785, 1.027, -0.953),
		Vector3(0.682, 1.351 + ROOF_RISE, -0.565), Vector3(-0.682, 1.351 + ROOF_RISE, -0.565), front_out, 0.022, 8, 3)
	var rear_out := Vector3(0.0, 0.65, 0.37).normalized()
	glass.pane("glass", Vector3(-0.78, 1.014, 1.45), Vector3(0.78, 1.014, 1.45),
		Vector3(0.66, 1.352 + ROOF_RISE, 0.80), Vector3(-0.66, 1.352 + ROOF_RISE, 0.80), rear_out, 0.016, 8, 3)
	for side in [-1.0, 1.0]:
		body.poly("paint", PackedVector3Array([
			Vector3(side * 0.78, 1.014, 1.45), Vector3(side * 0.845, BELT, 1.51),
			Vector3(side * 0.697, 1.36 + ROOF_RISE, 0.78), Vector3(side * 0.66, 1.352 + ROOF_RISE, 0.80),
		]), rear_out, true)
	for edge in [
		[Vector3(-0.79, 1.026, -0.965), Vector3(0.79, 1.026, -0.965)],
		[Vector3(-0.684, 1.36 + ROOF_RISE, -0.569), Vector3(0.684, 1.36 + ROOF_RISE, -0.569)],
		[Vector3(-0.78, 1.018, 1.458), Vector3(0.78, 1.018, 1.458)],
	]:
		body.tube("trim", edge[0], edge[1], 0.010, 6)


static func _front(body: VehicleMesh.Builder) -> void:
	# Хромированный скруглённый трапециевидный обод, два поля тонких вертикальных рёбер.
	var outline := PackedVector3Array([
		Vector3(-0.405, 0.912, -2.354), Vector3(0.405, 0.912, -2.354),
		Vector3(0.385, 0.764, -2.374), Vector3(0.325, 0.720, -2.378),
		Vector3(-0.325, 0.720, -2.378), Vector3(-0.385, 0.764, -2.374),
	])
	body.poly("trim", outline, Vector3.FORWARD)
	for k in outline.size():
		body.tube("chrome", outline[k], outline[(k + 1) % outline.size()], 0.015, 8)
	for k in range(-15, 16):
		var x := k * 0.023
		var low := 0.737 + pow(absf(x) / 0.36, 4.0) * 0.033
		body.tube("steel", Vector3(x, low, -2.381), Vector3(x, 0.895, -2.364), 0.004, 4)
	body.rbox("chrome", Vector3(0.036, 0.177, 0.023), Vector3(0.0, 0.817, -2.389), 0.008)
	body.rbox("lens_red", Vector3(0.032, 0.045, 0.008), Vector3(0.0, 0.872, -2.404), 0.007)
	for side in [-1.0, 1.0]:
		var s: float = side
		body.rbox("chrome", Vector3(0.366, 0.216, 0.035), Vector3(s * 0.614, 0.813, -2.336), 0.024)
		body.rbox("head", Vector3(0.305, 0.178, 0.021), Vector3(s * 0.602, 0.813, -2.358), 0.017)
		body.rbox("lens_amber", Vector3(0.080, 0.177, 0.037), Vector3(s * 0.80, 0.812, -2.334), 0.018)
		for k in 8:
			body.box("chrome", Vector3(0.003, 0.151, 0.002), Vector3(s * 0.603 + (k - 3.5) * 0.033, 0.813, -2.371))
	_bumper(body, -1.0)
	_plate(body, Vector3(0.0, 0.565, -2.431))
	for x in [-0.37, 0.0, 0.37]:
		body.rbox("trim", Vector3(0.29, 0.057, 0.016), Vector3(x, 0.407, -2.347), 0.016)
	# Швы отделяют широкий собственный капот от закруглённых передних крыльев.
	for side in [-1.0, 1.0]:
		var previous := Vector3(side * 0.607, 0.938, -2.29)
		for z in [-2.12, -1.90, -1.61, -1.30, -1.06]:
			var at := Vector3(side * 0.607, VehicleMesh.profile(TOP, z) + 0.004, z)
			body.tube("trim", previous, at, 0.0028, 4)
			previous = at
	for x in [-0.62, -0.02]:
		body.tube("trim", Vector3(x, 1.046, -0.955), Vector3(x + 0.43, 1.072, -0.91), 0.008, 4)
		body.tube("trim", Vector3(x + 0.05, 1.037, -1.005), Vector3(x + 0.19, 1.069, -0.916), 0.006, 4)


static func _rear(body: VehicleMesh.Builder) -> void:
	_bumper(body, 1.0)
	body.rbox("trim", Vector3(0.72, 0.211, 0.027), Vector3(0.0, 0.748, 2.35), 0.019)
	_plate(body, Vector3(0.0, 0.746, 2.357))
	for side in [-1.0, 1.0]:
		var s: float = side
		# Каждая половина фонаря пересечена вертикальным швом крышки багажника.
		_rear_strip(body, "trim", s, 0.393, 0.86, 0.647, 0.86, 0.012)
		_rear_strip(body, "tail", s, 0.405, 0.85, 0.66, 0.847, 0.018)
		_rear_strip(body, "lens_amber", s, 0.707, 0.844, 0.778, 0.835, 0.021)
		_rear_strip(body, "trim", s, 0.418, 0.842, 0.697, 0.757, 0.024)
		_rear_strip(body, "lens_white", s, 0.432, 0.588, 0.707, 0.744, 0.026)
		var seam_z := _rear_z(0.75) + 0.030
		body.tube("trim", Vector3(s * 0.75, 0.645, seam_z), Vector3(s * 0.75, 0.862, seam_z), 0.004, 5)
		var previous := Vector3(s * 0.75, 0.865, _rear_z(0.75) + 0.020)
		for z in [2.22, 2.05, 1.88, 1.65, 1.50]:
			var at := Vector3(s * 0.70, VehicleMesh.profile(TOP, z) + 0.004, z)
			body.tube("trim", previous, at, 0.003, 4)
			previous = at
		body.rbox("chrome", Vector3(0.16, 0.019, 0.008), Vector3(s * 0.60, 0.902, 2.281), 0.005)
	body.rbox("chrome", Vector3(0.022, 0.025, 0.016), Vector3(0.0, 0.905, 2.296), 0.009)
	body.tube("trim", Vector3(-0.745, 0.638, 2.35), Vector3(0.745, 0.638, 2.35), 0.003, 4)
	body.tube("dark", Vector3(0.58, 0.23, 2.09), Vector3(0.58, 0.215, 2.36), 0.025, 10, true)


static func _rear_z(x: float) -> float:
	# Фонарь огибает заднее крыло; центральная часть остаётся на плоскости крышки.
	var bend := maxf(absf(x) - 0.70, 0.0)
	return 2.17 + sqrt(maxf(0.18 * 0.18 - bend * bend, 0.0))


static func _rear_strip(body: VehicleMesh.Builder, slot: String, side: float,
		x0: float, x1: float, y0: float, y1: float, offset: float) -> void:
	var rows: Array = []
	for y in [y0, y1]:
		var row := PackedVector3Array()
		for k in 13:
			var x := lerpf(x0, x1, k / 12.0)
			row.append(Vector3(side * x, y, _rear_z(x) + offset))
		rows.append(row)
	body.grid(slot, rows, false, PackedVector3Array([Vector3(0, y0, -8), Vector3(0, y1, -8)]))


static func _bumper(body: VehicleMesh.Builder, end: float) -> void:
	body.rbox("trim", Vector3(1.78, 0.145, 0.142), Vector3(0.0, 0.546, end * (SIZE.z * 0.5 - 0.071)), 0.035)
	body.rbox("chrome", Vector3(1.66, 0.018, 0.022), Vector3(0.0, 0.613, end * 2.381), 0.007)
	for side in [-1.0, 1.0]:
		body.rbox("trim", Vector3(0.13, 0.145, 0.28), Vector3(side * 0.829, 0.546, end * 2.24), 0.035)


static func _sides(body: VehicleMesh.Builder) -> void:
	for side in [-1.0, 1.0]:
		var s: float = side
		# Четыре дверных полотна: две двери с ручками на каждом борту.
		for z in [-0.96, 0.105, 1.10]:
			body.tube("trim", Vector3(s * 0.897, _bottom_at(z) + 0.02, z),
				Vector3(s * 0.866, 0.957, z), 0.003, 4)
		body.tube("trim", Vector3(s * 0.892, 0.273, -0.94), Vector3(s * 0.892, 0.273, 0.83), 0.003, 4)
		for z in [-0.065, 0.91]:
			body.rbox("chrome", Vector3(0.018, 0.046, 0.116), Vector3(s * 0.873, 0.914, z), 0.008)
			body.box("trim", Vector3(0.022, 0.031, 0.080), Vector3(s * 0.884, 0.914, z + 0.006))
		# Чёрный защитный молдинг прерывается на арках, а не пересекает пустое место над шинами.
		for span in [[-2.15, -1.94], [-1.16, 0.85], [1.65, 2.15]]:
			var a: float = span[0]
			var b: float = span[1]
			body.rbox("trim", Vector3(0.019, 0.042, b - a), Vector3(s * 0.899, 0.605, (a + b) * 0.5), 0.007)
		body.rbox("lens_amber", Vector3(0.013, 0.027, 0.071), Vector3(s * 0.880, 0.928, -1.47), 0.005)
		var mirror := Vector3(s * 0.951, 1.079, -0.77)
		body.tube("trim", Vector3(s * 0.826, 1.038, -0.79), mirror, 0.021, 6)
		body.rbox("trim", Vector3(0.16, 0.115, 0.18), mirror, 0.028)
		body.rbox("lens_white", Vector3(0.128, 0.083, 0.010), mirror + Vector3(0.0, 0.0, 0.091), 0.013)
		for axle in AXLES:
			body.box("dark", Vector3(0.012, 0.34, 0.70), Vector3(s * 0.61, 0.46, axle))
			body.box("rubber", Vector3(0.19, 0.15, 0.012), Vector3(s * 0.74, 0.245, axle + ARCH_RADIUS + 0.018))
			var previous := Vector3(s * 0.891, WHEEL_RADIUS, axle - ARCH_RADIUS)
			for k in range(1, 25):
				var angle := PI - PI * k / 24.0
				var at := Vector3(s * 0.891, WHEEL_RADIUS + sin(angle) * ARCH_RADIUS, axle + cos(angle) * ARCH_RADIUS)
				body.tube("paint", previous, at, 0.009, 5)
				previous = at
	# Лючок бака у левого заднего крыла.
	var fuel := Vector3(-0.897, 0.819, 1.935)
	for dy in [-0.055, 0.055]:
		body.box("trim", Vector3(0.004, 0.003, 0.18), fuel + Vector3(0, dy, 0))
	for dz in [-0.09, 0.09]:
		body.box("trim", Vector3(0.004, 0.11, 0.003), fuel + Vector3(0, 0, dz))
	body.box("dark", Vector3(1.22, 0.045, 3.90), Vector3(0.0, 0.1785, 0.0))


static func _bottom_at(z: float) -> float:
	var low := VehicleMesh.profile(BOTTOM, z)
	for axle in AXLES:
		var dz: float = z - axle
		if absf(dz) < ARCH_RADIUS:
			low = maxf(low, WHEEL_RADIUS + sqrt(ARCH_RADIUS * ARCH_RADIUS - dz * dz))
	return low


static func _cabin(cabin: VehicleMesh.Builder) -> void:
	cabin.box("dark", Vector3(1.50, 0.025, 2.39), Vector3(0.0, 0.79, 0.22))
	cabin.rbox("dark", Vector3(1.48, 0.135, 0.30), Vector3(0.0, 0.995, -0.755), 0.027)
	for side in [-1.0, 1.0]:
		cabin.rbox("cloth", Vector3(0.49, 0.30, 0.15), Vector3(side * 0.37, 0.995, 0.05), 0.036)
		cabin.rbox("cloth", Vector3(0.25, 0.16, 0.10), Vector3(side * 0.37, 1.20, 0.065), 0.028)
	cabin.rbox("cloth", Vector3(1.35, 0.22, 0.14), Vector3(0.0, 1.02, 0.94), 0.03)
	for side in [-1.0, 1.0]:
		cabin.rbox("cloth", Vector3(0.24, 0.13, 0.085), Vector3(side * 0.41, 1.185, 0.95), 0.023)
	cabin.box("dark", Vector3(1.42, 0.02, 0.46), Vector3(0.0, 1.00, 1.20))
	cabin.rbox("lens_red", Vector3(0.15, 0.038, 0.04), Vector3(0.0, 1.041, 1.28), 0.01)
	var center := Vector3(-0.37, 1.047, -0.47)
	var up := Vector3(0.0, 0.86, -0.51)
	for k in 20:
		var a := TAU * k / 20.0
		var next := TAU * (k + 1) / 20.0
		cabin.tube("trim", center + (Vector3.RIGHT * cos(a) + up * sin(a)) * 0.175,
			center + (Vector3.RIGHT * cos(next) + up * sin(next)) * 0.175, 0.012, 5)
	cabin.tube("trim", center - Vector3.RIGHT * 0.16, center + Vector3.RIGHT * 0.16, 0.012, 4)
	cabin.rbox("dark", Vector3(0.20, 0.053, 0.025), Vector3(0.0, 1.305, -0.55), 0.01)


static func _plate(body: VehicleMesh.Builder, at: Vector3) -> void:
	body.box("trim", Vector3(0.53, 0.123, 0.012), at)
	body.box("plate", Vector3(0.515, 0.109, 0.014), at + Vector3(0.0, 0.0, signf(at.z) * 0.006))


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
	var key := "gaz3110_snow_" + VehicleMesh.snf(d)
	var mesh: ArrayMesh = VehicleMesh.cached(key)
	if mesh != null:
		return mesh
	var snow := VehicleMesh.Builder.new()
	snow.pillow("snow", Vector3(0.0, 0.0, 0.07), 1.30, 1.16, d, ROOF_Y - 0.010, ROOF_Y - 0.003, 71)
	snow.pillow("snow", Vector3(0.0, 0.0, -1.63), 1.35, 1.10, d * 0.58, 0.988, 1.033, 72)
	snow.pillow("snow", Vector3(0.0, 0.0, 1.88), 1.35, 0.66, d * 0.56, 0.992, 0.949, 73)
	mesh = VehicleMesh.finish(snow)
	return VehicleMesh.store(key, mesh)
