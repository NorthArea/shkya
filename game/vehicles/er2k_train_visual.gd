extends RefCounted
## Собственная статическая геометрия по форме ЭР2К: фото служит только референсом.
## -Z — голова, Y=0 — головка рельса. Caller размещает вагоны, пути и коллизии.
## Один MeshInstance3D, восемь opaque-поверхностей; ресурсы общие на вариант вагона.

const VehicleMesh := preload("res://game/vehicles/vehicle_mesh.gd")

const BODY_LENGTH := 19.6
const CAR_LENGTH := 20.4 # Шаг центров: сцепки встречаются на ±10,2 м.
const BODY_WIDTH := 3.48
const CAR_WIDTH := 3.56 # Вместе с наружными рёбрами и оконными рамами.
const ROOF_HEIGHT := 4.3
const CAR_HEIGHT := 5.02 # Верх неподвижного пантографа.
const SIZE := Vector3(CAR_WIDTH, CAR_HEIGHT, CAR_LENGTH)
const WHEEL_RADIUS := 0.52
const HALF_WIDTH := BODY_WIDTH * 0.5
const HALF_BODY := BODY_LENGTH * 0.5
const BODY_BOTTOM := 1.15
const WINDOW_BOTTOM := 2.26
const WINDOW_TOP := 3.39
const EAVE := 3.68
const DOOR_INNER := 6.95
const DOOR_OUTER := 8.45


static func build_car(cab: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "ER2KCab" if cab else "ER2KCoach"
	VehicleMesh.instance(root, "TrainMesh", _mesh(cab))
	return root


static func _mesh(cab: bool) -> ArrayMesh:
	var key := "er2k_cab" if cab else "er2k_coach"
	var found: ArrayMesh = VehicleMesh.cached(key)
	if found != null:
		return found
	var b := VehicleMesh.Builder.new()
	_underframe(b)
	_sides(b, cab)
	_roof(b, cab)
	_end(b, 1.0)
	if cab:
		_cab(b)
	else:
		_end(b, -1.0)
	_roof_equipment(b)
	var mesh := VehicleMesh.finish(b, _materials())
	return VehicleMesh.store(key, mesh)


static func _materials() -> Dictionary:
	var cached: Variant = VehicleMesh.cached("er2k_materials")
	if cached != null:
		return cached
	# Без текстур, эмиссии и прозрачности: окна остаются тёмными и днём, и ночью.
	var palette := {
		"green": [Color(0.055, 0.29, 0.22), 0.7, 0.12],
		"cream": [Color(0.80, 0.68, 0.37), 0.72, 0.08],
		"grey": [Color(0.53, 0.56, 0.55), 0.78, 0.12],
		"amber": [Color(0.96, 0.55, 0.075), 0.62, 0.05],
		"trim": [Color(0.045, 0.055, 0.052), 0.88, 0.05],
		"glass": [Color(0.075, 0.13, 0.15), 0.22, 0.3],
		"steel": [Color(0.22, 0.25, 0.24), 0.7, 0.55],
		"lens": [Color(0.68, 0.72, 0.64), 0.24, 0.22],
	}
	var materials := {}
	for slot in palette:
		var spec: Array = palette[slot]
		var material := StandardMaterial3D.new()
		material.albedo_color = spec[0]
		material.roughness = spec[1]
		material.metallic = spec[2]
		materials[slot] = material
	return VehicleMesh.store("er2k_materials", materials)


static func _underframe(b: VehicleMesh.Builder) -> void:
	b.box("trim", Vector3(2.75, 0.24, 18.5), Vector3(0, 1.12, 0))
	b.box("steel", Vector3(1.85, 0.47, 3.2), Vector3(0, 0.79, -2.1))
	b.box("steel", Vector3(1.9, 0.42, 2.4), Vector3(0, 0.82, 2.35))
	for bogie_z in [-6.4, 6.4]:
		b.box("trim", Vector3(2.18, 0.34, 3.5), Vector3(0, 0.72, bogie_z))
		for axle_z in [bogie_z - 1.22, bogie_z + 1.22]:
			b.tube("steel", Vector3(-1.25, WHEEL_RADIUS, axle_z), Vector3(1.25, WHEEL_RADIUS, axle_z), 0.095, 8, true)
			for s in [-1.0, 1.0]:
				var keep := b.xf
				b.xf = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(s * 1.05, WHEEL_RADIUS, axle_z))
				b.lathe("steel", PackedVector2Array([
					Vector2(0.001, -0.095), Vector2(0.45, -0.095),
					Vector2(WHEEL_RADIUS, -0.075), Vector2(WHEEL_RADIUS, 0.075),
					Vector2(0.42, 0.095), Vector2(0.001, 0.095),
				]), 14, Vector3.ZERO)
				b.xf = keep
				b.box("trim", Vector3(0.26, 0.26, 0.36), Vector3(s * 1.29, 0.57, axle_z))
		for s in [-1.0, 1.0]:
			b.box("steel", Vector3(0.2, 0.18, 3.1), Vector3(s * 1.29, 0.77, bogie_z))
			for spring_z in [-0.49, 0.49]:
				b.box("trim", Vector3(0.24, 0.33, 0.27), Vector3(s * 1.29, 0.81, bogie_z + spring_z))
	for s in [-1.0, 1.0]:
		b.box("steel", Vector3(0.23, 0.17, 0.8), Vector3(0, 0.93, s * 9.72))
		b.box("trim", Vector3(0.38, 0.28, 0.19), Vector3(0, 0.93, s * (CAR_LENGTH * 0.5 - 0.095)))


static func _sides(b: VehicleMesh.Builder, cab: bool) -> void:
	var front := -9.18 if cab else -HALF_BODY
	var spans := [[front, -DOOR_OUTER], [-DOOR_INNER, DOOR_INNER], [DOOR_OUTER, HALF_BODY]]
	for side in [-1.0, 1.0]:
		var x: float = side * (HALF_WIDTH - 0.035)
		# Панели прерываются у тамбуров: створки утоплены внутрь настоящих проёмов.
		for span in spans:
			var z0: float = span[0]
			var z1: float = span[1]
			var center := (z0 + z1) * 0.5
			var length := z1 - z0
			b.box("green", Vector3(0.07, 1.11, length), Vector3(x, 1.705, center))
			b.box("cream", Vector3(0.07, 1.23, length), Vector3(x, 2.855, center))
			b.box("green", Vector3(0.07, 0.24, length), Vector3(x, 3.58, center))
			b.box("grey", Vector3(0.075, 0.16, length), Vector3(x, 1.21, center))
			for rib_y in [1.48, 1.76, 2.05]:
				b.box("green", Vector3(0.035, 0.035, length), Vector3(side * (HALF_WIDTH + 0.012), rib_y, center))
		# Девять узких окон, частый шаг и кремовые переплёты — главный силуэт борта.
		for k in 9:
			var window_z := -5.84 + 1.46 * k
			_side_window(b, side, window_z, 1.17, WINDOW_BOTTOM, WINDOW_TOP)
		for end_sign in [-1.0, 1.0]:
			_door(b, side, end_sign * (DOOR_INNER + DOOR_OUTER) * 0.5)
		if cab:
			_side_window(b, side, -8.85, 0.43, 2.59, 3.37)
		else:
			_side_window(b, side, -9.09, 0.69, 2.43, 3.37)
		_side_window(b, side, 9.09, 0.69, 2.43, 3.37)


static func _side_window(b: VehicleMesh.Builder, side: float, z: float, width: float, bottom: float, top: float) -> void:
	var x := side * (HALF_WIDTH + 0.004)
	var normal := Vector3(side, 0, 0)
	var half := width * 0.5
	# Восемь вершин дают скошенные углы резинок и стёкол без дорогих rbox.
	for spec in [["trim", 0.0, 0.0], ["glass", 0.045, 0.008]]:
		var inset: float = spec[1]
		var px: float = x + side * float(spec[2])
		var lo := bottom + inset
		var hi := top - inset
		var a := z - half + inset
		var c := z + half - inset
		var bevel := 0.065
		b.poly(spec[0], PackedVector3Array([
			Vector3(px, lo, a + bevel), Vector3(px, lo, c - bevel),
			Vector3(px, lo + bevel, c), Vector3(px, hi - bevel, c),
			Vector3(px, hi, c - bevel), Vector3(px, hi, a + bevel),
			Vector3(px, hi - bevel, a), Vector3(px, lo + bevel, a),
		]), normal)
	# Узкая форточка сверху и металлическая горизонтальная перемычка.
	b.box("grey", Vector3(0.022, 0.022, width - 0.11), Vector3(x + side * 0.014, top - 0.28, z))


static func _door(b: VehicleMesh.Builder, side: float, z: float) -> void:
	var x := side * (HALF_WIDTH - 0.12)
	var width := DOOR_OUTER - DOOR_INNER
	b.box("trim", Vector3(0.018, 2.45, width), Vector3(x - side * 0.022, 2.39, z))
	for leaf in [-1.0, 1.0]:
		var center: float = z + leaf * width * 0.25
		b.box("green", Vector3(0.032, 2.29, width * 0.5 - 0.045), Vector3(x, 2.405, center))
		b.box("trim", Vector3(0.014, 0.77, 0.43), Vector3(x + side * 0.022, 2.89, center))
		b.box("glass", Vector3(0.014, 0.68, 0.34), Vector3(x + side * 0.032, 2.89, center))
		b.box("steel", Vector3(0.028, 0.16, 0.035), Vector3(x + side * 0.04, 2.28, z + leaf * 0.11))
	for jamb in [-1.0, 1.0]:
		b.box("grey", Vector3(0.13, 2.47, 0.045), Vector3(side * (HALF_WIDTH - 0.065), 2.385, z + jamb * width * 0.5))
		b.tube("grey", Vector3(side * (HALF_WIDTH - 0.025), 1.64, z + jamb * (width * 0.5 + 0.08)), Vector3(side * (HALF_WIDTH - 0.025), 2.51, z + jamb * (width * 0.5 + 0.08)), 0.022, 5)
	for step_y in [0.86, 1.12]:
		b.box("steel", Vector3(0.21, 0.06, width - 0.12), Vector3(side * (HALF_WIDTH - 0.105), step_y, z))
	b.box("green", Vector3(0.07, 0.19, width), Vector3(side * (HALF_WIDTH - 0.035), 3.6, z))


static func _roof(b: VehicleMesh.Builder, cab: bool) -> void:
	var rows: Array = []
	var refs := PackedVector3Array()
	# Крыша — широкая дуга поперечного эллипса, а не плоская коробка.
	var stations := [-9.8, -9.48, -8.9, -5.0, 0.0, 5.0, 9.48, 9.8]
	if cab:
		stations.erase(-9.48)
	for z: float in stations:
		var scale_w := 1.0
		var peak := ROOF_HEIGHT
		if absf(z) > 9.4:
			scale_w = 0.94 if absf(z) > 9.7 else 0.985
			peak -= 0.17 if absf(z) > 9.7 else 0.035
		if cab and z < -9.7:
			scale_w = 1.0
		var row := PackedVector3Array()
		for k in 13:
			var angle := PI * float(k) / 12.0
			var x := -cos(angle) * HALF_WIDTH * scale_w
			var at_z := z
			if cab and z < -9.7:
				at_z = _nose_z(x, EAVE) - sin(angle) * 0.07
			row.append(Vector3(x, EAVE + sin(angle) * (peak - EAVE), at_z))
		rows.append(row)
		refs.append(Vector3(0, 2.8, z))
	b.grid("grey", rows, false, refs)
	for index in [0, stations.size() - 1]:
		var normal := Vector3.FORWARD if index == 0 else Vector3.BACK
		b.poly("grey", rows[index], normal)
	for side in [-1.0, 1.0]:
		b.box("grey", Vector3(0.05, 0.07, 18.8), Vector3(side * (HALF_WIDTH - 0.015), 3.7, 0))


static func _end(b: VehicleMesh.Builder, sign_z: float) -> void:
	var z := sign_z * HALF_BODY
	b.box("green", Vector3(3.37, 2.53, 0.08), Vector3(0, 2.415, z - sign_z * 0.04))
	b.box("grey", Vector3(3.37, 0.2, 0.08), Vector3(0, 1.25, z))
	b.box("trim", Vector3(1.15, 2.25, 0.13), Vector3(0, 2.36, z + sign_z * 0.05))
	b.box("green", Vector3(0.77, 1.96, 0.04), Vector3(0, 2.3, z + sign_z * 0.13))
	b.box("glass", Vector3(0.52, 0.63, 0.02), Vector3(0, 2.91, z + sign_z * 0.16))
	# Объёмная гофра рамкой, а не сплошной чёрный щит между вагонами.
	for rib in 4:
		var rib_z := z + sign_z * (0.04 + rib * 0.055)
		for side in [-1.0, 1.0]:
			b.box("trim", Vector3(0.13, 2.24, 0.035), Vector3(side * 0.59, 2.37, rib_z))
		b.box("trim", Vector3(1.27, 0.13, 0.035), Vector3(0, 3.49, rib_z))
	b.box("steel", Vector3(1.04, 0.055, 0.27), Vector3(0, 1.25, z + sign_z * 0.12))


static func _cab(b: VehicleMesh.Builder) -> void:
	# Поперечная дуга носа; крайние стёкла уходят на скулы кабины.
	var xs: Array[float] = [-1.74, -1.4, -0.99, 0.0, 0.99, 1.4, 1.74]
	var zs: Array[float] = [-9.18, -9.61, -9.77, -9.82, -9.77, -9.61, -9.18]
	var ys: Array[float] = [1.35, 1.8, 2.5, 3.15, 3.68]
	var rows: Array = []
	var refs := PackedVector3Array()
	for y in ys:
		var row := PackedVector3Array()
		for k in xs.size():
			row.append(Vector3(xs[k], y, float(zs[k]) + maxf(y - 2.6, 0.0) * 0.085))
		rows.append(row)
		refs.append(Vector3(0, y, -8.7))
	b.grid("green", rows, false, refs)
	# Широкая серая нижняя юбка с заужением к низу.
	b.loft("grey", [[-9.83, 0.77, 1.38, 1.34, 1.58, 0.06, 0.03], [-9.45, 0.91, 1.38, 1.49, 1.69, 0.05, 0.03], [-9.18, 0.96, 1.38, 1.62, 1.74, 0.05, 0.03]], true, 2)
	for span in [[-1.43, -1.03], [-0.94, -0.07], [0.07, 0.94], [1.03, 1.43]]:
		var a: float = span[0]
		var c: float = span[1]
		for spec in [["trim", 0.0, 0.014], ["glass", 0.04, 0.026]]:
			var inset: float = spec[1]
			var lower := 2.76 + inset
			var upper := 3.51 - inset
			var p0 := Vector3(a + inset, lower, _nose_z(a + inset, lower) - float(spec[2]))
			var p1 := Vector3(c - inset, lower, _nose_z(c - inset, lower) - float(spec[2]))
			var p2 := Vector3(c - inset - 0.025 * signf(c), upper, _nose_z(c - inset, upper) - float(spec[2]))
			var p3 := Vector3(a + inset - 0.025 * signf(a), upper, _nose_z(a + inset, upper) - float(spec[2]))
			b.pane(spec[0], p0, p1, p2, p3, Vector3.FORWARD, 0.0, 1, 1)
	for stripe in [[1.48, 0.17, 1.58], [2.56, 0.12, 1.6], [2.04, 0.24, 0.88]]:
		var y: float = stripe[0]
		var height: float = stripe[1]
		var width: float = stripe[2]
		_nose_stripe(b, xs, ys, zs, y, height, width)
	# Верхний прожектор в сером лбу и две пары малых круглых фар.
	_disc(b, "grey", Vector3(0, 4.02, -9.79), 0.28, 0.12)
	_disc(b, "trim", Vector3(0, 4.02, -9.865), 0.213, 0.035)
	_disc(b, "lens", Vector3(0, 4.02, -9.889), 0.177, 0.012)
	for side in [-1.0, 1.0]:
		for light_x in [1.14, 1.36]:
			var x: float = side * light_x
			var z := _nose_z(x, 2.09) - 0.035
			_disc(b, "grey", Vector3(x, 2.09, z), 0.135, 0.07)
			_disc(b, "trim", Vector3(x, 2.09, z - 0.04), 0.103, 0.012)
			_disc(b, "lens", Vector3(x, 2.09, z - 0.05), 0.077, 0.012)
		b.tube("trim", Vector3(side * 0.28, 2.83, -9.84), Vector3(side * 0.67, 3.2, -9.815), 0.013, 5)
		b.tube("grey", Vector3(side * 1.56, 1.51, -9.47), Vector3(side * 1.56, 2.63, -9.47), 0.02, 5)
		for vent_x in [0.45, 0.7, 0.95]:
			b.box("trim", Vector3(0.052, 0.22, 0.018), Vector3(side * vent_x, 1.05, -9.842))
	b.box("trim", Vector3(0.45, 0.34, 0.17), Vector3(0, 1.28, -9.83))


static func _nose_stripe(b: VehicleMesh.Builder, xs: Array[float], ys: Array[float], zs: Array[float], y: float, height: float, width: float) -> void:
	# Полоса повторяет реальные плоскости сетки носа, включая скулы и наклон по Y.
	# Общий сдвиг -Z сохраняет стыки; на самой крутой грани зазор по нормали >18 мм.
	for face in xs.size() - 1:
		var x0 := maxf(-width, xs[face])
		var x1 := minf(width, xs[face + 1])
		if x1 <= x0:
			continue
		var slope_x := (zs[face + 1] - zs[face]) / (xs[face + 1] - xs[face])
		for band in ys.size() - 1:
			var y0 := maxf(y - height * 0.5, ys[band])
			var y1 := minf(y + height * 0.5, ys[band + 1])
			if y1 <= y0:
				continue
			var z_lower := maxf(ys[band] - 2.6, 0.0) * 0.085
			var z_upper := maxf(ys[band + 1] - 2.6, 0.0) * 0.085
			var slope_y := (z_upper - z_lower) / (ys[band + 1] - ys[band])
			var origin := Vector3(xs[face], ys[band], zs[face] + z_lower)
			var along_x := Vector3(1, 0, slope_x)
			var along_y := Vector3(0, 1, slope_y)
			var p00 := origin + along_x * (x0 - origin.x) + along_y * (y0 - origin.y) + Vector3.FORWARD * 0.03
			var p10 := p00 + along_x * (x1 - x0)
			var p11 := p10 + along_y * (y1 - y0)
			var p01 := p00 + along_y * (y1 - y0)
			b.poly("amber", PackedVector3Array([p00, p10, p11, p01]), Vector3(slope_x, slope_y, -1).normalized())


static func _nose_z(x: float, y: float) -> float:
	var ax := absf(x)
	var z := -9.82
	if ax <= 0.99:
		z += ax / 0.99 * 0.05
	elif ax <= 1.4:
		z = lerpf(-9.77, -9.61, (ax - 0.99) / 0.41)
	else:
		z = lerpf(-9.61, -9.18, (ax - 1.4) / 0.34)
	return z + maxf(y - 2.6, 0.0) * 0.085


static func _disc(b: VehicleMesh.Builder, slot: String, at: Vector3, radius: float, depth: float) -> void:
	var keep := b.xf
	b.xf = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at)
	b.lathe(slot, PackedVector2Array([
		Vector2(0.001, -depth * 0.5), Vector2(radius, -depth * 0.5),
		Vector2(radius, depth * 0.5), Vector2(0.001, depth * 0.5),
	]), 14, Vector3.ZERO)
	b.xf = keep


static func _roof_equipment(b: VehicleMesh.Builder) -> void:
	for z in [-4.1, -1.55, 1.55, 4.1, 7.0]:
		b.box("grey", Vector3(0.76, 0.14, 0.39), Vector3(0, 4.315, z))
		b.box("trim", Vector3(0.53, 0.045, 0.24), Vector3(0, 4.4, z))
	# Пантограф низко поднят, ромб из настоящих тонких тяг; никаких процессоров/анимации.
	var center_z := -6.7
	b.box("steel", Vector3(1.45, 0.08, 1.55), Vector3(0, 4.38, center_z))
	for x in [-0.46, 0.46]:
		for sign_z in [-1.0, 1.0]:
			var base := Vector3(x, 4.43, center_z)
			var elbow := Vector3(x, 4.69, center_z + sign_z * 0.8)
			var top := Vector3(x, 4.96, center_z)
			b.tube("steel", base, elbow, 0.027, 5)
			b.tube("steel", elbow, top, 0.025, 5)
	b.box("trim", Vector3(1.64, 0.06, 0.16), Vector3(0, CAR_HEIGHT - 0.03, center_z))
	b.tube("steel", Vector3(0.62, 4.28, -5.8), Vector3(0.62, 4.28, 7.4), 0.018, 5)
