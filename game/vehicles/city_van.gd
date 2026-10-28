class_name CityVan
extends AnimatableBody3D
## Микроавтобус ГСУМ «БЕСПЛАТНЫЙ ПРОЕЗД» (EXT-01 N, концепт e02): белый с ржавчиной, снег на крыше,
## остекление, тёплый свет в салоне, открытая правая боковая дверь, надписи «БЕСПЛАТНЫЙ ПРОЕЗД» на боках и
## «МАРШРУТ УТОЧНЯЕТСЯ» сзади, номер региона 154 без реальных эмблем. Перед — −Z, правая сторона (дверь) — +X,
## начало — на земле. Тело — AnimatableBody3D на слое World (C2): укрытие для луча DetectionSensor, коллизия едет
## вместе с кузовом. Дочерний DetectionSensor у двери (C7) в двух режимах: на стоянке (park) — «учебный»
## (этап 3: PARK_SENSOR_RANGE м во все стороны, потолок шкалы TUTORIAL_CAP — индикатор без провала); в пути выключен;
## в конце пути — дверной (STEALTH_DESIGN: 14 м, 80°) из двери наружу. Сектор на земле — при приближении Илюши.
## Interactable «ГОРОДСКОЙ ТРАНСПОРТ (?)» — только подпись при приближении, без действия (MISSION_EXTENSION).
## drive(path, stop_yaw) — постановочный проезд по точкам (сглаженные повороты, SPEED м/с) и остановка в конце
## носом по stop_yaw; без физики трафика (README расширения). Впереди по пути — датчик, как у PathVehicle
## (game/vehicles/path_vehicle.gd): «Лада», Илюша, транспорт кольца в SCAN_AHEAD м — торможение и ожидание, объезда нет;
## перед шагом кузов на новом месте проверяется на касание — сквозь машины автобус не едет (приёмка 28.10, P2).

const Materials = preload("res://game/world/materials.gd")
const PAINT := preload("res://game/vehicles/lada_paint.gdshader")
const DetectionSensorScript = preload("res://game/stealth/detection_sensor.gd")
const InteractableScript = preload("res://game/interaction/interactable.gd")

const SIZE := Vector3(2.1, 2.45, 5.5)
const PLATE := "о282оо 154"
const PROMPT := "ГОРОДСКОЙ ТРАНСПОРТ (?)"
const BODY_PAINT := Color(0.93, 0.92, 0.88)
const SPEED := 6.0
const ACCEL := 2.5            # м/с²: разгон и торможение у конца пути
const TURN_SMOOTH := 5.0      # радиус скругления углов пути, м
const WHEEL_RADIUS := 0.36
const DOOR_AT := Vector3(1.05, 0.0, 0.3)   # низ открытого дверного проёма, правый борт
const SENSOR_RANGE := 14.0
const SENSOR_FOV := 80.0
const PARK_SENSOR_RANGE := 8.0    # этап 3: пешком у двери и по проезжей части рядом — индикатор
const PARK_SENSOR_FOV := 360.0
const TUTORIAL_CAP := 0.6         # на стоянке улицы A шкала дорастает до 0,6 и стоит — провала нет
const SCAN_AHEAD := 7.0           # м от переднего бампера
const SCAN_STEP := 1.0
const STOP_MARGIN := 2.5          # м: встаёт, когда препятствие в 2,5–3,5 м от бампера
const EMERGENCY_DECEL := 9.0
const OBSTACLE_MASK := 1 | 2 | 4  # World (транспорт кольца), Player, Car

var sensor: Node3D
var interactable: Interactable
var visual: Node3D
var _curve: Curve3D
var _offset := 0.0
var _speed := 0.0
var _stop_yaw := 0.0
var _driving := false
var _wheels: Array[MeshInstance3D] = []
var _scan_query := PhysicsShapeQueryParameters3D.new()
var _body_query := PhysicsShapeQueryParameters3D.new()
## Что держит автобус в последнем кадре (null — ничего) — для тестов.
var blocked_by: Object = null

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = false
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	collider.position.y = SIZE.y * 0.5
	add_child(collider)
	visual = _build_visual()
	add_child(visual)
	sensor = DetectionSensorScript.new()
	sensor.name = "DetectionSensor"
	sensor.range_m = SENSOR_RANGE
	sensor.fov_deg = SENSOR_FOV
	sensor.position = DOOR_AT
	sensor.rotation.y = -PI * 0.5   # −Z сенсора → +X: из двери наружу
	sensor.show_cone = true
	add_child(sensor)
	var scan_box := BoxShape3D.new()
	scan_box.size = Vector3(SIZE.x + 0.3, 1.8, SCAN_STEP)
	_scan_query.shape = scan_box
	_scan_query.collision_mask = OBSTACLE_MASK
	_scan_query.exclude = [get_rid()]
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(SIZE.x + 0.1, 1.8, SIZE.z + 0.1)
	_body_query.shape = body_box
	_body_query.collision_mask = OBSTACLE_MASK
	_body_query.exclude = [get_rid()]
	interactable = InteractableScript.new()
	interactable.name = "Interactable"
	interactable.interaction_id = &"city_van"
	interactable.prompt = PROMPT
	interactable.radius = 4.2
	interactable.position = Vector3(0, 0, 0)
	add_child(interactable)

## Поставить на точку носом по yaw (yaw 0 — на север, как в Layout).
func park(point: Vector3, yaw: float) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x, 0.0, point.z))
	_driving = false
	_curve = null
	_sensor_mode(PARK_SENSOR_RANGE, PARK_SENSOR_FOV, TUTORIAL_CAP)

## Проехать по точкам (первая — где стоит сейчас) и встать в конце носом по stop_yaw.
func drive(path: Array, stop_yaw: float) -> void:
	if path.size() < 2:
		return
	_curve = Curve3D.new()
	_curve.bake_interval = 0.25
	for i in path.size():
		var p: Vector3 = path[i]
		p.y = 0.0
		var tangent_in := Vector3.ZERO
		var tangent_out := Vector3.ZERO
		if i > 0 and i < path.size() - 1:
			var prev: Vector3 = path[i - 1]
			var next: Vector3 = path[i + 1]
			var d0 := (p - prev)
			var d1 := (next - p)
			d0.y = 0.0
			d1.y = 0.0
			var reach := minf(TURN_SMOOTH, minf(d0.length(), d1.length()) * 0.4)
			var dir := (d0.normalized() + d1.normalized()).normalized()
			tangent_in = -dir * reach
			tangent_out = dir * reach
		_curve.add_point(p, tangent_in, tangent_out)
	_offset = 0.0
	_speed = 0.0
	_stop_yaw = stop_yaw
	_driving = true
	sensor.enabled = false   # в пути не смотрит; дверной режим — на месте

## Режим сенсора двери: дальность, угол, потолок шкалы; включает сенсор.
func _sensor_mode(range_m: float, fov: float, cap: float) -> void:
	sensor.range_m = range_m
	sensor.fov_deg = fov
	sensor.suspicion_cap = cap
	sensor.enabled = true

func is_driving() -> bool:
	return _driving

func _physics_process(delta: float) -> void:
	if not _driving or _curve == null:
		return
	var length := _curve.get_baked_length()
	var left := length - _offset
	# Тормозной путь v²/2a: перед концом сбрасываем, иначе набираем до SPEED.
	var allowed := sqrt(maxf(2.0 * ACCEL * left, 0.0))
	var target := minf(SPEED, allowed)
	var obstacle := _obstacle_limit(length)
	if obstacle < target:
		_speed = maxf(_speed - EMERGENCY_DECEL * delta, obstacle)
	elif _speed < target:
		_speed = minf(_speed + ACCEL * delta, target)
	else:
		_speed = maxf(_speed - ACCEL * 1.5 * delta, target)
	var next := minf(_offset + _speed * delta, length)
	if next > _offset and not _free_at(next, length):
		_speed = 0.0   # кузов на новом месте задел бы машину или Илюшу — стоим
		return
	_offset = next
	var at := _curve.sample_baked(_offset, true)
	var ahead := _curve.sample_baked(minf(_offset + 0.6, length), true)
	var behind := _curve.sample_baked(maxf(_offset - 0.6, 0.0), true)
	var dir := ahead - behind
	dir.y = 0.0
	var yaw := global_rotation.y
	if dir.length() > 0.01:
		yaw = atan2(-dir.x, -dir.z)
	if left < 1.5:
		# Последние полтора метра — довернуть к stop_yaw.
		yaw = lerp_angle(global_rotation.y, _stop_yaw, 1.0 - exp(-4.0 * delta))
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.z))
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.UP, -_speed * delta / WHEEL_RADIUS)   # ось цилиндра повёрнута на ±90° по Z
	if _offset >= length - 0.01:
		global_transform = Transform3D(Basis(Vector3.UP, _stop_yaw), Vector3(at.x, 0.0, at.z))
		_driving = false
		_speed = 0.0
		_sensor_mode(SENSOR_RANGE, SENSOR_FOV, 1.0)

## Предел скорости по датчику впереди: коробки шириной кузова + 0,3 м вдоль пути от бампера на SCAN_AHEAD.
func _obstacle_limit(length: float) -> float:
	var space := get_world_3d().direct_space_state
	blocked_by = null
	for k in int(round(SCAN_AHEAD / SCAN_STEP)):
		var at := _offset + SIZE.z * 0.5 + SCAN_STEP * (k + 0.5)
		if at > length + SIZE.z * 0.5:
			break
		_scan_query.transform = _transform_at(at, length, 1.1)
		for result in space.intersect_shape(_scan_query, 8):
			if _is_obstacle(result["collider"]):
				blocked_by = result["collider"]
				return sqrt(2.0 * EMERGENCY_DECEL * maxf(SCAN_STEP * k - STOP_MARGIN, 0.0))
	return INF

## Кузов на смещении at никого подвижного не задевает.
func _free_at(at: float, length: float) -> bool:
	_body_query.transform = _transform_at(at, length, 0.95)
	for result in get_world_3d().direct_space_state.intersect_shape(_body_query, 8):
		if _is_obstacle(result["collider"]):
			blocked_by = result["collider"]
			return false
	return true

## Положение на кривой со смещением at (за концом — продолжение по последнему направлению), на высоте y.
func _transform_at(at: float, length: float, y: float) -> Transform3D:
	var clamped := clampf(at, 0.0, length)
	var p := _curve.sample_baked(clamped, true)
	var ahead := _curve.sample_baked(minf(clamped + 0.6, length), true)
	var behind := _curve.sample_baked(maxf(clamped - 0.6, 0.0), true)
	var dir := ahead - behind
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = -global_basis.z
	dir = dir.normalized()
	p += dir * (at - clamped)
	return Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), Vector3(p.x, y, p.z))

## Препятствие — любой корпус, кроме неподвижной застройки и NPC (StaticBody3D, не AnimatableBody3D).
static func _is_obstacle(body: Object) -> bool:
	if body == null:
		return false
	if body is StaticBody3D and not (body is AnimatableBody3D):
		return false
	return true

# --- облик (по e02: кабина со скошенным капотом, окна по всему борту, открытая сдвижная дверь) ---

func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var lower := _paint(BODY_PAINT, 0.55, 0.6, 0.55)   # белый с ржавчиной по низу (e02), не бурый
	var upper := _paint(BODY_PAINT, 0.15, 0.3, 0.1)
	var glass := _glass()
	var trim := Materials.plain(Color(0.10, 0.10, 0.11), 0.6)
	var dark_grey := Materials.plain(Color(0.22, 0.22, 0.23), 0.7)
	var tyre := Materials.plain(Color(0.05, 0.05, 0.05), 0.9)
	var cloth := Materials.plain(Color(0.36, 0.30, 0.22), 0.95)
	var cabin := Materials.plain(Color(0.62, 0.52, 0.36), 0.9, Color(1.0, 0.72, 0.40), 0.5)   # тёплый салон
	var snow := Materials.snow(0.0)
	var hx := SIZE.x * 0.5
	# Кузов: нижний пояс, крыша; между ними — остекление и стойки.
	_box(root, "Body", Vector3(SIZE.x, 1.0, 5.3), Vector3(0, 0.95, 0.05), lower)
	_box(root, "Hood", Vector3(SIZE.x - 0.1, 0.46, 0.9), Vector3(0, 1.62, -2.25), upper)
	var windshield := _box(root, "Windshield", Vector3(SIZE.x - 0.3, 0.72, 0.03), Vector3(0, 1.98, -1.73), glass, false)
	windshield.rotation.x = deg_to_rad(18.0)
	_box(root, "Roof", Vector3(SIZE.x - 0.1, 0.14, 4.4), Vector3(0, 2.38, 0.5), upper)
	_box(root, "RoofFront", Vector3(SIZE.x - 0.4, 0.1, 0.6), Vector3(0, 2.36, -1.72), upper)
	_box(root, "RoofFrontSnow", Vector3(SIZE.x - 0.5, 0.08, 0.5), Vector3(0, 2.45, -1.72), snow)
	_box(root, "SnowRoof", Vector3(SIZE.x - 0.3, 0.12, 4.2), Vector3(0, 2.5, 0.5), snow)
	_box(root, "SnowHood", Vector3(SIZE.x - 0.5, 0.06, 0.6), Vector3(0, 1.87, -2.3), snow)
	# Салон за стёклами: пол, сиденья в два ряда, перегородка кабины — видны в проём двери.
	_box(root, "CabinFloor", Vector3(SIZE.x - 0.2, 0.04, 3.9), Vector3(0, 1.45, 0.6), cloth, false)
	_box(root, "CabinCeiling", Vector3(SIZE.x - 0.2, 0.02, 4.2), Vector3(0, 2.3, 0.5), cabin, false)
	for z in [-0.7, 0.4, 1.5]:
		for x in [-0.62, 0.55]:
			_box(root, "Seat", Vector3(0.5, 0.42, 0.44), Vector3(x, 1.66, z), cloth, false)
			_box(root, "SeatBack", Vector3(0.5, 0.5, 0.08), Vector3(x, 2.0, z + 0.24), cloth, false)
	_box(root, "Dashboard", Vector3(SIZE.x - 0.3, 0.2, 0.3), Vector3(0, 1.55, -1.55), trim, false)
	_box(root, "Wheel", Vector3(0.36, 0.04, 0.36), Vector3(-0.6, 1.8, -1.35), trim, false)
	# Остекление: левый борт — сплошная лента; правый — лента позади двери и кабинное окно впереди.
	var side_glass := glass.duplicate() as StandardMaterial3D
	side_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(root, "GlassLeft", Vector3(0.03, 0.8, 4.1), Vector3(-hx + 0.02, 1.9, 0.4), side_glass, false)
	_box(root, "GlassRightRear", Vector3(0.03, 0.8, 1.55), Vector3(hx - 0.02, 1.9, 1.68), side_glass, false)
	_box(root, "GlassRightCab", Vector3(0.03, 0.8, 0.95), Vector3(hx - 0.02, 1.9, -1.18), side_glass, false)
	_box(root, "GlassRear", Vector3(SIZE.x - 0.5, 0.7, 0.03), Vector3(0, 1.92, 2.69), glass, false)
	for z in [-1.68, -0.68, 0.9, 2.45]:
		for x in [-hx + 0.03, hx - 0.03]:
			_box(root, "Pillar", Vector3(0.06, 0.82, 0.08), Vector3(x, 1.9, z), upper, false)
	_box(root, "PillarRearL", Vector3(0.08, 0.82, 0.08), Vector3(-hx + 0.22, 1.9, 2.66), upper, false)
	_box(root, "PillarRearR", Vector3(0.08, 0.82, 0.08), Vector3(hx - 0.22, 1.9, 2.66), upper, false)
	_box(root, "Sill", Vector3(SIZE.x + 0.04, 0.06, 4.4), Vector3(0, 1.47, 0.5), upper, false)
	# Открытая сдвижная дверь: панель отъехала назад и стоит снаружи борта; проём — тёмный с тёплым светом.
	_box(root, "DoorOpening", Vector3(0.02, 0.95, 1.2), Vector3(hx - 0.01, 1.95, 0.3), cabin, false)
	_box(root, "DoorStep", Vector3(0.16, 0.05, 1.0), Vector3(hx + 0.06, 0.62, 0.3), trim, false)
	_box(root, "DoorPanel", Vector3(0.06, 1.75, 1.2), Vector3(hx + 0.08, 1.37, 1.55), lower)
	_box(root, "DoorGlass", Vector3(0.03, 0.6, 0.9), Vector3(hx + 0.12, 1.85, 1.55), side_glass, false)
	_box(root, "DoorRail", Vector3(0.04, 0.05, 2.0), Vector3(hx + 0.04, 2.3, 1.2), trim, false)
	# Перед: решётка, фары, бампер; зад: фонари, бампер, выхлоп.
	_box(root, "Grille", Vector3(0.9, 0.22, 0.04), Vector3(0, 1.12, -2.76), trim, false)
	var head := _lamp(Color(1.0, 0.95, 0.80), Color(1.0, 0.90, 0.66), 1.4)
	var tail := _lamp(Color(0.5, 0.05, 0.03), Color(0.9, 0.08, 0.04), 0.6)
	var amber := _lamp(Color(0.95, 0.55, 0.10), Color(1.0, 0.6, 0.1), 0.3)
	for x in [-0.68, 0.68]:
		_box(root, "Headlight", Vector3(0.3, 0.22, 0.04), Vector3(x, 1.12, -2.77), head, false)
		_box(root, "Taillight", Vector3(0.16, 0.34, 0.04), Vector3(x * 1.35, 1.1, 2.77), tail, false)
		_box(root, "Turn", Vector3(0.16, 0.12, 0.04), Vector3(x * 1.35, 1.36, 2.77), amber, false)
		_box(root, "Mirror", Vector3(0.1, 0.26, 0.14), Vector3(x * 1.65, 1.75, -1.5), trim, false)
		_box(root, "MirrorArm", Vector3(0.4, 0.03, 0.03), Vector3(x * 1.45, 1.78, -1.5), trim, false)
	for z in [-2.78, 2.78]:
		_box(root, "Bumper", Vector3(SIZE.x + 0.1, 0.16, 0.14), Vector3(0, 0.6, z), dark_grey)
	_box(root, "RearDoorSeam", Vector3(0.02, 1.9, 0.02), Vector3(0, 1.4, 2.71), trim, false)
	var exhaust := _cylinder(root, "Exhaust", 0.04, 0.2, Vector3(0.6, 0.38, 2.75), dark_grey)
	exhaust.rotation.x = PI * 0.5
	_plate(root, -2.8, PI, PLATE)
	_plate(root, 2.8, 0.0, PLATE)
	# Колёса.
	for x in [-0.9, 0.9]:
		for z in [-1.75, 1.6]:
			var wheel := _cylinder(root, "Wheel", WHEEL_RADIUS, 0.24, Vector3(x, WHEEL_RADIUS, z), tyre)
			wheel.rotation.z = PI * 0.5
			var cap := _cylinder(wheel, "Hubcap", 0.16, 0.26, Vector3.ZERO, Materials.plain(Color(0.45, 0.44, 0.42), 0.5))
			cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_wheels.append(wheel)
	# Надписи (DIALOGUES_AND_JOKES «Надписи»): красным на боках, сзади на двери.
	for x in [-1.0, 1.0]:
		var side := _label("БЕСПЛАТНЫЙ\nПРОЕЗД", 64, Color(0.62, 0.06, 0.05))
		side.position = Vector3(x * (hx + 0.012), 1.0, 1.0 if x < 0.0 else -0.5)   # справа — перед дверью
		side.rotation.y = PI * 0.5 if x > 0.0 else -PI * 0.5
		root.add_child(side)
	var rear := _label("МАРШРУТ\nУТОЧНЯЕТСЯ", 56, Color(0.62, 0.06, 0.05))
	rear.position = Vector3(0, 1.0, 2.79)
	root.add_child(rear)
	# Тёплый свет в салоне (слабый, без теней) — виден в проём двери и в окна.
	var lamp := OmniLight3D.new()
	lamp.name = "CabinLight"
	lamp.position = Vector3(0.2, 2.1, 0.4)
	lamp.light_color = Color(1.0, 0.78, 0.46)
	lamp.light_energy = 1.1
	lamp.omni_range = 4.5
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	lamp.light_specular = 0.2
	root.add_child(lamp)
	return root

func _paint(color: Color, dirt: float, rust: float, half_height: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PAINT
	material.set_shader_parameter("paint", color)
	material.set_shader_parameter("rust", Color(0.46, 0.26, 0.12))
	material.set_shader_parameter("dirt_amount", dirt)
	material.set_shader_parameter("rust_amount", rust)
	material.set_shader_parameter("half_height", half_height)
	return material

func _glass() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.16, 0.20, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.08
	material.metallic = 0.2
	material.metallic_specular = 0.7
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material

func _lamp(color: Color, glow: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = energy
	return material

func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.0046
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _box(parent: Node3D, name: String, size: Vector3, at: Vector3, material: Material, shadow := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	if not shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _cylinder(parent: Node3D, name: String, radius: float, width: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 16
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance

func _plate(parent: Node3D, z: float, yaw: float, text: String) -> void:
	var holder := Node3D.new()
	holder.name = "Plate"
	holder.position = Vector3(0, 0.78, z)
	holder.rotation.y = yaw
	parent.add_child(holder)
	_box(holder, "PlateBase", Vector3(0.52, 0.12, 0.02), Vector3.ZERO, Materials.plain(Color(0.92, 0.92, 0.90), 0.5), false)
	var label := _label(text, 48, Color(0.05, 0.05, 0.05))
	label.pixel_size = 0.0016
	label.position = Vector3(0, 0, 0.012)
	holder.add_child(label)
