extends RefCounted
## Облик «Лады» (ART-03, POLISH-02): седан-«пятёрка» из простых объёмов по кадрам 01, 04, 05.
## Только внешний вид: коллизия, физика и зона входа остаются в lada.gd. Перед — −Z, начало — на земле.
## Одна сборка на белую «Ладу» игрока (с водителем, фарами и номером) и припаркованные «Жигули»
## (свой цвет и номер, без огней и водителя).

const Materials = preload("res://game/world/materials.gd")
const PAINT := preload("res://game/vehicles/lada_paint.gdshader")
const LadaDriver = preload("res://game/vehicles/lada_driver.gd")

const PLATE := "н382кх 154"
const WHITE := Color(0.86, 0.85, 0.80)

## Огни (POLISH-02, п. 8): без водителя фары погашены, задние тусклые; с водителем горят; при торможении ярче.
enum Lights { OFF, ON, BRAKE }
const TAIL_ENERGY := [0.25, 1.2, 4.0]
const HEAD_ENERGY := 1.6
const BEAM_RANGE := 22.0
const BEAM_ENERGY := 10.0
const BEAM_COLOR := Color(1.0, 0.91, 0.76)   # тёплый белый лампы накаливания

## Водитель на левом месте; y — линия «ног» холста. Камера in_car (высота ≈2,4 м, 5,1 м сзади) видит
## в заднее стекло на этой глубине полосу 0,94–1,31 м: в неё вписаны шапка (холст y≈42 → 1,30 м)
## и воротник (y 270–330 → 1,01–0,93 м). Чуть сдвинут назад от «настоящего» кресла — иначе крыша срезает шапку.
const DRIVER_AT := Vector3(-0.36, 0.598, 0.3)
const DRIVER_HEIGHT := 0.77

## Линии стёкол (y, z): лобовое и заднее — как наклонные боксы ниже, боковые окна — трапеции между ними.
const WINDSHIELD_BOTTOM := Vector2(0.99, -0.83)
const WINDSHIELD_TOP := Vector2(1.45, -0.49)
const REAR_TOP := Vector2(1.45, 0.89)
const REAR_BOTTOM := Vector2(0.99, 1.16)

## paint — цвет кузова; plate — номер ("" — без номера); player — фары, огни и водитель.
static func build(paint := WHITE, plate := PLATE, player := true, rust := 0.8, snow_depth := 0.08) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var lower := _paint(paint, 1.0, rust, 0.31)
	var upper := _paint(paint, 0.0, rust * 0.55, 0.05)
	var glass := _glass()
	var trim := Materials.plain(Color(0.10, 0.10, 0.11), 0.6)
	var chrome := Materials.plain(Color(0.55, 0.56, 0.58), 0.3)
	var tyre := Materials.plain(Color(0.05, 0.05, 0.05), 0.9)
	var cloth := Materials.plain(Color(0.17, 0.15, 0.14), 0.95)
	var snow := Materials.snow(0.0)
	# Кузов: низ, капот, крышка багажника — классический «трёхобъёмник».
	_box(root, "Body", Vector3(1.64, 0.62, 4.1), Vector3(0, 0.62, 0), lower)
	_box(root, "Hood", Vector3(1.58, 0.06, 1.2), Vector3(0, 0.96, -1.43), upper)
	_box(root, "Trunk", Vector3(1.58, 0.06, 0.9), Vector3(0, 0.96, 1.6), upper)
	# Салон за полупрозрачными стёклами (концепт 05): тёмный пол, торпедо, спинки сидений.
	# У водительского кресла нет подголовника — сзади его закрыла бы голова Илюши, как на концепте.
	_box(root, "CabinFloor", Vector3(1.40, 0.02, 1.9), Vector3(0, 0.94, 0.17), cloth, false)
	_box(root, "Dashboard", Vector3(1.40, 0.16, 0.26), Vector3(0, 1.04, -0.66), cloth, false)
	# Спинка водителя и заднего дивана — ниже линии окон: сзади видны голова и воротник Илюши.
	_box(root, "SeatBack", Vector3(0.5, 0.1, 0.1), Vector3(-0.36, 0.95, 0.45), cloth, false)
	_box(root, "SeatBack", Vector3(0.5, 0.24, 0.1), Vector3(0.36, 1.02, 0.45), cloth, false)
	_box(root, "Headrest", Vector3(0.24, 0.16, 0.08), Vector3(0.36, 1.22, 0.47), cloth, false)
	_box(root, "RearSeat", Vector3(1.36, 0.08, 0.12), Vector3(0, 0.96, 0.88), cloth, false)
	# Кабина: полупрозрачные стёкла, стойки и крыша в цвет кузова.
	var windshield := _box(root, "Windshield", Vector3(1.42, 0.59, 0.03), Vector3(0, 1.23, -0.655), glass, false)
	windshield.rotation.x = deg_to_rad(36.0)
	var rear := _box(root, "RearWindow", Vector3(1.42, 0.55, 0.03), Vector3(0, 1.23, 1.03), glass, false)
	rear.rotation.x = deg_to_rad(-29.0)
	var side_glass := glass.duplicate() as StandardMaterial3D
	side_glass.cull_mode = BaseMaterial3D.CULL_DISABLED   # одна плоскость: видна снаружи и из салона
	for x in [-0.725, 0.725]:
		_side_window(root, x, side_glass)
	_box(root, "Roof", Vector3(1.42, 0.06, 1.36), Vector3(0, 1.47, 0.2), upper)
	for x in [-0.72, 0.72]:
		_box(root, "Pillar", Vector3(0.05, 0.5, 0.07), Vector3(x, 1.21, 0.2), upper, false)
		var a_pillar := _box(root, "Pillar", Vector3(0.05, 0.59, 0.06), Vector3(x, 1.23, -0.655), upper, false)
		a_pillar.rotation.x = deg_to_rad(36.0)
		var c_pillar := _box(root, "Pillar", Vector3(0.05, 0.55, 0.08), Vector3(x, 1.23, 1.03), upper, false)
		c_pillar.rotation.x = deg_to_rad(-29.0)
		_box(root, "Molding", Vector3(0.02, 0.04, 3.9), Vector3(x * 1.14, 0.8, 0), trim, false)
		_box(root, "Mirror", Vector3(0.14, 0.08, 0.06), Vector3(x * 1.22, 1.02, -0.62), trim, false)
	# Перед: решётка, прямоугольные фары, бампер, номер.
	_box(root, "Grille", Vector3(0.9, 0.18, 0.04), Vector3(0, 0.78, -2.06), trim, false)
	var head := _lamp(Color(1.0, 0.95, 0.80), Color(1.0, 0.92, 0.70), 0.2) if player else Materials.plain(Color(0.78, 0.78, 0.74), 0.2)
	var tail := _lamp(Color(0.32, 0.03, 0.02), Color(0.9, 0.05, 0.03), 0.3) if player else Materials.plain(Color(0.42, 0.05, 0.04), 0.3)
	var amber := Materials.plain(Color(0.95, 0.55, 0.10), 0.3)
	for x in [-0.6, 0.6]:
		_box(root, "Headlight", Vector3(0.28, 0.16, 0.04), Vector3(x, 0.78, -2.07), head, false)
		_box(root, "Turn", Vector3(0.18, 0.06, 0.04), Vector3(x, 0.62, -2.07), amber, false)
		_box(root, "Taillight", Vector3(0.38, 0.16, 0.04), Vector3(x, 0.8, 2.07), tail, false)
	for z in [-2.1, 2.1]:
		_box(root, "Bumper", Vector3(1.72, 0.1, 0.12), Vector3(0, 0.48, z), chrome)
	if plate != "":
		_plate(root, -2.17, PI, plate)
		_plate(root, 2.17, 0.0, plate)
	# Колёса с колпаками.
	for x in [-0.78, 0.78]:
		for z in [-1.25, 1.25]:
			var wheel := _cylinder(root, "Wheel", 0.32, 0.2, Vector3(x, 0.32, z), tyre)
			wheel.rotation.z = PI * 0.5
			var cap := _cylinder(root, "Hubcap", 0.15, 0.22, Vector3(x, 0.32, z), chrome)
			cap.rotation.z = PI * 0.5
			cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Снег на крыше, капоте и багажнике (кадры 01, 04); у стоящих машин шапка толще.
	_box(root, "SnowRoof", Vector3(1.34, snow_depth, 1.24), Vector3(0, 1.5 + snow_depth * 0.5, 0.22), snow)
	_box(root, "SnowHood", Vector3(1.3, snow_depth * 0.6, 0.7), Vector3(0, 0.99 + snow_depth * 0.3, -1.28), snow)
	_box(root, "SnowTrunk", Vector3(1.3, snow_depth * 0.6, 0.6), Vector3(0, 0.99 + snow_depth * 0.3, 1.62), snow)
	if player:
		_beams(root)
		var driver: Node3D = LadaDriver.new()
		driver.name = "Driver"
		driver.character = "ilyusha"
		driver.height_m = DRIVER_HEIGHT
		driver.position = DRIVER_AT
		driver.visible = false
		root.add_child(driver)
		set_lights(root, Lights.OFF)
	return root

## Огни белой «Лады»: фары с лучами и задние фонари по режиму Lights.
static func set_lights(visual: Node3D, mode: int) -> void:
	var on := mode != Lights.OFF
	for name in ["BeamLeft", "BeamRight"]:
		var beam := visual.get_node_or_null(name) as Light3D
		if beam:
			beam.visible = on
	var head := visual.get_node_or_null("Headlight") as MeshInstance3D
	if head:
		(head.material_override as StandardMaterial3D).emission_energy_multiplier = HEAD_ENERGY if on else 0.0
	var tail := visual.get_node_or_null("Taillight") as MeshInstance3D
	if tail:
		(tail.material_override as StandardMaterial3D).emission_energy_multiplier = TAIL_ENERGY[mode]

static func set_driver_visible(visual: Node3D, shown: bool) -> void:
	var driver := visual.get_node_or_null("Driver") as Node3D
	if driver:
		driver.visible = shown

static func _beams(root: Node3D) -> void:
	for side in [["BeamLeft", -0.6], ["BeamRight", 0.6]]:
		var beam := SpotLight3D.new()
		beam.name = side[0]
		beam.position = Vector3(side[1], 0.8, -2.12)
		beam.rotation.x = deg_to_rad(-5.0)   # чуть вниз: пятно ложится на дорогу в 6–20 м впереди
		beam.light_color = BEAM_COLOR
		beam.light_energy = BEAM_ENERGY
		beam.spot_range = BEAM_RANGE
		beam.spot_angle = 28.0
		beam.spot_angle_attenuation = 0.8
		beam.spot_attenuation = 0.6
		beam.shadow_enabled = false
		beam.light_specular = 0.6
		beam.visible = false
		root.add_child(beam)

static func _paint(color: Color, dirt: float, rust: float, half_height: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PAINT
	material.set_shader_parameter("paint", color)
	material.set_shader_parameter("dirt_amount", dirt)
	material.set_shader_parameter("rust_amount", rust)
	material.set_shader_parameter("half_height", half_height)
	return material

## Тёмно-синее стекло с альфой ≈0,5: салон и водитель видны сзади и сбоку (концепт 05).
## Водитель — рисунок с отсечением по альфе (непрозрачный проход), стекло рисуется после него: без мерцания.
static func _glass() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.13, 0.22, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.06
	material.metallic = 0.2
	material.metallic_specular = 0.7
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material

## Свой материал на каждую машину: яркость огней меняется на ходу (общий из Materials.plain менять нельзя).
static func _lamp(color: Color, glow: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = 0.0
	return material

## Боковое окно — трапеция между наклонами лобового и заднего стёкол, без треугольных щелей у стоек.
static func _side_window(parent: Node3D, x: float, material: Material) -> void:
	var outline := [WINDSHIELD_BOTTOM, WINDSHIELD_TOP, REAR_TOP, REAR_BOTTOM]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal := Vector3(signf(x), 0, 0)
	tool.set_normal(normal)
	var points: Array[Vector3] = []
	for p: Vector2 in outline:
		points.append(Vector3(x, p.x, p.y))
	for i in [0, 1, 2, 0, 2, 3]:
		tool.add_vertex(points[i])
	var instance := MeshInstance3D.new()
	instance.name = "SideGlass"
	instance.mesh = tool.commit()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

static func _box(parent: Node3D, name: String, size: Vector3, at: Vector3, material: Material, shadow := true) -> MeshInstance3D:
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

static func _cylinder(parent: Node3D, name: String, radius: float, width: float, at: Vector3, material: Material) -> MeshInstance3D:
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

static func _plate(parent: Node3D, z: float, yaw: float, text: String) -> void:
	var holder := Node3D.new()
	holder.name = "Plate"
	holder.position = Vector3(0, 0.6, z)
	holder.rotation.y = yaw
	parent.add_child(holder)
	_box(holder, "PlateBase", Vector3(0.52, 0.12, 0.02), Vector3.ZERO, Materials.plain(Color(0.92, 0.92, 0.90), 0.5), false)
	var label := Label3D.new()
	label.name = "PlateText"
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.0016
	label.modulate = Color(0.05, 0.05, 0.05)
	label.outline_size = 0
	label.position = Vector3(0, 0, 0.012)
	label.double_sided = false
	holder.add_child(label)
