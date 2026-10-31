class_name Trolleybus
extends PathVehicle
## Троллейбус ЗиУ-9 маршрута 13 на кольце (ARENA-01, часть T, C8). Облик — перенос `_trolleybus(size)` (удалён) из
## level_geometry.gd (ART-06: по фото владельца `Novosibirsk_KrasnyProspekt_trolley_07-2016_img1.jpg` — кузов
## целиком зелёный, тёмный бампер, светлая решётка, белое табло «13», бортовой номер жёлтым и белым) в системе
## координат транспорта: перед — −Z, двери — справа (+X), к тротуару при правостороннем движении.
## Штанги — назад и влево вверх, к контактному проводу над осью улицы (визуально, без логики).
## Остановки Layout.TROLLEY_STOPS: плавное торможение до точки, 6 с стоя с открытыми дверями
## (сигналы doors_opened / doors_closed — звук даёт SoundDirector), затем дальше по кругу. Скорость 7 м/с.

const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const CabinScript = preload("res://game/vehicles/trolley_cabin.gd")

signal doors_opened(stop_index: int)
signal doors_closed(stop_index: int)

const BODY := Vector3(11.9, 3.35, 2.5)   # ЗиУ-9: 11 888 × 3347 × 2500 мм — вдоль, высота, поперёк (как в Layout)
const DWELL := 6.0
const STOP_DECEL := 1.2
const CONTACT_Y := 7.0                   # высота контактного провода (как в level_geometry.gd)
const WIRE_LEFT: Array[float] = [1.5, 4.5]   # провода над осью улицы: левее правой полосы на 1,5 и 4,5 м

var occupants_enabled := true
var stop_offsets: Array[float] = []
var next_stop := 0
var dwell_left := 0.0
var stops_made := 0
var doors_open := false
var _door_panels: Array[Node3D] = []
var _door_openings: Array[Node3D] = []
## TROLLEY-01: водитель и пассажиры (trolley_cabin.gd) — ребёнок Body, без коллизий.
var people: Node3D

func _init() -> void:
	super._init()
	size = Vector3(BODY.z, BODY.y, BODY.x)
	wheelbase = 6.2
	wheel_radius = 0.5
	cruise_speed = 7.0
	corner_speed = 4.0

func setup(lane_path: LanePath, offset: float) -> void:
	super.setup(lane_path, offset)
	stop_offsets.clear()
	for p in Layout.TROLLEY_STOPS:
		stop_offsets.append(path.offset_of(p))
	# Ближайшая остановка впереди.
	var best := INF
	for i in stop_offsets.size():
		var d := fposmod(stop_offsets[i] - s, path.length)
		if d < best:
			best = d
			next_stop = i

func _tick(delta: float) -> void:
	if people:
		people.tick(delta, doors_open)
	if dwell_left <= 0.0:
		return
	dwell_left -= delta
	if dwell_left <= 0.0:
		dwell_left = 0.0
		_set_doors(false)
		doors_closed.emit(next_stop)
		next_stop = (next_stop + 1) % stop_offsets.size()

func _extra_limit() -> float:
	if dwell_left > 0.0:
		return 0.0
	if stop_offsets.is_empty():
		return INF
	var d := fposmod(stop_offsets[next_stop] - s, path.length)
	return maxf(sqrt(2.0 * STOP_DECEL * d), 0.4)

func _limit_step(step: float) -> float:
	if dwell_left > 0.0:
		return 0.0
	if stop_offsets.is_empty():
		return step
	var d := fposmod(stop_offsets[next_stop] - s, path.length)
	if d <= step and d < 1.0:
		dwell_left = DWELL
		speed = 0.0
		stops_made += 1
		_set_doors(true)
		doors_opened.emit(next_stop)
		return d
	return step

func _set_doors(open: bool) -> void:
	doors_open = open
	for panel in _door_panels:
		panel.visible = not open
	for opening in _door_openings:
		opening.visible = open


# --- облик (CITY-02 V): своя геометрия в осях транспорта — перед −Z, двери справа (+X), начало на земле ---
# Кузов — лофт сечений со скруглёнными углами в плане и скруглённой крышей; оконный пояс открыт: окна в чёрных
# резинках (шейдер стекла), за ними салон — сиденья, жёлтые поручни, плафоны. Двери — двустворчатые остеклённые.

const HALF_LEN := 5.95
const HALF_W := 1.25
const SILL := 1.72                 # низ окон
const EAVE := 2.92                 # верх окон, низ крыши
const AXLES: Array[float] = [-3.3, 2.9]   # передняя ось в 2,65 м от передка, база 6,2 м
## Двери к тротуару (+X): [центр по z, ширина] — узкая передняя, широкие средняя и задняя (ART-06).
const DOORS := [[-4.1, 0.9], [-0.2, 1.4], [4.05, 1.4]]
const GREEN := Color(0.02, 0.56, 0.25)

func _build_visual() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var meshes := _meshes()
	var head := _lamp(Color(1.0, 0.96, 0.85), Color(1.0, 0.92, 0.75), 2.4)
	VehicleMesh.instance(body, "BodyMesh", meshes["body"], {"head": head, "tail": _tail})
	VehicleMesh.instance(body, "Glass", meshes["glass"], {}, false)
	var cabin := VehicleMesh.instance(body, "Interior", meshes["interior"], {}, false)
	cabin.visibility_range_end = 60.0
	VehicleMesh.instance(body, "Snow", meshes["snow"])
	# Двери: закрытые створки и открытый проём (видимость переключает _set_doors). Проём — тёмная глубина салона со
	# светом плафона сверху, ступени с жёлтой кромкой, поручень, сложенные створки по краям (CITY-02 F: был бежевый щит).
	for door in DOORS:
		var at := Vector3(HALF_W + 0.012, 0.0, door[0])
		var panel := VehicleMesh.instance(body, "Door", _door_mesh(door[1]), {}, false)
		panel.position = at
		_door_panels.append(panel)
		var opening := VehicleMesh.instance(body, "DoorOpening", _open_door_mesh(door[1]), {}, false)
		opening.position = at
		opening.visible = false
		_door_openings.append(opening)
	_labels(body)
	if occupants_enabled:
		people = CabinScript.new()
		body.add_child(people)
	# Тёплый свет в салоне — виден в окна и в открытые двери; без теней.
	var light := OmniLight3D.new()
	light.name = "CabinLight"
	light.position = Vector3(0, 2.4, 0)
	light.light_color = Color(1.0, 0.82, 0.55)
	light.light_energy = 0.8
	light.omni_range = 5.0
	light.shadow_enabled = false
	light.light_specular = 0.1
	body.add_child(light)
	for z in AXLES:
		for x in [-1.1, 1.1]:
			_wheels.append(VehicleMesh.add_wheel(root, Vector3(x, wheel_radius, z), wheel_radius, 0.3, "bus"))
	return root

## TROLLEY-01: жители в поездке (Residents) — в салон тем же обликом; вышедшие пропадают из салона.
func set_riders(list: Array) -> void:
	if people:
		people.set_riders(list)

## Надписи: табло «13» спереди (с конечными) и сзади, табличка «13» у передней двери с обеих сторон, бортовой номер
## 3271 (первые цифры жёлтые, последние белые) спереди и на бортах.
func _labels(body: Node3D) -> void:
	var labels := [
		["13", 115, Color(0.05, 0.05, 0.05), Vector3(0, 3.04, -HALF_LEN - 0.035), PI],
		["Учительская", 22, Color(0.75, 0.1, 0.08), Vector3(0.62, 3.1, -HALF_LEN - 0.035), PI],
		["Речной вокзал", 22, Color(0.75, 0.1, 0.08), Vector3(-0.62, 3.1, -HALF_LEN - 0.035), PI],
		["13", 140, Color(0.05, 0.05, 0.05), Vector3(0, 3.06, HALF_LEN + 0.035), 0.0],
		["13", 60, Color(0.05, 0.05, 0.05), Vector3(HALF_W + 0.04, 1.6, -2.95), PI * 0.5],
		["13", 60, Color(0.05, 0.05, 0.05), Vector3(-HALF_W - 0.04, 1.6, -2.95), -PI * 0.5],
	]
	for spec in labels:
		var label := _label(spec[0], spec[1], spec[2])
		label.position = spec[3]
		label.rotation.y = spec[4]
		label.visibility_range_end = 90.0
		body.add_child(label)
	for spot in [[Vector3(0.75, 1.45, -HALF_LEN - 0.03), PI], [Vector3(HALF_W + 0.03, 1.05, -2.0), PI * 0.5], [Vector3(-HALF_W - 0.03, 1.05, -2.0), -PI * 0.5]]:
		var yaw_s: float = spot[1]
		var right := Basis(Vector3.UP, yaw_s) * Vector3.RIGHT   # «вправо» для того, кто смотрит на надпись
		for part in [["32", Color(1.0, 0.82, 0.10), -0.19], ["71", Color(0.96, 0.96, 0.94), 0.19]]:
			var digits := _label(part[0], 80, part[1])
			digits.position = spot[0] + right * float(part[2])
			digits.rotation.y = yaw_s
			digits.visibility_range_end = 60.0
			body.add_child(digits)

## Отрезки борта без дверей: [начало, конец] по z в пределах оконного пояса.
static func _free_spans(right: bool) -> Array:
	var spans := [[-5.55, 5.6]]
	if not right:
		return spans
	for door in DOORS:
		var a: float = float(door[0]) - float(door[1]) * 0.5 - 0.06
		var b: float = float(door[0]) + float(door[1]) * 0.5 + 0.06
		var next := []
		for span in spans:
			if b <= span[0] or a >= span[1]:
				next.append(span)
				continue
			if a > span[0]:
				next.append([span[0], a])
			if b < span[1]:
				next.append([b, span[1]])
		spans = next
	return spans

## The old closed lower-body loft had a full-width lid at the window sill.
## Keep the exact outer section vertices/arches and both end caps, but leave the
## passenger volume open above the floor instead of spanning it with green paint.
func _lower_hull_shell(builder: VehicleMesh.Builder, interior: VehicleMesh.Builder, stations: Array) -> void:
	var rows: Array = []
	var closed_rings: Array[PackedVector3Array] = []
	var refs := PackedVector3Array()
	for station: Array in stations:
		var ring := builder.section(station[0], station[1], station[2], station[3], station[4], station[5], station[6])
		closed_rings.append(ring)
		# section starts at the bottom centre; its opposite centre is the sole
		# top-centre point. Start after it and stop before it, leaving no top span.
		var top_centre := int(ring.size() / 2.0)
		var path := PackedVector3Array()
		for offset in ring.size() - 1:
			path.append(ring[(top_centre + 1 + offset) % ring.size()])
		rows.append(path)
		refs.append(Vector3(0.0, (float(station[1]) + float(station[2])) * 0.5, station[0]))
	builder.grid("paint", rows, false, refs)
	builder.cap("paint", closed_rings[0], Vector3.FORWARD)
	builder.cap("paint", closed_rings[-1], Vector3.BACK)
	interior.cap("dark", closed_rings[0], Vector3.BACK)
	interior.cap("dark", closed_rings[-1], Vector3.FORWARD)

func _meshes() -> Dictionary:
	var occupants_3d := CabinScript.uses_3d()
	var cache_key := "trolleybus_3d_occupants" if occupants_3d else "trolleybus"
	var found: Variant = VehicleMesh.cached(cache_key)
	if found != null:
		return found
	var b := VehicleMesh.Builder.new()
	var glass := VehicleMesh.Builder.new()
	var cabin := VehicleMesh.Builder.new()
	var snow := VehicleMesh.Builder.new()
	var hl := HALF_LEN
	var hw := HALF_W
	var r := 0.5
	var arch := r + 0.1
	# Низ кузова до окон: углы в плане скруглены, арки колёс; крыша — скруглённые рёбра, светлая.
	var lower_stations := VehicleMesh.hull_stations(hl * 2.0, hw, [[-hl, SILL], [hl, SILL]], [[-hl, 0.42], [-hl + 0.25, 0.36], [hl - 0.25, 0.36], [hl, 0.42]],
		AXLES, r, arch, 0.3, 0.3, 0.0, 0.08, 0.02, 0.2)
	if occupants_3d:
		_lower_hull_shell(b, cabin, lower_stations)
	else:
		b.loft("paint", lower_stations)
	b.loft("paint", VehicleMesh.hull_stations(hl * 2.0, hw, [[-hl, 3.18], [-hl + 0.12, 3.33], [hl - 0.12, 3.33], [hl, 3.2]], [[-hl, EAVE], [hl, EAVE]],
		[], 0.0, 0.0, 0.3, 0.3, 0.03, 0.01, 0.24, 0.3))
	# Оконный пояс: угловые стойки, простенки между окнами, стёкла в резинках.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.rbox("paint", Vector3(0.3, EAVE - SILL, 0.42), Vector3(sx * (hw - 0.15), (SILL + EAVE) * 0.5, sz * (hl - 0.21)), 0.13)
	for side in [-1.0, 1.0]:
		var s: float = side
		var x := s * (hw - 0.025)
		for span in _free_spans(s > 0.0):
			var a: float = span[0]
			var e: float = span[1]
			var count := maxi(1, ceili((e - a) / 1.45))
			var bay := (e - a) / count
			for k in count + 1:
				b.rbox("paint", Vector3(0.06, EAVE - SILL, 0.12), Vector3(x, (SILL + EAVE) * 0.5, a + bay * k), 0.02)
			for k in count:
				var z0 := a + bay * k + 0.06
				var z1 := a + bay * (k + 1) - 0.06
				glass.pane("glass", Vector3(x, SILL + 0.03, z0), Vector3(x, SILL + 0.03, z1), Vector3(x, EAVE - 0.03, z1), Vector3(x, EAVE - 0.03, z0),
					Vector3(s, 0, 0), 0.0, 1, 1)
				if k % 2 == 0:
					glass.pane("glass", Vector3(x + s * 0.006, EAVE - 0.42, z0 + 0.04), Vector3(x + s * 0.006, EAVE - 0.42, (z0 + z1) * 0.5),
						Vector3(x + s * 0.006, EAVE - 0.06, (z0 + z1) * 0.5), Vector3(x + s * 0.006, EAVE - 0.06, z0 + 0.04), Vector3(s, 0, 0), 0.0, 1, 1)   # форточка
		# Юбка понизу между арками, водосток по краю крыши.
		for span in [[-hl + 0.4, AXLES[0] - arch - 0.05], [AXLES[0] + arch + 0.05, AXLES[1] - arch - 0.05], [AXLES[1] + arch + 0.05, hl - 0.4]]:
			b.rbox("bumper_dark", Vector3(0.03, 0.14, float(span[1]) - float(span[0])), Vector3(s * (hw + 0.01), 0.45, (float(span[0]) + float(span[1])) * 0.5), 0.01)
		b.tube("trim", Vector3(s * (hw + 0.005), EAVE + 0.02, -hl + 0.35), Vector3(s * (hw + 0.005), EAVE + 0.02, hl - 0.35), 0.015, 4)
		for axle in AXLES:
			b.box("dark", Vector3(0.01, arch * 1.1, arch * 1.9), Vector3(s * 0.85, r + arch * 0.3, axle))
		# Зеркала на кронштейнах.
		var mirror := Vector3(s * 1.47, 2.12, -hl - 0.2)
		b.tube("trim", Vector3(s * (hw - 0.05), 2.55, -hl + 0.05), mirror + Vector3(0, 0.2, 0), 0.02, 4)
		b.rbox("trim", Vector3(0.06, 0.38, 0.22), mirror, 0.04)
	# Перед: лобовое из двух половин, табло маршрута, решётка, круглые фары, поворотники, бампер, дворники.
	var fz := -hl
	for s in [-1.0, 1.0]:
		glass.pane("glass", Vector3(s * 1.1, SILL + 0.04, fz - 0.005), Vector3(s * 0.04, SILL + 0.04, fz - 0.005),
			Vector3(s * 0.04, EAVE - 0.03, fz + 0.06), Vector3(s * 1.08, EAVE - 0.03, fz + 0.06), Vector3(0, 0.05, -1).normalized(), 0.02, 3, 1)
		_lamp_disc(b, "head", Vector3(s * 0.85, 0.85, fz - 0.02), 0.12)
		_lamp_disc(b, "chrome", Vector3(s * 0.85, 0.85, fz - 0.015), 0.14, true)
		_lamp_disc(b, "lens_white", Vector3(s * 0.6, 0.85, fz - 0.02), 0.06)
		b.rbox("lens_amber", Vector3(0.1, 0.16, 0.03), Vector3(s * 1.04, 0.85, fz - 0.015), 0.02)
		b.tube("trim", Vector3(s * 0.15, SILL + 0.06, fz - 0.03), Vector3(s * 0.85, SILL + 0.12, fz - 0.02), 0.012, 4)
		# Зад: фонари, поворотники.
		b.rbox("tail", Vector3(0.18, 0.3, 0.03), Vector3(s * 0.93, 0.95, hl + 0.015), 0.02)
		b.rbox("lens_amber", Vector3(0.18, 0.12, 0.03), Vector3(s * 0.93, 1.18, hl + 0.015), 0.02)
	b.rbox("trim", Vector3(0.08, EAVE - SILL, 0.06), Vector3(0, (SILL + EAVE) * 0.5, fz + 0.02), 0.02)
	b.rbox("plate", Vector3(1.9, 0.34, 0.03), Vector3(0, 3.04, fz - 0.01), 0.02)
	b.rbox("grille_light", Vector3(1.2, 0.14, 0.04), Vector3(0, 1.2, fz - 0.01), 0.02)
	for y in [1.17, 1.23]:
		b.box("trim", Vector3(1.14, 0.012, 0.01), Vector3(0, y, fz - 0.032))
	for e in [-1.0, 1.0]:
		b.rbox("bumper_dark", Vector3(hw * 2.0 + 0.04, 0.3, 0.14), Vector3(0, 0.5, e * (hl + 0.04)), 0.05)
	# Зад: стена с окном, табло «13».
	b.box("dark", Vector3(1.8, 0.86, 0.02), Vector3(0, 2.45, hl - 0.01))
	b.box("paint", Vector3(2.0, EAVE - SILL, 0.02), Vector3(0, (SILL + EAVE) * 0.5, hl - 0.03))
	glass.pane("glass", Vector3(0.88, 2.04, hl + 0.004), Vector3(-0.88, 2.04, hl + 0.004), Vector3(-0.88, 2.86, hl + 0.004), Vector3(0.88, 2.86, hl + 0.004),
		Vector3(0, 0, 1), 0.0, 1, 1)
	b.rbox("plate", Vector3(1.4, 0.34, 0.03), Vector3(0, 3.06, hl + 0.01), 0.02)
	for s in [-1.0, 1.0]:
		b.rbox("plate", Vector3(0.03, 0.32, 0.9), Vector3(s * (hw + 0.015), 1.6, -2.95), 0.01)
	# Крыша: короб оборудования, основания штанг, штанги к проводам, ловители.
	b.rbox("grey_roof", Vector3(1.6, 0.32, 3.6), Vector3(0, 3.49, 0.8), 0.06)
	for k in 8:
		for s in [-1.0, 1.0]:
			b.box("trim", Vector3(0.01, 0.16, 0.18), Vector3(s * 0.805, 3.49, -0.6 + k * 0.4))
	for left in WIRE_LEFT:
		var from := Vector3(-left * 0.12, 3.7, 1.6)
		var to := Vector3(-left, CONTACT_Y - 0.05, 7.4)
		b.rbox("dark", Vector3(0.3, 0.12, 0.5), Vector3(from.x, 3.68, 1.75), 0.04)
		b.tube("trim", from, to, 0.035, 6, true)
		b.rbox("trim", Vector3(0.08, 0.06, 0.3), to, 0.02)
		b.tube("dark", to + Vector3(0, -0.03, 0), Vector3(from.x * 2.0, 3.2, hl + 0.02), 0.006, 3)   # канат ловителя
	# Салон: пол, потолок с плафонами, сиденья вдоль бортов, поручни, кабина водителя.
	var cabin_floor := CabinScript.INTERIOR_FLOOR_3D if occupants_3d else SILL + 0.006
	cabin.box("dark", Vector3(hw * 2.0 - 0.1, 0.01, hl * 2.0 - 0.4), Vector3(0, cabin_floor - (0.005 if occupants_3d else 0.0), 0))
	cabin.box("ceiling", Vector3(hw * 2.0 - 0.1, 0.01, hl * 2.0 - 0.4), Vector3(0, EAVE - 0.006, 0))
	if occupants_3d:
		for side: float in [-1.0, 1.0]:
			cabin.box("dark", Vector3(0.035, SILL - cabin_floor, hl * 2.0 - 0.5), Vector3(side * (hw - 0.05), (cabin_floor + SILL) * 0.5, 0))
	for s in [-1.0, 1.0]:
		cabin.box("glow", Vector3(0.12, 0.02, hl * 2.0 - 1.4), Vector3(s * 0.55, EAVE - 0.02, 0.2))
		cabin.tube("pole", Vector3(s * 0.55, 2.72, -4.5), Vector3(s * 0.55, 2.72, hl - 0.4), 0.02, 6)
	var z := -3.5
	while z < hl - 0.6:
		for s in [-1.0, 1.0]:
			var blocked := false
			if s > 0.0:
				for door in DOORS:
					if absf(z - float(door[0])) < float(door[1]) * 0.5 + 0.45:
						blocked = true
			if not blocked:
				var back_y := 1.45 if occupants_3d else SILL + 0.16
				cabin.rbox("seat_red", Vector3(0.86, 0.42, 0.07), Vector3(s * 0.72, back_y, z + 0.2), 0.03, Basis(Vector3.RIGHT, -0.12))
				if occupants_3d:
					cabin.rbox("seat_red", Vector3(0.78, 0.10, 0.42), Vector3(s * 0.72, 1.18, z - 0.01), 0.03)
		z += 0.85
	for door in DOORS:
		for dz in [-0.5, 0.5]:
			cabin.tube("pole", Vector3(0.62, SILL, float(door[0]) + dz * float(door[1])), Vector3(0.62, EAVE, float(door[0]) + dz * float(door[1])), 0.02, 6)
	for zp in [-2.4, 1.6, 3.0]:
		cabin.tube("pole", Vector3(-0.2, SILL, zp), Vector3(-0.2, EAVE, zp), 0.02, 6)
	cabin.box("dark", Vector3(1.0, 0.9, 0.04), Vector3(-0.7, SILL + 0.45, -4.55))
	var wheel_at := Vector3(-0.6, SILL + 0.25, -5.35)
	for k in 12:
		var t0 := TAU * k / 12.0
		var t1 := TAU * (k + 1) / 12.0
		var ay := Vector3(0, 0.35, -0.94)
		cabin.tube("dark", wheel_at + (Vector3.RIGHT * cos(t0) + ay * sin(t0)) * 0.24, wheel_at + (Vector3.RIGHT * cos(t1) + ay * sin(t1)) * 0.24, 0.018, 4)
	# Снег на крыше перед и за коробом, на коробе.
	snow.pillow("snow", Vector3(0, 0, -3.3), hw * 2.0 - 0.4, 4.4, 0.1, 3.33, 3.33, 8, 9, 9)
	snow.pillow("snow", Vector3(0, 0, 4.3), hw * 2.0 - 0.4, 2.5, 0.09, 3.33, 3.33, 9)
	snow.pillow("snow", Vector3(0, 0, 0.8), 1.45, 3.4, 0.06, 3.65, 3.65, 10)
	var meshes := {
		"body": VehicleMesh.finish(b, {"paint": VehicleMesh.paint(GREEN, 0.15, 0.9, 0.3, 0.5), "head": VehicleMesh.mat("lens_white"), "tail": VehicleMesh.mat("lens_red")}),
		"glass": VehicleMesh.finish(glass, {"glass": VehicleMesh.glass(0.05, Color(0.06, 0.08, 0.10, 0.62))}),
		"interior": VehicleMesh.finish(cabin, {"glow": VehicleMesh.cabin_glow(1.6)}),
		"snow": VehicleMesh.finish(snow),
	}
	return VehicleMesh.store(cache_key, meshes)

## Закрытая дверь: две остеклённые створки в чёрных рамах на тёмной подложке; начало — середина проёма у борта.
func _door_mesh(width: float) -> ArrayMesh:
	var key := "trolley_door_%s" % VehicleMesh.snf(width)
	var mesh: ArrayMesh = VehicleMesh.cached(key)
	if mesh != null:
		return mesh
	var b := VehicleMesh.Builder.new()
	b.box("dark", Vector3(0.004, 2.4, width), Vector3(-0.004, 1.65, 0))
	var leaf := width * 0.5
	for k in 2:
		var zc := (k - 0.5) * leaf
		for dz in [-0.5, 0.5]:
			b.rbox("trim", Vector3(0.035, 2.38, 0.05), Vector3(0.01, 1.65, zc + dz * (leaf - 0.05)), 0.012)
		for y in [0.47, 1.25, 2.83]:
			b.rbox("trim", Vector3(0.035, 0.05, leaf - 0.04), Vector3(0.01, y, zc), 0.012)
		b.pane("glass", Vector3(0.012, 1.27, zc - leaf * 0.5 + 0.07), Vector3(0.012, 1.27, zc + leaf * 0.5 - 0.07),
			Vector3(0.012, 2.81, zc + leaf * 0.5 - 0.07), Vector3(0.012, 2.81, zc - leaf * 0.5 + 0.07), Vector3(1, 0, 0), 0.0, 1, 1)
		b.pane("glass", Vector3(0.012, 0.5, zc - leaf * 0.5 + 0.07), Vector3(0.012, 0.5, zc + leaf * 0.5 - 0.07),
			Vector3(0.012, 1.23, zc + leaf * 0.5 - 0.07), Vector3(0.012, 1.23, zc - leaf * 0.5 + 0.07), Vector3(1, 0, 0), 0.0, 1, 1)
	mesh = VehicleMesh.finish(b, {"glass": VehicleMesh.glass(0.04, Color(0.06, 0.08, 0.10, 0.62))})
	return VehicleMesh.store(key, mesh)

## Открытая дверь: тёмный проём (салон за ним — в глубине), плафон над ступенями, две ступени с жёлтой кромкой,
## жёлтый поручень посередине и сложенные «гармошкой» створки у краёв; начало — середина проёма у борта.
func _open_door_mesh(width: float) -> ArrayMesh:
	var key := "trolley_door_open_%s" % VehicleMesh.snf(width)
	var mesh: ArrayMesh = VehicleMesh.cached(key)
	if mesh != null:
		return mesh
	var b := VehicleMesh.Builder.new()
	b.box("void", Vector3(0.004, 2.5, width), Vector3(-0.004, 1.6, 0))
	b.box("glow", Vector3(0.01, 0.05, width - 0.3), Vector3(0.0, 2.78, 0))
	for k in 2:
		var y := 0.38 + 0.36 * k
		b.box("steel", Vector3(0.05 + 0.1 * (1 - k), 0.04, width - 0.12), Vector3(0.0, y, 0))
		b.box("pole", Vector3(0.012, 0.03, width - 0.12), Vector3(0.03 + 0.05 * (1 - k), y + 0.02, 0))
	b.tube("pole", Vector3(0.06, 0.45, 0.0), Vector3(0.06, 2.85, 0.0), 0.02, 6)
	b.tube("pole", Vector3(0.05, 1.05, -width * 0.5 + 0.12), Vector3(0.05, 1.85, -width * 0.5 + 0.12), 0.018, 6)
	b.tube("pole", Vector3(0.05, 1.05, width * 0.5 - 0.12), Vector3(0.05, 1.85, width * 0.5 - 0.12), 0.018, 6)
	for e: float in [-1.0, 1.0]:
		var z := e * (width * 0.5 - 0.1)
		b.rbox("trim", Vector3(0.05, 2.38, 0.2), Vector3(0.01, 1.65, z), 0.012)
		b.pane("glass", Vector3(0.04, 1.3, z - 0.07), Vector3(0.04, 1.3, z + 0.07), Vector3(0.04, 2.75, z + 0.07), Vector3(0.04, 2.75, z - 0.07), Vector3(1, 0, 0), 0.0, 1, 1)
	mesh = VehicleMesh.finish(b, {"void": Materials.plain(Color(0.015, 0.014, 0.013), 0.95), "glow": VehicleMesh.cabin_glow(1.6),
		"glass": VehicleMesh.glass(0.04, Color(0.06, 0.08, 0.10, 0.62))})
	return VehicleMesh.store(key, mesh)

## Круглое стекло фары (или хромированный ободок) в плоскости передка, смотрит вперёд (−Z).
static func _lamp_disc(b: VehicleMesh.Builder, slot: String, at: Vector3, radius: float, ring := false) -> void:
	var keep := b.xf
	b.xf = b.xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at)
	if ring:
		b.lathe(slot, PackedVector2Array([Vector2(radius * 0.84, 0.004), Vector2(radius, 0.0), Vector2(radius * 1.02, -0.012)]), 16, Vector3.ZERO)
	else:
		b.lathe(slot, PackedVector2Array([Vector2(radius, -0.004), Vector2(radius * 0.75, 0.012), Vector2(0.001, 0.02)]), 16, Vector3.ZERO)
	b.xf = keep
