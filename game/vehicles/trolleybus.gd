class_name Trolleybus
extends PathVehicle
## Троллейбус ЗиУ-9 маршрута 13 на кольце (ARENA-01, часть T, C8). Облик — перенос `_trolleybus(size)` из
## level_geometry.gd (ART-06: по фото владельца `Novosibirsk_KrasnyProspekt_trolley_07-2016_img1.jpg` — кузов
## целиком зелёный, тёмный бампер, светлая решётка, белое табло «13», бортовой номер жёлтым и белым) в системе
## координат транспорта: перед — −Z, двери — справа (+X), к тротуару при правостороннем движении.
## Штанги — назад и влево вверх, к контактному проводу над осью улицы (визуально, без логики).
## Остановки Layout.TROLLEY_STOPS: плавное торможение до точки, 6 с стоя с открытыми дверями
## (сигналы doors_opened / doors_closed — звук даёт SoundDirector), затем дальше по кругу. Скорость 7 м/с.

signal doors_opened(stop_index: int)
signal doors_closed(stop_index: int)

const BODY := Vector3(11.9, 3.35, 2.5)   # ЗиУ-9: 11 888 × 3347 × 2500 мм — вдоль, высота, поперёк (как в Layout)
const DWELL := 6.0
const STOP_DECEL := 1.2
const CONTACT_Y := 7.0                   # высота контактного провода (как в level_geometry.gd)
const WIRE_LEFT: Array[float] = [1.5, 4.5]   # провода над осью улицы: левее правой полосы на 1,5 и 4,5 м

var stop_offsets: Array[float] = []
var next_stop := 0
var dwell_left := 0.0
var stops_made := 0
var doors_open := false
var _door_panels: Array[Node3D] = []
var _door_openings: Array[Node3D] = []

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

# --- облик: построение в осях `_trolleybus` (перед −x, двери −z, начало на земле), узел повёрнут на −90° ---

func _build_visual() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	body.rotation.y = -PI * 0.5   # (−x → −Z: перед), (−z → +X: двери справа)
	root.add_child(body)
	var hx := BODY.x * 0.5
	var hz := BODY.z * 0.5
	var base := 0.0
	var green := Materials.plain(Color(0.02, 0.56, 0.25), 0.45)
	var dark := Materials.plain(Color(0.12, 0.14, 0.18), 0.6)
	var glass := Materials.plain(Color(0.05, 0.07, 0.09), 0.1)
	var light_grey := Materials.plain(Color(0.73, 0.75, 0.77), 0.5)
	var white := Materials.plain(Color(0.92, 0.92, 0.90), 0.6)
	# Кузов: низ, оконный пояс со стойками, верх, крыша.
	_box(body, "Lower", Vector3(BODY.x, 1.65, BODY.z), Vector3(0, base + 0.35 + 0.825, 0), green)
	_box(body, "Windows", Vector3(BODY.x - 0.2, 1.25, BODY.z - 0.06), Vector3(0.05, base + 2.62, 0), glass, false)
	_box(body, "Upper", Vector3(BODY.x, 0.7, BODY.z), Vector3(0, base + 3.0, 0), green)
	_box(body, "Roof", Vector3(BODY.x - 0.3, 0.06, BODY.z - 0.2), Vector3(0, base + BODY.y - 0.02, 0), light_grey)
	var x := -hx + 2.6
	while x < hx - 0.2:
		for side in [-1.0, 1.0]:
			_box(body, "Pillar", Vector3(0.16, 1.25, 0.04), Vector3(x, base + 2.62, side * (hz - 0.005)), green, false)
		x += 1.45
	# Двери к тротуару (−z): узкая передняя, широкие средняя и задняя. Открытые — тёмный проём с тёплым светом.
	var opening_material := Materials.plain(Color(0.16, 0.13, 0.09), 0.9, Color(1.0, 0.72, 0.40), 0.18)
	for door in [[-hx + 1.85, 0.9], [-0.2, 1.4], [hx - 1.9, 1.4]]:
		var panel := _box(body, "Door", Vector3(door[1], 2.0, 0.04), Vector3(door[0], base + 1.45, -hz - 0.01), glass, false)
		var frame := _box(body, "DoorFrame", Vector3(0.06, 2.0, 0.05), Vector3(door[0], base + 1.45, -hz - 0.02), green, false)
		var opening := _box(body, "DoorOpening", Vector3(door[1], 2.0, 0.03), Vector3(door[0], base + 1.45, -hz - 0.012), opening_material, false)
		opening.visible = false
		_door_panels.append(panel)
		_door_panels.append(frame)
		_door_openings.append(opening)
	# Тёмный бампер и юбка понизу.
	_box(body, "BumperFront", Vector3(0.12, 0.3, BODY.z + 0.04), Vector3(-hx - 0.04, base + 0.5, 0), dark)
	_box(body, "BumperRear", Vector3(0.12, 0.3, BODY.z + 0.04), Vector3(hx + 0.04, base + 0.5, 0), dark)
	for side in [-1.0, 1.0]:
		_box(body, "Skirt", Vector3(BODY.x, 0.12, 0.03), Vector3(0, base + 0.42, side * (hz + 0.01)), dark, false)
	# Перед: лобовое из двух половин, табло маршрута, решётка, круглые фары, поворотники, зеркала.
	for zs in [-0.62, 0.62]:
		_box(body, "Windshield", Vector3(0.05, 1.25, 1.1), Vector3(-hx - 0.02, base + 1.95, zs), glass, false)
	_box(body, "WindshieldBar", Vector3(0.06, 1.3, 0.12), Vector3(-hx - 0.03, base + 1.95, 0), dark, false)
	_box(body, "RouteBoard", Vector3(0.05, 0.42, 1.9), Vector3(-hx - 0.03, base + 2.86, 0), Materials.plain(Color(0.92, 0.92, 0.90), 0.6, Color(1.0, 0.98, 0.9), 0.4), false)
	_box(body, "Grille", Vector3(0.05, 0.14, 1.2), Vector3(-hx - 0.03, base + 1.2, 0), light_grey, false)
	var head := _lamp(Color(1.0, 0.96, 0.85), Color(1.0, 0.92, 0.75), 2.4)
	var amber := Materials.plain(Color(0.95, 0.5, 0.1), 0.3)
	for zs in [-0.85, 0.85]:
		var lamp := _cylinder(body, "Headlight", 0.12, 0.06, Vector3(-hx - 0.04, base + 0.85, zs), head)
		lamp.rotation.z = PI * 0.5
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box(body, "Turn", Vector3(0.05, 0.16, 0.1), Vector3(-hx - 0.03, base + 0.85, zs * 1.22), amber, false)
		_box(body, "Mirror", Vector3(0.05, 0.36, 0.2), Vector3(-hx - 0.25, base + 2.05, zs * 1.62), dark, false)
		_box(body, "Taillight", Vector3(0.04, 0.3, 0.18), Vector3(hx + 0.05, base + 0.95, zs * 1.1), _tail, false)
	var labels := [
		["13", 115, Color(0.05, 0.05, 0.05), Vector3(-hx - 0.07, base + 2.86, 0), -PI * 0.5],
		["Учительская", 22, Color(0.75, 0.1, 0.08), Vector3(-hx - 0.07, base + 2.95, -0.62), -PI * 0.5],
		["Речной вокзал", 22, Color(0.75, 0.1, 0.08), Vector3(-hx - 0.07, base + 2.95, 0.62), -PI * 0.5],
		["13", 140, Color(0.05, 0.05, 0.05), Vector3(hx + 0.07, base + 2.86, 0), PI * 0.5],
	]
	for spec in labels:
		var label := _label(spec[0], spec[1], spec[2])
		label.position = spec[3]
		label.rotation.y = spec[4]
		body.add_child(label)
	# Табло сзади и сбоку у передней двери; бортовой номер: первые цифры жёлтые, последние белые.
	_box(body, "RearBoard", Vector3(0.05, 0.42, 1.4), Vector3(hx + 0.03, base + 2.86, 0), white, false)
	for side in [-1.0, 1.0]:
		_box(body, "SideBoard", Vector3(0.9, 0.32, 0.03), Vector3(-hx + 3.0, base + 1.6, side * (hz + 0.02)), white, false)
		var board := _label("13", 60, Color(0.05, 0.05, 0.05))
		board.position = Vector3(-hx + 3.0, base + 1.6, side * (hz + 0.04))
		board.rotation.y = PI if side < 0.0 else 0.0
		body.add_child(board)
	for spot in [[Vector3(-hx - 0.07, base + 1.25, -0.6), -PI * 0.5], [Vector3(-2.0, base + 1.05, -hz - 0.04), PI], [Vector3(-2.0, base + 1.05, hz + 0.04), 0.0]]:
		var yaw_s: float = spot[1]
		var right := Basis(Vector3.UP, yaw_s) * Vector3.RIGHT   # «вправо» для того, кто смотрит на надпись
		for part in [["32", Color(1.0, 0.82, 0.10), -0.19], ["71", Color(0.96, 0.96, 0.94), 0.19]]:
			var digits := _label(part[0], 80, part[1])
			digits.position = spot[0] + right * float(part[2])
			digits.rotation.y = yaw_s
			body.add_child(digits)
	# Тёплый свет в салоне — виден в окна и в открытые двери; без теней.
	var cabin := OmniLight3D.new()
	cabin.name = "CabinLight"
	cabin.position = Vector3(0, base + 2.4, 0)
	cabin.light_color = Color(1.0, 0.82, 0.55)
	cabin.light_energy = 0.8
	cabin.omni_range = 5.0
	cabin.shadow_enabled = false
	cabin.light_specular = 0.1
	body.add_child(cabin)
	# Крыша: короб оборудования, снег; штанги назад и влево вверх — к проводам над осью улицы (−z в осях body — это
	# правый борт, поэтому левые провода — на +z).
	_box(body, "RoofBox", Vector3(3.6, 0.32, 1.6), Vector3(0.8, base + BODY.y + 0.16, 0), light_grey)
	_box(body, "SnowRoof", Vector3(BODY.x - 4.6, 0.1, BODY.z - 0.4), Vector3(-2.6, base + BODY.y + 0.05, 0), Materials.snow(0.0))
	var boom_material := Materials.plain(Color(0.30, 0.30, 0.28), 0.6)
	for left in WIRE_LEFT:
		var from := Vector3(1.6, base + BODY.y + 0.35, left * 0.12)
		var to := Vector3(7.4, CONTACT_Y - 0.05, left)
		var boom := _cylinder(body, "Boom", 0.04, from.distance_to(to), (from + to) * 0.5, boom_material)
		var axis := (to - from).normalized()
		var side_axis := axis.cross(Vector3.UP).normalized()
		boom.basis = Basis(side_axis, axis, side_axis.cross(axis))
		_box(body, "BoomShoe", Vector3(0.3, 0.06, 0.08), to, boom_material, false)
	# Колёса — в осях транспорта: передняя ось в 2,65 м от передка, база 6,2 м.
	for wz in [-BODY.x * 0.5 + 2.65, -BODY.x * 0.5 + 2.65 + 6.2]:
		for wx in [-(hz - 0.12), hz - 0.12]:
			_wheel(root, Vector3(wx, wheel_radius, wz), wheel_radius, 0.3)
	return root
