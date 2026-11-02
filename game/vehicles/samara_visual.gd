extends RefCounted
## ВАЗ-2109/21093 с длинным крылом: собственная геометрия пятидверного хэтчбека.
## Размеры и 175/70 R13: https://www.drom.ru/catalog/lada/2109/237101/ .
## Свесы/профиль: «Третий Рим», 1999, стр. 8, https://expertvaz.ru/wp-content/uploads/lib/VAZ-2108-2109.pdf .
## Фото формы: каталог Drom https://www.drom.ru/catalog/lada/2109/237101/ ; сторонние фото в модель не включены.
## Панели/салон приближены по фото; чужих моделей, текстур и кода нет.
## Только облик: перед −Z, шины касаются y=0; SIZE без зеркал/снега.

const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const Dimensions = preload("res://game/vehicles/vehicle_dimensions.gd")
const SPEC: Dictionary = Dimensions.SPECS[&"samara2109"]
const SIZE := Vector3(SPEC["width_m"], SPEC["height_m"], SPEC["length_m"])
const WHEELBASE: float = SPEC["wheelbase_m"]
const WHEEL_RADIUS := 0.2876
const WHEEL_WIDTH := 0.175
const FRONT_AXLE: float = -SIZE.z * 0.5 + SPEC["front_overhang_m"]
const AXLES := [FRONT_AXLE, FRONT_AXLE + WHEELBASE]
const TRACK_HALF := [SPEC["front_track_m"] * 0.5, SPEC["rear_track_m"] * 0.5]
const HALF_WIDTH: float = SIZE.x * 0.5
const ARCH_RADIUS := 0.345
const HULL_LENGTH := 3.84
const BELT := 0.98
const ROOF_Y: float = SIZE.y
const GLASS_HALF_WIDTH := 0.771
const ROOF_HALF_WIDTH := 0.665
const TOP := [[-1.92, 0.815], [-1.84, 0.85], [-1.40, 0.915], [-0.73, 1.015],
	[-0.64, BELT], [1.63, BELT], [1.80, 0.951], [1.92, 0.891]]
const BOTTOM := [[-1.92, 0.35], [-1.50, 0.25], [-0.75, 0.225], [1.61, 0.23], [1.92, 0.34]]


static func build(paint: Color, plate: String = "", snow_depth: float = 0.08) -> Node3D:
	var visual := Node3D.new()
	visual.name = "Visual"
	var body := Node3D.new()
	body.name = "Body"
	visual.add_child(body)
	var meshes := body_meshes()
	var paint_material: ShaderMaterial = VehicleMesh.paint(paint, 0.19, 0.65,
		clampf(snow_depth * 3.0, 0.0, 0.7), 0.61).duplicate()
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
		_plate_label(body, Vector3(0, 0.488, -SIZE.z * 0.5 - 0.001), PI, plate)
		_plate_label(body, Vector3(0, 0.745, 1.948), 0.0, plate)
	return visual


static func wheel_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for axle in AXLES.size():
		for side in [-1.0, 1.0]:
			spots.append(Vector3(side * TRACK_HALF[axle], WHEEL_RADIUS, AXLES[axle]))
	return spots


static func wheel_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = VehicleMesh.cached("samara2109_wheel")
	if mesh != null:
		return mesh
	var wheel := VehicleMesh.Builder.new()
	var hw := WHEEL_WIDTH * 0.5
	var rim := 0.1651
	wheel.lathe("rubber", PackedVector2Array([
		Vector2(rim, -hw + 0.01), Vector2(WHEEL_RADIUS - 0.028, -hw),
		Vector2(WHEEL_RADIUS - 0.005, -hw + 0.018), Vector2(WHEEL_RADIUS, -hw * 0.48),
		Vector2(WHEEL_RADIUS, hw * 0.48), Vector2(WHEEL_RADIUS - 0.005, hw - 0.018),
		Vector2(WHEEL_RADIUS - 0.028, hw), Vector2(rim, hw - 0.01),
	]), 48, Vector3.ZERO, PackedInt32Array([3, 4]), 0.008)
	for side in [-1.0, 1.0]:
		var s: float = side
		wheel.lathe("alu", PackedVector2Array([
			Vector2(rim + 0.005, s * (hw - 0.011)), Vector2(rim * 0.92, s * (hw - 0.02)),
			Vector2(rim * 0.76, s * (hw - 0.037)), Vector2(rim * 0.48, s * (hw - 0.043)),
			Vector2(rim * 0.36, s * (hw - 0.025)), Vector2(0.001, s * (hw - 0.025)),
		]), 40, Vector3.ZERO)
		for k in 8:
			var angle := TAU * k / 8.0
			var at := Vector3(cos(angle) * 0.116, s * (hw - 0.021), sin(angle) * 0.116)
			var points := PackedVector3Array()
			for j in 12:
				var a := TAU * j / 12.0
				points.append(at + Vector3(cos(a) * 0.019, 0.0, sin(a) * 0.019))
			wheel.poly("dark", points, Vector3.UP * s)
		wheel.lathe("trim", PackedVector2Array([
			Vector2(0.047, s * (hw - 0.02)), Vector2(0.043, s * (hw + 0.003)),
			Vector2(0.001, s * (hw + 0.005)),
		]), 20, Vector3.ZERO)
		for k in 4:
			var angle := TAU * k / 4.0
			wheel.box("chrome", Vector3(0.017, 0.011, 0.017),
				Vector3(cos(angle) * 0.066, s * (hw - 0.021), sin(angle) * 0.066))
	mesh = VehicleMesh.finish(wheel)
	return VehicleMesh.store("samara2109_wheel", mesh)


static func body_meshes() -> Dictionary:
	var found: Variant = VehicleMesh.cached("samara2109_body")
	if found != null:
		return found
	var body := VehicleMesh.Builder.new()
	var glass := VehicleMesh.Builder.new()
	var interior := VehicleMesh.Builder.new()
	body.loft("paint", VehicleMesh.hull_stations(HULL_LENGTH, HALF_WIDTH, TOP, BOTTOM,
		AXLES, WHEEL_RADIUS, ARCH_RADIUS, 0.045, 0.055, 0.027, 0.022, 0.026, 0.075))
	_greenhouse(body, glass)
	_front(body)
	_rear(body)
	_sides(body)
	_cabin(interior)
	var meshes := {
		"body": VehicleMesh.finish(body, {"paint": VehicleMesh.paint(Color(0.35, 0.41, 0.30))}),
		"glass": VehicleMesh.finish(glass, {"glass": VehicleMesh.glass(0.018)}),
		"interior": VehicleMesh.finish(interior),
	}
	return VehicleMesh.store("samara2109_body", meshes)


static func _greenhouse(body: VehicleMesh.Builder, glass: VehicleMesh.Builder) -> void:
	body.loft("paint", [
		[-0.27, 1.350, 1.381, 0.658, 0.643, 0.008, 0.022],
		[-0.19, 1.350, 1.398, 0.677, 0.661, 0.01, 0.032],
		[0.40, 1.350, ROOF_Y, 0.681, 0.665, 0.01, 0.036],
		[0.99, 1.345, 1.381, 0.660, 0.644, 0.008, 0.026],
		[1.07, 1.334, 1.359, 0.640, 0.624, 0.008, 0.018],
	], true, 3)
	for side in [-1.0, 1.0]:
		var s: float = side
		var outward := Vector3(s, 0.25, 0.0).normalized()
		body.tube("paint", Vector3(s * GLASS_HALF_WIDTH, BELT, -0.70),
			Vector3(s * ROOF_HALF_WIDTH, 1.36, -0.23), 0.029, 6)
		body.poly("trim", PackedVector3Array([
			Vector3(s * GLASS_HALF_WIDTH, BELT, 0.23), Vector3(s * GLASS_HALF_WIDTH, BELT, 0.30),
			Vector3(s * ROOF_HALF_WIDTH, 1.35, 0.30), Vector3(s * ROOF_HALF_WIDTH, 1.35, 0.23),
		]), outward, true)
		body.poly("paint", PackedVector3Array([
			Vector3(s * GLASS_HALF_WIDTH, BELT, 0.99), Vector3(s * GLASS_HALF_WIDTH, BELT, 1.06),
			Vector3(s * ROOF_HALF_WIDTH, 1.35, 0.91), Vector3(s * ROOF_HALF_WIDTH, 1.35, 0.85),
		]), outward, true)
		body.poly("paint", PackedVector3Array([
			Vector3(s * GLASS_HALF_WIDTH, BELT, 1.47), Vector3(s * 0.785, BELT, 1.79),
			Vector3(s * 0.642, 1.351, 1.07), Vector3(s * ROOF_HALF_WIDTH, 1.35, 0.97),
		]), outward, true)
		glass.pane("glass", Vector3(s * GLASS_HALF_WIDTH, BELT + 0.009, -0.65),
			Vector3(s * GLASS_HALF_WIDTH, BELT + 0.009, 0.232),
			Vector3(s * ROOF_HALF_WIDTH, 1.342, 0.232), Vector3(s * ROOF_HALF_WIDTH, 1.342, -0.199),
			outward, 0.0, 4, 2)
		glass.pane("glass", Vector3(s * GLASS_HALF_WIDTH, BELT + 0.009, 0.298),
			Vector3(s * GLASS_HALF_WIDTH, BELT + 0.009, 0.991),
			Vector3(s * ROOF_HALF_WIDTH, 1.342, 0.851), Vector3(s * ROOF_HALF_WIDTH, 1.342, 0.298),
			outward, 0.0, 4, 2)
		# Маленькое неподвижное окно за задней дверью, отличающее пятидверную 2109 от 2108.
		glass.pane("glass", Vector3(s * GLASS_HALF_WIDTH, BELT + 0.009, 1.058),
			Vector3(s * GLASS_HALF_WIDTH, BELT + 0.009, 1.473),
			Vector3(s * ROOF_HALF_WIDTH, 1.341, 0.975), Vector3(s * ROOF_HALF_WIDTH, 1.341, 0.913),
			outward, 0.0, 4, 2)
		body.tube("trim", Vector3(s * 0.775, BELT + 0.001, -0.674),
			Vector3(s * 0.775, BELT + 0.001, 1.47), 0.009, 5)
		body.tube("trim", Vector3(s * 0.682, 1.367, -0.23), Vector3(s * 0.682, 1.367, 1.00), 0.009, 5)
	var front_out := Vector3(0.0, 0.47, -0.38).normalized()
	glass.pane("glass", Vector3(-0.742, 1.019, -0.70), Vector3(0.742, 1.019, -0.70),
		Vector3(0.634, 1.35, -0.264), Vector3(-0.634, 1.35, -0.264), front_out, 0.009, 7, 3)
	var rear_out := Vector3(0.0, 0.65, 0.35).normalized()
	glass.pane("glass", Vector3(-0.716, 1.005, 1.715), Vector3(0.716, 1.005, 1.715),
		Vector3(0.604, 1.332, 1.087), Vector3(-0.604, 1.332, 1.087), rear_out, 0.008, 7, 3)
	for side in [-1.0, 1.0]:
		body.poly("paint", PackedVector3Array([
			Vector3(side * 0.716, 1.005, 1.715), Vector3(side * 0.785, BELT, 1.79),
			Vector3(side * 0.642, 1.351, 1.07), Vector3(side * 0.604, 1.332, 1.087),
		]), rear_out, true)
		body.tube("trim", Vector3(side * 0.721, 1.004, 1.725),
			Vector3(side * 0.609, 1.338, 1.089), 0.008, 5)
	body.poly("paint", PackedVector3Array([
		Vector3(-0.773, 0.871, 1.921), Vector3(0.773, 0.871, 1.921),
		Vector3(0.744, 1.012, 1.721), Vector3(-0.744, 1.012, 1.721),
	]), rear_out)
	body.tube("trim", Vector3(-0.721, 1.006, 1.725), Vector3(0.721, 1.006, 1.725), 0.009, 5)
	# Штатный задний дворник лежит на нижней части наклонного стекла.
	body.tube("trim", Vector3(0.05, 1.031, 1.686), Vector3(-0.13, 1.095, 1.578), 0.007, 4)
	body.tube("trim", Vector3(-0.39, 1.100, 1.580), Vector3(0.13, 1.100, 1.580), 0.008, 4)


static func _front(body: VehicleMesh.Builder) -> void:
	body.box("trim", Vector3(0.70, 0.166, 0.025), Vector3(0, 0.715, -1.925))
	for k in 3:
		body.box("trim", Vector3(0.69, 0.017, 0.016), Vector3(0, 0.653 + k * 0.057, -1.946))
		if k < 2:
			body.box("dark", Vector3(0.67, 0.024, 0.006), Vector3(0, 0.680 + k * 0.057, -1.955))
	body.box("chrome", Vector3(0.025, 0.045, 0.008), Vector3(0, 0.72, -1.962))
	for side in [-1.0, 1.0]:
		var s: float = side
		body.rbox("trim", Vector3(0.35, 0.22, 0.028), Vector3(s * 0.533, 0.727, -1.922), 0.006)
		body.rbox("lens_white", Vector3(0.316, 0.189, 0.018), Vector3(s * 0.533, 0.727, -1.942), 0.005)
		body.rbox("lens_amber", Vector3(0.082, 0.188, 0.025), Vector3(s * 0.754, 0.729, -1.918), 0.006)
		for k in 8:
			body.box("chrome", Vector3(0.003, 0.162, 0.002), Vector3(s * 0.533 + (k - 3.5) * 0.035, 0.727, -1.953))
	_bumper(body, -1.0)
	_plate(body, Vector3(0, 0.488, -SIZE.z * 0.5 + 0.013))
	body.box("dark", Vector3(0.66, 0.066, 0.014), Vector3(0, 0.333, -1.922))
	for side in [-1.0, 1.0]:
		var previous := Vector3(side * 0.657, 0.847, -1.84)
		for z in [-1.65, -1.40, -1.15, -0.93, -0.74]:
			var at := Vector3(side * 0.657, VehicleMesh.profile(TOP, z) + 0.003, z)
			body.tube("trim", previous, at, 0.0025, 4)
			previous = at
	for x in [-0.60, -0.02]:
		body.tube("trim", Vector3(x, 1.040, -0.679), Vector3(x + 0.42, 1.060, -0.646), 0.007, 4)
		body.tube("trim", Vector3(x + 0.05, 1.021, -0.72), Vector3(x + 0.16, 1.056, -0.65), 0.005, 4)


static func _rear(body: VehicleMesh.Builder) -> void:
	_bumper(body, 1.0)
	_plate(body, Vector3(0, 0.745, 1.931))
	for side in [-1.0, 1.0]:
		var s: float = side
		body.rbox("trim", Vector3(0.405, 0.216, 0.026), Vector3(s * 0.577, 0.747, 1.925), 0.007)
		body.box("lens_red", Vector3(0.376, 0.190, 0.015), Vector3(s * 0.577, 0.747, 1.944))
		body.box("lens_amber", Vector3(0.106, 0.176, 0.013), Vector3(s * 0.708, 0.747, 1.956))
		body.box("lens_white", Vector3(0.135, 0.065, 0.014), Vector3(s * 0.55, 0.706, 1.956))
		body.tube("trim", Vector3(s * 0.77, 0.873, 1.927), Vector3(s * 0.741, 1.012, 1.725), 0.003, 4)
		body.rbox("chrome", Vector3(0.13, 0.016, 0.008), Vector3(s * 0.58, 0.908, 1.880), 0.004)
	body.rbox("trim", Vector3(0.098, 0.026, 0.021), Vector3(0, 0.901, 1.896), 0.006)
	body.tube("dark", Vector3(-0.47, 0.22, 1.68), Vector3(-0.47, 0.205, 1.98), 0.023, 10, true)


static func _bumper(body: VehicleMesh.Builder, end: float) -> void:
	body.rbox("trim", Vector3(1.63, 0.196, 0.17), Vector3(0, 0.482, end * 1.918), 0.018)
	for side in [-1.0, 1.0]:
		body.rbox("trim", Vector3(0.106, 0.196, 0.26), Vector3(side * 0.768, 0.482, end * 1.78), 0.016)


static func _sides(body: VehicleMesh.Builder) -> void:
	for side in [-1.0, 1.0]:
		var s: float = side
		for z in [-0.67, 0.265, 1.01]:
			body.tube("trim", Vector3(s * 0.822, _bottom_at(z) + 0.016, z),
				Vector3(s * 0.799, 0.967, z), 0.003, 4)
		body.tube("trim", Vector3(s * 0.822, 0.253, -0.65), Vector3(s * 0.822, 0.253, 0.86), 0.003, 4)
		for z in [0.115, 0.86]:
			body.rbox("trim", Vector3(0.022, 0.035, 0.143), Vector3(s * 0.811, 0.903, z), 0.006)
			body.rbox("trim", Vector3(0.024, 0.055, 0.082), Vector3(s * 0.812, 0.878, z + 0.015), 0.006)
		body.rbox("lens_amber", Vector3(0.012, 0.033, 0.065), Vector3(s * 0.820, 0.847, -1.05), 0.004)
		var mirror := Vector3(s * 0.889, 1.042, -0.58)
		body.tube("trim", Vector3(s * 0.776, 1.023, -0.58), mirror, 0.018, 6)
		body.rbox("trim", Vector3(0.144, 0.108, 0.174), mirror, 0.014)
		body.rbox("lens_white", Vector3(0.118, 0.080, 0.009), mirror + Vector3(0, 0, 0.088), 0.008)
		for axle in AXLES:
			body.box("dark", Vector3(0.01, 0.31, 0.66), Vector3(s * 0.59, 0.44, axle))
			body.box("rubber", Vector3(0.18, 0.17, 0.012), Vector3(s * 0.695, 0.225, axle + ARCH_RADIUS + 0.017))
			var previous := Vector3(s * 0.821, WHEEL_RADIUS, axle - ARCH_RADIUS)
			for k in range(1, 25):
				var angle := PI - PI * k / 24.0
				var at := Vector3(s * 0.821, WHEEL_RADIUS + sin(angle) * ARCH_RADIUS, axle + cos(angle) * ARCH_RADIUS)
				body.tube("paint", previous, at, 0.007, 4)
				previous = at
	# Прямоугольный лючок на правом заднем крыле.
	var fuel := Vector3(0.824, 0.807, 1.63)
	for dy in [-0.051, 0.051]:
		body.box("trim", Vector3(0.004, 0.003, 0.12), fuel + Vector3(0, dy, 0))
	for dz in [-0.06, 0.06]:
		body.box("trim", Vector3(0.004, 0.102, 0.003), fuel + Vector3(0, 0, dz))
	body.box("dark", Vector3(1.16, 0.04, 3.26), Vector3(0, 0.18, 0))


static func _bottom_at(z: float) -> float:
	var low := VehicleMesh.profile(BOTTOM, z)
	for axle in AXLES:
		var dz: float = z - axle
		if absf(dz) < ARCH_RADIUS:
			low = maxf(low, WHEEL_RADIUS + sqrt(ARCH_RADIUS * ARCH_RADIUS - dz * dz))
	return low


static func _cabin(cabin: VehicleMesh.Builder) -> void:
	cabin.box("dark", Vector3(1.39, 0.02, 2.22), Vector3(0, 0.77, 0.41))
	cabin.rbox("dark", Vector3(1.38, 0.14, 0.26), Vector3(0, 0.99, -0.52), 0.018)
	for side in [-1.0, 1.0]:
		cabin.rbox("cloth", Vector3(0.46, 0.29, 0.14), Vector3(side * 0.34, 1.0, 0.22), 0.025)
		cabin.rbox("cloth", Vector3(0.24, 0.15, 0.09), Vector3(side * 0.34, 1.20, 0.23), 0.021)
	cabin.rbox("cloth", Vector3(1.24, 0.23, 0.13), Vector3(0, 1.01, 1.01), 0.022)
	cabin.box("dark", Vector3(1.30, 0.018, 0.52), Vector3(0, 1.003, 1.30))
	var center := Vector3(-0.34, 1.055, -0.26)
	var up := Vector3(0, 0.86, -0.51)
	for k in 20:
		var a := TAU * k / 20.0
		var next := TAU * (k + 1) / 20.0
		cabin.tube("trim", center + (Vector3.RIGHT * cos(a) + up * sin(a)) * 0.17,
			center + (Vector3.RIGHT * cos(next) + up * sin(next)) * 0.17, 0.011, 5)
	cabin.tube("trim", center - Vector3.RIGHT * 0.16, center + Vector3.RIGHT * 0.16, 0.012, 4)
	cabin.rbox("dark", Vector3(0.18, 0.05, 0.024), Vector3(0, 1.307, -0.21), 0.007)


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
	var key := "samara2109_snow_" + VehicleMesh.snf(d)
	var mesh: ArrayMesh = VehicleMesh.cached(key)
	if mesh != null:
		return mesh
	var snow := VehicleMesh.Builder.new()
	snow.pillow("snow", Vector3(0, 0, 0.40), 1.20, 1.11, d, 1.397, 1.385, 81)
	snow.pillow("snow", Vector3(0, 0, -1.285), 1.30, 0.96, d * 0.56, 0.866, 1.011, 82)
	mesh = VehicleMesh.finish(snow)
	return VehicleMesh.store(key, mesh)
