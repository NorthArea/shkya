extends RefCounted
## Машина героя — светло-бежевая ВАЗ-2106: четыре круглые фары, хромированные бамперы и обводы, классические колёса.
## Общая ВАЗ-2106 — для игрока, парковок, полицейского поста и потока; «Волга» ГАЗ-24 — для машин кольца.
## Силуэт трёхобъёмника — лофт сечений: капот, наклонные стойки, скаты крыши, арки колёс.
## Только внешний вид: коллизия, физика и зона входа остаются в lada.gd. Перед — −Z, начало — на земле.
## Меши общие (VehicleMesh.cached): «Лада» игрока, ≈ 16 припаркованных «Жигулей» и машины кольца делят меши своих моделей;
## на машину — свои материалы краски, стёкол и фар (перекрытия поверхностей).

const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const LadaDriver = preload("res://game/vehicles/lada_driver.gd")

const PLATE := "н382кх 154"
const WHITE := Color(0.86, 0.85, 0.80)
const BEIGE := Color(0.84, 0.79, 0.68)
const PLAYER_MODEL := &"vaz2106"

## Огни (POLISH-02, п. 8): без водителя фары погашены, задние тусклые; с водителем горят; при торможении ярче.
enum Lights { OFF, ON, BRAKE }
const TAIL_ENERGY := [0.25, 1.2, 4.0]
const HEAD_ENERGY := 1.6
const BEAM_RANGE := 22.0
const BEAM_ENERGY := 6.0
const BEAM_COLOR := Color(1.0, 0.91, 0.76)   # тёплый белый лампы накаливания

## Водитель на переднем левом месте ВАЗ-2106: z=−0,19 перед стойкой B (z=0,19), за рулём (z≈−0,53).
## y — линия «ног» холста, не макушка.
## По формуле LadaDriver y = DRIVER_AT.y + (FEET_Y − canvas_y) * DRIVER_HEIGHT / CANVAS_HEIGHT:
## волосы (canvas_y≈42) на 1,301 м, воротник (270–330) на 0,966–0,878 м: плечи уходят под линию окон.
## Холст крупнее на 17%; опущен, чтобы даже его прозрачный верх (1,362 м) остался ниже крыши (1,385 м).
## Сдвиг к центру на 1,5 см оставляет полный billboard внутри ширины крыши при любом повороте к камере.
const DRIVER_AT := Vector3(-0.345, 0.497, -0.19) # 1 см за прежним местом: подбородок не касается нижнего обода
const DRIVER_HEIGHT := 0.88

## Линии стёкол (y, z) «пятёрки»: лобовое и заднее — как в ART-03/POLISH-02 (по ним вписан водитель).
const WINDSHIELD_BOTTOM := Vector2(0.99, -0.83)
const WINDSHIELD_TOP := Vector2(1.45, -0.49)
const REAR_TOP := Vector2(1.45, 0.89)
const REAR_BOTTOM := Vector2(0.99, 1.16)

## Седаны: размеры, профили верха и низа нижнего кузова [[z, y]], линии стёкол, оси, колёса, стиль передка.
## Размеры — по ВАЗ-2105 (4130 × 1620 × 1446, база 2424), ВАЗ-2106 (4166 × 1611), ГАЗ-24 (4735 × 1800 × 1490, база 2800).
const SEDANS := {
	&"vaz2105": {
		"length": 4.13, "half_w": 0.81, "belt": 0.99,
		"top": [[-2.065, 0.90], [-2.035, 0.93], [-1.9, 0.955], [-0.83, 0.985], [1.16, 0.99], [1.90, 0.97], [2.04, 0.955], [2.065, 0.93]],
		"bottom": [[-2.065, 0.42], [-1.9, 0.27], [1.9, 0.28], [2.065, 0.42]],
		"ws": [WINDSHIELD_BOTTOM, WINDSHIELD_TOP], "rear": [REAR_BOTTOM, REAR_TOP],
		"glass_w": 0.77, "roof_w": 0.655, "b_z": 0.19, "c_z": [0.84, 0.72], "roof_y": 1.485,
		"axles": [-1.26, 1.16], "wheel_r": 0.30, "wheel_w": 0.17, "track": 0.68, "round": 0.04, "edge": 0.025,
		"front": "rect", "wheel_style": "steel", "aerial_y": 1.767,
	},
	&"vaz2106": {
		"length": 4.07, "half_w": 0.80, "belt": 0.98,
		"top": [[-2.035, 0.89], [-2.0, 0.925], [-1.86, 0.945], [-0.83, 0.975], [1.14, 0.98], [1.82, 0.962], [2.0, 0.95], [2.035, 0.92]],
		"bottom": [[-2.035, 0.40], [-1.88, 0.28], [1.88, 0.29], [2.035, 0.42]],
		"ws": [Vector2(0.98, -0.83), Vector2(1.42, -0.50)], "rear": [Vector2(0.98, 1.14), Vector2(1.42, 0.88)],
		"glass_w": 0.76, "roof_w": 0.645, "b_z": 0.19, "c_z": [0.83, 0.71], "roof_y": 1.455,
		"axles": [-1.21, 1.21], "wheel_r": 0.32, "wheel_w": 0.17, "track": 0.69, "round": 0.065, "edge": 0.04,
		"front": "round4", "wheel_style": "classic", "aerial_y": 1.761,
	},
	&"volga": {
		"length": 4.74, "half_w": 0.90, "belt": 0.95,
		"top": [[-2.37, 0.90], [-2.33, 0.925], [-2.1, 0.945], [-0.95, 0.95], [1.24, 0.95], [2.15, 0.93], [2.34, 0.91], [2.37, 0.88]],
		"bottom": [[-2.37, 0.40], [-2.2, 0.28], [2.2, 0.30], [2.37, 0.40]],
		"ws": [Vector2(0.95, -0.95), Vector2(1.42, -0.47)], "rear": [Vector2(0.95, 1.24), Vector2(1.42, 0.76)],
		"glass_w": 0.85, "roof_w": 0.73, "b_z": 0.12, "c_z": [0.94, 0.66], "roof_y": 1.475,
		"axles": [-1.4, 1.4], "wheel_r": 0.34, "wheel_w": 0.19, "track": 0.75, "round": 0.08, "edge": 0.045,
		"front": "volga", "wheel_style": "volga", "aerial_y": 1.705,
	},
}

## paint — цвет кузова; plate — номер ("" — без номера); player — фары, водитель и вращение колёс.
## Во всех ролях общий кузов ВАЗ-2106; парковки и службы передают свои окраску, износ и снег.
static func build(paint := BEIGE, plate := PLATE, player := true, rust := 0.8, snow_depth := 0.08) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var model: StringName = PLAYER_MODEL
	var spec: Dictionary = SEDANS[model]
	var head: Material = null
	var tail: Material = null
	if player:
		head = VehicleMesh.lamp(Color(1.0, 0.95, 0.80), Color(1.0, 0.92, 0.70), 0.0)
		tail = VehicleMesh.lamp(Color(0.32, 0.03, 0.02), Color(0.9, 0.05, 0.03), 0.0)
		root.set_meta("head_material", head)
		root.set_meta("tail_material", tail)
	# Стоящие машины — в снегу гуще и с инеем шире; у машины игрока стёкла почти чистые (видно водителя).
	var snow := clampf(snow_depth * 4.0, 0.2, 0.8)
	var paint_material := VehicleMesh.paint(paint, rust, 1.0, snow, 0.55)
	var body := dress(root, model, paint_material, VehicleMesh.glass(0.03 if player else 0.07), head, tail, plate, snow_depth)
	# Instance material illuminates the actual amber lenses; it follows body damage and every transform.
	var indicators := VehicleMesh.lamp(Color(1.0, 0.55, 0.10), Color(1.0, 0.5, 0.05), 0.0)
	var body_mesh := body.get_node("BodyMesh") as MeshInstance3D
	var amber_slot := (body_mesh.mesh.get_meta("slots", []) as Array).find("lens_amber")
	if amber_slot >= 0:
		body_mesh.set_surface_override_material(amber_slot, indicators)
	root.set_meta("indicator_material", indicators)
	var wheels: Array[Node3D] = []
	var steer: Array[Node3D] = []
	for spot in wheel_spots(model):
		var pivot := Node3D.new()
		pivot.name = "WheelPivot%d" % wheels.size()
		pivot.position = spot
		root.add_child(pivot)
		var wheel := VehicleMesh.add_wheel(pivot, Vector3.ZERO, spec["wheel_r"], spec["wheel_w"], spec["wheel_style"])
		wheels.append(wheel)
		if spot.z < 0.0:
			steer.append(pivot)
	if player:
		_beams(body, model)
		var driver: Node3D = LadaDriver.new()
		driver.name = "Driver"
		driver.character = "ilyusha"
		driver.height_m = DRIVER_HEIGHT
		driver.position = DRIVER_AT
		driver.visible = false
		body.add_child(driver)
		var exhaust := VehicleMesh.exhaust(root, Vector3(-0.45, 0.29, float(spec["length"]) * 0.5 + 0.085))
		exhaust.emitting = false
		var motion := Motion.new()
		motion.name = "Motion"
		motion.wheels = wheels
		motion.steer = steer
		motion.body = body
		motion.radius = spec["wheel_r"]
		root.add_child(motion)
		set_lights(root, Lights.OFF)
	return root

static func set_indicators(visual: Node3D, on: bool) -> void:
	var material := visual.get_meta("indicator_material", null) as StandardMaterial3D
	if material:
		material.emission_energy_multiplier = 4.0 if on else 0.0

## Огни «Лады»: фары с лучами, задние фонари по режиму Lights; выхлоп — пока работает мотор (огни горят).
static func set_lights(visual: Node3D, mode: int) -> void:
	var on := mode != Lights.OFF
	for name in ["Body/BeamLeft", "Body/BeamRight"]:
		var beam := visual.get_node_or_null(name) as Light3D
		if beam:
			beam.visible = on
	var head := visual.get_meta("head_material", null) as StandardMaterial3D
	if head:
		head.emission_energy_multiplier = HEAD_ENERGY if on else 0.0
	var tail := visual.get_meta("tail_material", null) as StandardMaterial3D
	if tail:
		tail.emission_energy_multiplier = TAIL_ENERGY[mode]
	var exhaust := visual.get_node_or_null("Exhaust") as CPUParticles3D
	if exhaust:
		exhaust.emitting = on

static func set_driver_visible(visual: Node3D, shown: bool) -> void:
	var driver := visual.get_node_or_null("Body/Driver") as Node3D
	if driver:
		driver.visible = shown

## Кузов седана model в parent: узел Body с кузовом, стёклами, салоном, снегом и номерами.
## head/tail — материалы стёкол фар и фонарей (null — стекло без света).
static func dress(parent: Node3D, model: StringName, paint: Material, glass: Material, head: Material, tail: Material,
		plate: String, snow_depth: float) -> Node3D:
	var meshes := sedan_meshes(model)
	var body := Node3D.new()
	body.name = "Body"
	parent.add_child(body)
	var overrides := {"paint": paint}
	if head:
		overrides["head"] = head
	if tail:
		overrides["tail"] = tail
	VehicleMesh.instance(body, "BodyMesh", meshes["body"], overrides)
	var glass_mi := VehicleMesh.instance(body, "Glass", meshes["glass"], {"glass": glass}, false)
	glass_mi.sorting_offset = -0.5
	var interior := VehicleMesh.instance(body, "Interior", meshes["interior"], {}, false)
	interior.visibility_range_end = 45.0
	if snow_depth > 0.0:
		VehicleMesh.instance(body, "Snow", snow_mesh(model, snow_depth), {}, true)
	if plate != "":
		var spec: Dictionary = SEDANS[model]
		var hl: float = spec["length"] * 0.5
		_plate_label(body, Vector3(0, 0.49, -hl - 0.106), PI, plate)
		_plate_label(body, Vector3(0, 0.66, hl + 0.022), 0.0, plate)
	return body

## Точки колёс модели (центры): левые и правые, передние и задние.
static func wheel_spots(model: StringName) -> Array[Vector3]:
	var spec: Dictionary = SEDANS[model]
	var out: Array[Vector3] = []
	var track: float = spec["track"]
	var r: float = spec["wheel_r"]
	for axle in spec["axles"]:
		for x in [-track, track]:
			out.append(Vector3(x, r, axle))
	return out

## Общие меши седана: body (кузов и детали по слотам), glass, interior.
static func sedan_meshes(model: StringName) -> Dictionary:
	var key := "sedan_" + String(model)
	if LadaDriver.uses_3d():
		key += "_3d_occupants"
	var found: Variant = VehicleMesh.cached(key)
	if found != null:
		return found
	var spec: Dictionary = SEDANS[model]
	var b := VehicleMesh.Builder.new()
	var glass := VehicleMesh.Builder.new()
	var cabin := VehicleMesh.Builder.new()
	for builder in [b, glass, cabin]:
		builder.record_parts = model == PLAYER_MODEL
	var length: float = spec["length"]
	var hl := length * 0.5
	var w: float = spec["half_w"]
	var belt: float = spec["belt"]
	var r: float = spec["wheel_r"]
	var arch := r + 0.07
	var axles: Array = spec["axles"]
	var top: Array = spec["top"]
	var bottom: Array = spec["bottom"]
	# Нижний кузов: лофт сечений со скруглёнными рёбрами, завалом бортов и вырезами арок.
	var stations := VehicleMesh.hull_stations(length, w, top, bottom, axles, r, arch, spec["round"], spec["round"],
		0.018, 0.04, spec["edge"])
	if LadaDriver.uses_3d():
		_open_cabin_hull(b, stations, spec)
	else:
		b.loft("paint", stations)
	_greenhouse(b, glass, spec)
	_cabin(cabin, spec)
	_details(b, spec, hl, w, belt, r, arch, axles, bottom)
	var meshes := {
		"body": VehicleMesh.finish(b, {"paint": VehicleMesh.paint(WHITE), "head": VehicleMesh.mat("lens_white"), "tail": VehicleMesh.mat("lens_red")}),
		"glass": VehicleMesh.finish(glass, {"glass": VehicleMesh.glass()}),
		"interior": VehicleMesh.finish(cabin),
	}
	return VehicleMesh.store(key, meshes)

## Keep the door walls and underbody, with an actual opening between the screens.
## The closed hull's flat upper strip used to slice through the seated driver.
static func _open_cabin_hull(b: VehicleMesh.Builder, stations: Array, spec: Dictionary) -> void:
	var rows: Array = []
	var upper_rows: Array = []
	var refs := PackedVector3Array()
	for station: Array in stations:
		var ring := b.section(station[0], station[1], station[2], station[3], station[4], station[5], station[6])
		var top := (ring.size() + 2) / 2 - 1
		var shell := PackedVector3Array()
		for index in range(top + 1, ring.size()):
			shell.append(ring[index])
		for index in range(0, top):
			shell.append(ring[index])
		rows.append(shell)
		upper_rows.append(PackedVector3Array([ring[top - 1], ring[top], ring[top + 1]]))
		refs.append(Vector3(0, (station[1] + station[2]) * 0.5, station[0]))
	b.triangle_part = &"side_shell"
	b.grid("paint", rows, false, refs)
	b.triangle_part = &""
	for index in stations.size() - 1:
		var middle_z: float = (stations[index][0] + stations[index + 1][0]) * 0.5
		if middle_z > spec["ws"][0].y + 0.10 and middle_z < spec["rear"][0].y - 0.10:
			continue
		b.grid("paint", [upper_rows[index], upper_rows[index + 1]], false, PackedVector3Array([refs[index], refs[index + 1]]))
	var first: Array = stations[0]
	var last: Array = stations[-1]
	b.cap("paint", b.section(first[0], first[1], first[2], first[3], first[4], first[5], first[6]), Vector3.FORWARD)
	b.cap("paint", b.section(last[0], last[1], last[2], last[3], last[4], last[5], last[6]), Vector3.BACK)

## Крыша, стойки и стёкла: лобовое и заднее по линиям ws/rear, боковые окна передней и задней двери, глухая
## треугольная «парусная» панель у задней стойки.
static func _greenhouse(b: VehicleMesh.Builder, glass: VehicleMesh.Builder, spec: Dictionary) -> void:
	var ws: Array = spec["ws"]
	var rear: Array = spec["rear"]
	var wsb: Vector2 = ws[0]
	var wst: Vector2 = ws[1]
	var rb: Vector2 = rear[0]
	var rt: Vector2 = rear[1]
	var gw: float = spec["glass_w"]
	var rw: float = spec["roof_w"]
	var roof_y: float = spec["roof_y"]
	var bz: float = spec["b_z"]
	var cz: Array = spec["c_z"]
	var sill := wsb.x + 0.005
	var eave := wst.x - 0.02
	# Крыша: пологий купол, края скруглены; передний и задний края закрывают верх стёкол.
	var z0 := wst.y - 0.03
	var z1 := rt.y + 0.03
	var yb := wst.x - 0.035
	b.loft("paint", [
		[z0, yb + 0.012, roof_y - 0.03, rw - 0.02, rw - 0.04, 0.01, 0.03],
		[z0 + 0.05, yb, roof_y, rw + 0.012, rw - 0.008, 0.01, 0.06],
		[(z0 + z1) * 0.5, yb, roof_y + 0.008, rw + 0.012, rw - 0.008, 0.01, 0.07],
		[z1 - 0.05, yb, roof_y, rw + 0.012, rw - 0.008, 0.01, 0.06],
		[z1, yb + 0.012, roof_y - 0.03, rw - 0.02, rw - 0.04, 0.01, 0.03],
	], true, 3)
	for side in [-1.0, 1.0]:
		var s: float = side
		var a0 := Vector3(s * gw, sill, wsb.y + 0.01)
		var a1 := Vector3(s * rw, eave, wst.y + 0.01)
		var c0 := Vector3(s * gw, sill, rb.y - 0.01)
		var c1 := Vector3(s * rw, eave, rt.y - 0.01)
		b.tube("paint", a0, a1, 0.034, 6)                                          # стойка A
		b.tube("paint", Vector3(s * (gw + 0.003), sill, bz), Vector3(s * (rw + 0.003), eave, bz + 0.02), 0.032, 6)   # стойка B
		b.tube("paint", c0, c1, 0.03, 6)
		# «Парус» задней стойки — глухая панель между задним окном двери и задним стеклом.
		var sail := PackedVector3Array([Vector3(s * gw, sill, cz[0]), c0, c1, Vector3(s * rw, eave, cz[1])])
		b.poly("paint", sail, Vector3(s * (eave - sill), gw - rw, 0.0).normalized(), true)
		b.tube("trim", Vector3(s * (gw + 0.012), sill - 0.002, wsb.y + 0.05), Vector3(s * (gw + 0.012), sill - 0.002, cz[0]), 0.009, 4)   # уплотнитель
		# Боковые стёкла: передняя дверь (A–B) и задняя (B–«парус»), плоскость с завалом внутрь.
		var out := Vector3(s * (eave - sill), gw - rw, 0.0).normalized()
		var lean := (wst.y - wsb.y) / (wst.x - wsb.x)
		glass.triangle_part = &"door_glass_l" if s < 0 else &""
		glass.pane("glass", Vector3(s * (gw - 0.004), sill + 0.01, wsb.y + 0.05), Vector3(s * (gw - 0.004), sill + 0.01, bz - 0.035),
			Vector3(s * (rw + 0.004), eave - 0.012, bz - 0.015), Vector3(s * (rw + 0.004), eave - 0.012, wsb.y + lean * (eave - 0.012 - wsb.x) + 0.04), out, 0.0, 2, 1)
		glass.triangle_part = &""
		glass.pane("glass", Vector3(s * (gw - 0.004), sill + 0.01, bz + 0.035), Vector3(s * (gw - 0.004), sill + 0.01, float(cz[0]) - 0.02),
			Vector3(s * (rw + 0.004), eave - 0.012, float(cz[1]) - 0.015), Vector3(s * (rw + 0.004), eave - 0.012, bz + 0.055), out, 0.0, 2, 1)
		# Водосток и обводы окон: у 2105 чёрная резина, у 2106/ГАЗ-24 заметный хром.
		var frame := "trim" if spec["front"] == "rect" else "chrome"
		var a_trim := Vector3(s * 0.025, 0, -0.012)
		var c_trim := Vector3(s * 0.025, 0, 0.012)
		b.tube(frame, a0 + a_trim, a1 + a_trim, 0.012, 4)
		b.tube(frame, c0 + c_trim, c1 + c_trim, 0.012, 4)
		b.triangle_part = &"belt_trim_l" if s < 0 else &""
		b.tube(frame, Vector3(s * gw, sill, wsb.y + 0.01), Vector3(s * gw, sill, rb.y - 0.01), 0.012, 4)
		b.triangle_part = &""
		b.tube(frame, Vector3(s * (rw + 0.019), eave + 0.018, wst.y),
			Vector3(s * (rw + 0.019), eave + 0.018, rt.y), 0.013, 4)
		if spec["front"] != "rect":
			# Форточка передней двери — характерная вертикальная перемычка классических кузовов.
			var quarter_z := wsb.y + 0.33
			b.triangle_part = &"door_quarter_l" if s < 0 else &""
			b.tube("chrome", Vector3(s * gw, sill + 0.015, quarter_z),
				Vector3(s * (rw + 0.016), eave - 0.015, quarter_z + 0.025), 0.009, 4)
			b.triangle_part = &""
		if spec["front"] == "volga":
			# Вытяжные прорези на широкой задней стойке, не дополнительное окно.
			for k in 3:
				var y := sill + 0.12 + k * 0.06
				var t := (y - sill) / (eave - sill)
				var x := lerpf(gw, rw, t) + 0.008
				var z := lerpf(float(cz[0]), float(cz[1]), t) + 0.07
				b.box("trim", Vector3(0.009, 0.018, 0.10), Vector3(s * x, y, z))
	# Лобовое и заднее — слегка выпуклые.
	var front_out := Vector3(0.0, wst.y - wsb.y, -(wst.x - wsb.x)).normalized()
	glass.pane("glass", Vector3(-gw + 0.03, sill, wsb.y), Vector3(gw - 0.03, sill, wsb.y),
		Vector3(rw - 0.025, wst.x, wst.y), Vector3(-rw + 0.025, wst.x, wst.y), front_out, 0.025, 6, 2)
	var back_out := Vector3(0.0, rb.y - rt.y, rt.x - rb.x).normalized()
	glass.pane("glass", Vector3(gw - 0.03, sill, rb.y), Vector3(-gw + 0.03, sill, rb.y),
		Vector3(-rw + 0.025, rt.x, rt.y), Vector3(rw - 0.025, rt.x, rt.y), back_out, 0.02, 6, 2)

	var screen_frame := "trim" if spec["front"] == "rect" else "chrome"
	for edge in [[wsb, gw - 0.03], [wst, rw - 0.025], [rb, gw - 0.03], [rt, rw - 0.025]]:
		var at: Vector2 = edge[0]
		var half_width: float = edge[1]
		b.tube(screen_frame, Vector3(-half_width, at.x, at.y), Vector3(half_width, at.x, at.y), 0.009, 4)

## Салон силуэтами: тёмная обшивка по линии окон, торпедо, руль, спинка пассажира с подголовником, задний диван.
## У водительского кресла нет высокой спинки и подголовника — сзади видны голова и воротник Илюши (концепт 05).
static func _cabin(b: VehicleMesh.Builder, spec: Dictionary) -> void:
	var ws: Array = spec["ws"]
	var rear: Array = spec["rear"]
	var wsb: Vector2 = ws[0]
	var rb: Vector2 = rear[0]
	var belt: float = spec["belt"]
	var gw: float = spec["glass_w"]
	var occupants_3d := LadaDriver.uses_3d()
	var y := LadaDriver.LADA_FLOOR - 0.002 if occupants_3d else belt + 0.007
	b.box("dark", Vector3(gw * 2.0 - 0.04, 0.004, rb.y - wsb.y - 0.02), Vector3(0, y, (wsb.y + rb.y) * 0.5))
	if occupants_3d:
		for side: float in [-1.0, 1.0]:
			b.triangle_part = &"inner_wall_l" if side < 0 else &""
			b.box("dark", Vector3(0.024, belt - LadaDriver.LADA_FLOOR, rb.y - wsb.y - 0.18), Vector3(side * (gw - 0.035), (belt + LadaDriver.LADA_FLOOR) * 0.5, (wsb.y + rb.y) * 0.5))
		b.triangle_part = &""
		b.box("dark", Vector3(gw * 2.0 - 0.08, belt - LadaDriver.LADA_FLOOR, 0.024), Vector3(0, (belt + LadaDriver.LADA_FLOOR) * 0.5, wsb.y + 0.10))
		b.box("dark", Vector3(gw * 2.0 - 0.08, belt - LadaDriver.LADA_FLOOR, 0.024), Vector3(0, (belt + LadaDriver.LADA_FLOOR) * 0.5, rb.y - 0.10))
		b.rbox("cloth", Vector3(0.50, 0.12, 0.50), Vector3(-0.345, 0.37, -0.10), 0.04)
		b.rbox("cloth", Vector3(0.48, 0.42, 0.08), Vector3(-0.345, 0.60, 0.12), 0.03, Basis(Vector3.RIGHT, -0.10))
	b.rbox("dark", Vector3(gw * 2.0 - 0.1, 0.12, 0.3), Vector3(0, belt + 0.06, wsb.y + 0.13), 0.04)
	# Руль: обод трубками, наклон к водителю, колонка к торпедо.
	var center := Vector3(-0.36, belt + 0.13, wsb.y + 0.3)
	var ax := Vector3.RIGHT
	var ay := Vector3(0.0, 0.87, -0.5)
	var ring := PackedVector3Array()
	for k in 12:
		var t := TAU * k / 12.0
		ring.append(center + (ax * cos(t) + ay * sin(t)) * 0.18)
	for k in 12:
		b.tube("dark", ring[k], ring[(k + 1) % 12], 0.014, 4)
	b.tube("dark", center, center + Vector3(0.0, -0.08, -0.16), 0.02, 4)
	b.tube("dark", center - ax * 0.17, center + ax * 0.17, 0.012, 4)
	# Пассажир справа: спинка и подголовник; задний диван — ниже линии окон.
	b.rbox("cloth", Vector3(0.48, 0.18, 0.1), Vector3(0.36, belt + 0.09, 0.45), 0.04)
	b.rbox("cloth", Vector3(0.24, 0.15, 0.08), Vector3(0.36, belt + 0.245, 0.47), 0.04)
	b.rbox("cloth", Vector3(gw * 2.0 - 0.2, 0.06, 0.12), Vector3(0, belt + 0.02, rb.y - 0.28), 0.03)
	b.rbox("dark", Vector3(0.18, 0.05, 0.02), Vector3(0, float(spec["roof_y"]) - 0.1, wsb.y + 0.32), 0.01)   # зеркало заднего вида

## Детали кузова: перед, зад, бамперы, номера, борта (швы дверей, ручки, молдинг, зеркала), дворники, антенна, днище.
static func _details(b: VehicleMesh.Builder, spec: Dictionary, hl: float, w: float, belt: float, r: float, arch: float,
		axles: Array, bottom: Array) -> void:
	var front: String = spec["front"]
	var fz := -hl
	var rz := hl
	var face := w - float(spec["round"])   # полуширина торца
	var ws: Array = spec["ws"]
	var wsb: Vector2 = ws[0]
	var bz: float = spec["b_z"]
	var cz: Array = spec["c_z"]
	var chrome := "alu" if front == "rect" else "chrome"
	match front:
		"rect":
			# 2105: единая плоская маска, широкие блок-фары и чёрные горизонтальные рёбра.
			b.box("dark", Vector3(1.49, 0.235, 0.026), Vector3(0, 0.765, fz - 0.008))
			for y in [0.68, 0.72, 0.76, 0.80, 0.84]:
				b.box("trim", Vector3(0.73, 0.014, 0.022), Vector3(0, y, fz - 0.03))
			for s in [-1.0, 1.0]:
				b.box("alu", Vector3(0.33, 0.203, 0.018), Vector3(s * 0.535, 0.765, fz - 0.026))
				b.box("head", Vector3(0.303, 0.18, 0.018), Vector3(s * 0.535, 0.765, fz - 0.04))
				b.box("lens_amber", Vector3(0.064, 0.18, 0.02), Vector3(s * 0.727, 0.765, fz - 0.035))
		"round4":
			# 2106: две пары фар в отдельных чёрных чашках; между ними хромированная сетка.
			b.rbox("chrome", Vector3(1.51, 0.25, 0.022), Vector3(0, 0.77, fz - 0.004), 0.012)
			b.box("trim", Vector3(1.47, 0.218, 0.028), Vector3(0, 0.77, fz - 0.016))
			for y in [0.68, 0.725, 0.77, 0.815, 0.86]:
				b.box("chrome", Vector3(0.63, 0.009, 0.012), Vector3(0, y, fz - 0.035))
			for k in 13:
				b.box("chrome", Vector3(0.007, 0.19, 0.009), Vector3(-0.3 + k * 0.05, 0.77, fz - 0.036))
			for s in [-1.0, 1.0]:
				for x in [0.425, 0.635]:
					_disc(b, "head", Vector3(s * x, 0.77, fz - 0.04), 0.087, false)
					_disc(b, "chrome", Vector3(s * x, 0.77, fz - 0.035), 0.099, false, true)
				b.rbox("chrome", Vector3(0.22, 0.075, 0.022), Vector3(s * 0.63, 0.595, fz - 0.035), 0.008)
				b.box("lens_amber", Vector3(0.14, 0.055, 0.023), Vector3(s * 0.655, 0.595, fz - 0.05))
				b.box("lens_white", Vector3(0.055, 0.055, 0.023), Vector3(s * 0.55, 0.595, fz - 0.05))
		"volga":
			# ГАЗ-24: высокая широкая решётка с частыми вертикальными зубьями и две фары.
			b.rbox("chrome", Vector3(1.68, 0.305, 0.025), Vector3(0, 0.745, fz - 0.005), 0.018)
			b.box("trim", Vector3(1.16, 0.27, 0.03), Vector3(0, 0.745, fz - 0.02))
			for k in 29:
				var x := -0.55 + k * 1.1 / 28.0
				b.tube("chrome", Vector3(x, 0.615, fz - 0.034), Vector3(x * 0.96, 0.875, fz - 0.034), 0.009, 4)
			for s in [-1.0, 1.0]:
				_disc(b, "trim", Vector3(s * 0.715, 0.745, fz - 0.025), 0.135, false)
				_disc(b, "head", Vector3(s * 0.715, 0.745, fz - 0.046), 0.108, false)
				_disc(b, "chrome", Vector3(s * 0.715, 0.745, fz - 0.038), 0.126, false, true)
				b.rbox("chrome", Vector3(0.22, 0.075, 0.022), Vector3(s * 0.72, 0.56, fz - 0.035), 0.008)
				b.box("lens_amber", Vector3(0.20, 0.055, 0.025), Vector3(s * 0.72, 0.56, fz - 0.05))
	# Бамперы: у «пятёрки» алюминиевый брус с пластиковыми концами и резиновой полосой, у остальных — хром с клыками.
	for end in [-1.0, 1.0]:
		var e: float = end
		var z := e * (hl + 0.055)
		b.rbox(chrome, Vector3(face * 2.0 - 0.1, 0.11, 0.07), Vector3(0, 0.49, z), 0.03)
		b.rbox("trim", Vector3(face * 2.0 - 0.14, 0.055 if front == "rect" else 0.022, 0.075), Vector3(0, 0.545, z), 0.01)
		for s in [-1.0, 1.0]:
			b.rbox("trim" if front == "rect" else chrome, Vector3(0.2, 0.12, 0.1), Vector3(s * (face - 0.02), 0.49, e * (hl + 0.03)), 0.035,
				Basis(Vector3.UP, s * e * 0.25))
			b.rbox("trim" if front == "rect" else chrome, Vector3(0.05, 0.11, 0.24), Vector3(s * (w - 0.01), 0.49, e * (hl - 0.07)), 0.02)
			if front != "rect":
				b.rbox(chrome, Vector3(0.05, 0.17, 0.054), Vector3(s * 0.34, 0.5, e * (hl + 0.085)), 0.02)
				b.box("trim", Vector3(0.035, 0.145, 0.008), Vector3(s * 0.34, 0.5, e * (hl + 0.116)))
		# Номер: белая пластина в чёрной рамке.
		var plate_at := Vector3(0, 0.49, -hl - 0.1) if e < 0.0 else Vector3(0, 0.66, hl + 0.012)
		b.box("trim", Vector3(0.53, 0.122, 0.006), plate_at + Vector3(0, 0, -e * 0.004))
		b.box("plate", Vector3(0.52, 0.112, 0.008), plate_at)
	# Зад: у каждой модели свой рисунок оптики, красный слот tail сохраняет режим торможения.
	for s in [-1.0, 1.0]:
		if front == "volga":
			# Вертикальные трапеции ГАЗ-24: красный верх, янтарная середина, белый низ.
			var x: float = s * 0.766
			_tail_trapezoid(b, "chrome", x, 0.735, rz + 0.014, 0.165, 0.32, s)
			_tail_trapezoid(b, "tail", x, 0.805, rz + 0.029, 0.131, 0.14, s)
			_tail_trapezoid(b, "lens_amber", x, 0.695, rz + 0.03, 0.133, 0.074, s)
			_tail_trapezoid(b, "lens_white", x, 0.622, rz + 0.03, 0.126, 0.052, s)
		elif front == "round4":
			# 2106: янтарный внешний край и белое окошко внутри красного прямоугольника.
			b.rbox("chrome", Vector3(0.43, 0.19, 0.028), Vector3(s * 0.53, 0.75, rz + 0.008), 0.015)
			b.box("tail", Vector3(0.30, 0.155, 0.023), Vector3(s * 0.48, 0.75, rz + 0.026))
			b.box("lens_amber", Vector3(0.085, 0.155, 0.025), Vector3(s * 0.683, 0.75, rz + 0.027))
			b.box("lens_white", Vector3(0.15, 0.055, 0.026), Vector3(s * 0.49, 0.742, rz + 0.03))
			b.box("trim", Vector3(0.04, 0.175, 0.025), Vector3(s * 0.315, 0.75, rz + 0.023))
		else:
			b.box("trim", Vector3(0.44, 0.185, 0.03), Vector3(s * 0.53, 0.755, rz + 0.005))
			b.box("tail", Vector3(0.235, 0.15, 0.02), Vector3(s * 0.61, 0.755, rz + 0.025))
			b.box("lens_amber", Vector3(0.095, 0.15, 0.021), Vector3(s * 0.435, 0.755, rz + 0.026))
			b.box("lens_white", Vector3(0.065, 0.15, 0.021), Vector3(s * 0.35, 0.755, rz + 0.026))
	if front != "rect":
		b.box("chrome", Vector3(1.30 if front == "volga" else 1.43, 0.018, 0.015), Vector3(0, 0.89, rz + 0.014))
	b.rbox("chrome", Vector3(0.05, 0.03, 0.02), Vector3(0, 0.84, rz + 0.008), 0.008)
	b.tube("dark", Vector3(-0.45, 0.3, rz - 0.12), Vector3(-0.45, 0.29, rz + 0.04), 0.026, 8, true)   # глушитель
	b.tube("steel", Vector3(-0.45, 0.29, rz + 0.03), Vector3(-0.45, 0.29, rz + 0.06), 0.028, 8, true)
	# Швы крышек удерживают три отдельных объёма даже под тонким слоем снега.
	var rear_bottom: Vector2 = spec["rear"][0]
	for side in [-1.0, 1.0]:
		var seam_x: float = side * (w - 0.13)
		for ends in [[fz + 0.16, wsb.y - 0.04], [rear_bottom.y + 0.05, rz - 0.12]]:
			var za: float = ends[0]
			var zb: float = ends[1]
			b.tube("trim", Vector3(seam_x, profile_y(spec, za) + 0.003, za),
				Vector3(seam_x, profile_y(spec, zb) + 0.003, zb), 0.0035, 4)
	# Борта: швы дверей (обходят арку), ручки, молдинг, повторитель поворота, зеркала, лючок бензобака.
	for side in [-1.0, 1.0]:
		var s: float = side
		var x := s * (w + 0.0015)
		for z in [wsb.y + 0.03, bz + 0.01, float(cz[0]) + 0.1]:
			var low := _bottom_at(bottom, axles, r, arch, z) + 0.03
			b.box("dark", Vector3(0.004, belt - 0.02 - low, 0.007), Vector3(x, (belt - 0.02 + low) * 0.5, z))
		for z in [bz - 0.1, float(cz[0]) - 0.02]:
			b.triangle_part = &"door_handle_l" if s < 0 and z == bz - 0.1 else &""
			b.rbox("chrome", Vector3(0.014, 0.024, 0.11), Vector3(s * (w + 0.008), belt - 0.11, z), 0.008)
		b.triangle_part = &"belt_trim_l" if s < 0 else &""
		b.rbox("trim" if front == "rect" else "chrome", Vector3(0.012, 0.035, hl * 2.0 - 0.7), Vector3(s * (w + 0.004), r + arch + 0.05, 0.0), 0.006)
		b.triangle_part = &""
		b.rbox("lens_amber", Vector3(0.008, 0.03, 0.06), Vector3(s * (w + 0.003), belt - 0.18, -hl + 0.45), 0.004)
		var mirror := Vector3(s * (w + 0.11), belt + 0.06, wsb.y + 0.14)
		b.triangle_part = &"door_mirror_l" if s < 0 else &""
		b.tube("trim", Vector3(s * (w - 0.04), belt + 0.01, wsb.y + 0.12), mirror, 0.012, 4)
		b.rbox("trim", Vector3(0.06, 0.09, 0.13), mirror, 0.025)
		b.box("chrome", Vector3(0.045, 0.07, 0.004), mirror + Vector3(0, 0, 0.066))
		b.triangle_part = &""
		# Подкрылки и грязевые щитки — без «сквозного» вида через арку.
		for axle in axles:
			b.box("dark", Vector3(0.008, arch * 1.1, arch * 1.9), Vector3(s * (float(spec["track"]) - 0.12), r + arch * 0.25, axle))
		b.box("dark", Vector3(0.16, 0.22, 0.008), Vector3(s * float(spec["track"]), 0.22, float(axles[1]) + arch + 0.03))
	b.rbox("dark", Vector3(0.008, 0.09, 0.09), Vector3(w + 0.002, belt - 0.13, hl - 0.55), 0.03)   # лючок бензобака справа
	b.box("dark", Vector3(float(spec["track"]) * 2.0 - 0.3, 0.06, hl * 2.0 - 0.8), Vector3(0, 0.24, 0))   # днище
	# Дворники на лобовом стекле и антенна на правом крыле.
	for x0 in [-0.62, -0.05]:
		b.tube("trim", Vector3(x0, wsb.x + 0.02, wsb.y + 0.03), Vector3(x0 + 0.5, wsb.x + 0.035, wsb.y + 0.06), 0.009, 4)
		b.tube("trim", Vector3(x0 + 0.1, wsb.x - 0.01, wsb.y - 0.06), Vector3(x0 + 0.22, wsb.x + 0.03, wsb.y + 0.045), 0.007, 4)
	var mast := Vector3(w - 0.09, profile_y(spec, -hl + 0.85), -hl + 0.85)
	var mast_top := Vector3(mast.x + 0.03, float(spec["aerial_y"]), mast.z + 0.24)
	b.tube("trim", mast, mast_top, 0.004, 4)
	b.tube("chrome", mast - Vector3(0, 0.01, 0), mast + Vector3(0, 0.03, 0), 0.012, 6, true)

## Плоская трапеция фонаря: внешний край наклонён, как на задних крыльях ГАЗ-24.
static func _tail_trapezoid(b: VehicleMesh.Builder, slot: String, x: float, y: float, z: float,
		width: float, height: float, side: float) -> void:
	var hw := width * 0.5
	var hh := height * 0.5
	b.poly(slot, PackedVector3Array([
		Vector3(x - hw, y - hh, z), Vector3(x + hw, y - hh, z),
		Vector3(x + hw - side * 0.025, y + hh, z), Vector3(x - hw - side * 0.025, y + hh, z),
	]), Vector3.BACK)

## Высота верха нижнего кузова в точке z.
static func profile_y(spec: Dictionary, z: float) -> float:
	return VehicleMesh.profile(spec["top"], z)

static func _bottom_at(bottom: Array, axles: Array, r: float, arch: float, z: float) -> float:
	var yb := VehicleMesh.profile(bottom, z)
	for axle in axles:
		var dz := z - float(axle)
		if absf(dz) <= arch:
			yb = maxf(yb, r + sqrt(arch * arch - dz * dz))
	return yb

## Круглое стекло фары или хромированный ободок (ring) в плоскости торца; back — смотрит назад (+Z).
static func _disc(b: VehicleMesh.Builder, slot: String, at: Vector3, radius: float, back: bool, ring := false) -> void:
	var keep := b.xf
	b.xf = b.xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5 if back else -PI * 0.5), at)
	if ring:
		b.lathe(slot, PackedVector2Array([Vector2(radius * 0.84, 0.004), Vector2(radius, 0.0), Vector2(radius * 1.02, -0.012)]), 16, Vector3.ZERO)
	else:
		b.lathe(slot, PackedVector2Array([Vector2(radius, -0.004), Vector2(radius * 0.75, 0.01), Vector2(0.001, 0.016)]), 16, Vector3.ZERO)
	b.xf = keep

## Снег: подушки на крыше, капоте и багажнике, валик у основания лобового стекла (кадры 01, 04).
static func snow_mesh(model: StringName, depth: float) -> ArrayMesh:
	var d := snappedf(depth, 0.02)
	var key := "sedan_snow_%s_%s" % [model, VehicleMesh.snf(d)]
	var mesh: ArrayMesh = VehicleMesh.cached(key)
	if mesh != null:
		return mesh
	var spec: Dictionary = SEDANS[model]
	var b := VehicleMesh.Builder.new()
	var ws: Array = spec["ws"]
	var rear: Array = spec["rear"]
	var wsb: Vector2 = ws[0]
	var wst: Vector2 = ws[1]
	var rb: Vector2 = rear[0]
	var rt: Vector2 = rear[1]
	var hl: float = spec["length"] * 0.5
	var w: float = spec["half_w"]
	var roof_y: float = spec["roof_y"]
	var rw: float = spec["roof_w"]
	b.pillow("snow", Vector3(0, 0, (wst.y + rt.y) * 0.5), rw * 2.0 - 0.1, rt.y - wst.y - 0.08, d, roof_y, roof_y, 1)
	var hood_front := -hl + 0.2
	var hood_back := wsb.y - 0.06
	b.pillow("snow", Vector3(0, 0, (hood_front + hood_back) * 0.5), w * 2.0 - 0.22, hood_back - hood_front, d * 0.6,
		profile_y(spec, hood_front), profile_y(spec, hood_back), 2)
	var trunk_front := rb.y + 0.08
	var trunk_back := hl - 0.15
	b.pillow("snow", Vector3(0, 0, (trunk_front + trunk_back) * 0.5), w * 2.0 - 0.24, trunk_back - trunk_front, d * 0.6,
		profile_y(spec, trunk_front), profile_y(spec, trunk_back), 3)
	b.pillow("snow", Vector3(0, 0, wsb.y - 0.03), w * 2.0 - 0.3, 0.14, d * 0.7, wsb.x - 0.01, wsb.x - 0.005, 4, 7, 3)
	mesh = VehicleMesh.finish(b)
	return VehicleMesh.store(key, mesh)

static func _beams(body: Node3D, model: StringName) -> void:
	var spec: Dictionary = SEDANS[model]
	# Два луча от внешних фар; четыре стекла фар разделяют светящийся материал head.
	var head_x := 0.635 if spec["front"] == "round4" else 0.535
	var head_y := 0.77 if spec["front"] == "round4" else 0.765
	for side in [["BeamLeft", -head_x], ["BeamRight", head_x]]:
		var beam := SpotLight3D.new()
		beam.name = side[0]
		beam.position = Vector3(side[1], head_y, -float(spec["length"]) * 0.5 - 0.06)
		beam.rotation.x = deg_to_rad(-5.0)   # чуть вниз: пятно ложится на дорогу в 6–20 м впереди
		beam.light_color = BEAM_COLOR
		beam.light_energy = BEAM_ENERGY
		beam.spot_range = BEAM_RANGE
		beam.spot_angle = 28.0
		beam.spot_angle_attenuation = 0.8
		beam.spot_attenuation = 0.6
		preload("res://game/world/lighting.gd").configure_local_shadow(beam)
		beam.light_specular = 0.6
		beam.visible = false
		body.add_child(beam)

## Номер: надпись на белой пластине кузова (пластина — в общем меше).
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

## Движение облика «Лады» игрока: колёса крутятся по пройденному пути, передние поворачиваются по скорости
## поворота, кузов чуть клюёт при торможении и кренится в повороте (подвеска — только вид).
class Motion extends Node3D:
	var wheels: Array[Node3D] = []
	var steer: Array[Node3D] = []
	var body: Node3D
	var radius := 0.3
	var _last := Vector3.ZERO
	var _yaw := 0.0
	var _speed := 0.0
	var _started := false

	func _process(delta: float) -> void:
		var visual := get_parent() as Node3D
		if visual == null or delta <= 0.0:
			return
		var p := visual.global_position
		var yaw := visual.global_rotation.y
		if not _started or p.distance_to(_last) > 3.0:   # первая рамка или перестановка reset_to
			_started = true
			_last = p
			_yaw = yaw
			return
		var forward := -visual.global_basis.z
		var dist := (p - _last).dot(forward)
		var speed := dist / delta
		var yaw_rate := angle_difference(_yaw, yaw) / delta
		_last = p
		_yaw = yaw
		for wheel in wheels:
			wheel.rotate_object_local(Vector3.UP, -dist / radius)
		var angle := 0.0
		if absf(speed) > 0.5:
			angle = clampf(atan(2.42 * yaw_rate / speed), -0.5, 0.5)
		var k := 1.0 - exp(-10.0 * delta)
		for pivot in steer:
			pivot.rotation.y = lerpf(pivot.rotation.y, angle, k)
		var accel := (speed - _speed) / delta
		_speed = speed
		if body:
			var soft := 1.0 - exp(-6.0 * delta)
			body.rotation.x = lerpf(body.rotation.x, clampf(accel * 0.0025, -0.035, 0.03), soft)
			body.rotation.z = lerpf(body.rotation.z, clampf(-speed * yaw_rate * 0.004, -0.035, 0.035), soft)
