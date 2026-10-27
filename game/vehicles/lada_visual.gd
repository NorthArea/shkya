extends RefCounted
## Облик белой «Лады» игрока (ART-03): седан-«пятёрка» из простых объёмов по кадрам 01, 04, 05.
## Только внешний вид: коллизия, физика и зона входа остаются в lada.gd. Перед — −Z, начало — на земле.

const Materials = preload("res://game/world/materials.gd")
const PAINT := preload("res://game/vehicles/lada_paint.gdshader")

const PLATE := "н382кх 154"

static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var lower := _paint(1.0, 0.55, 0.31)
	var upper := _paint(0.0, 0.3, 0.05)
	var glass := _dark_glass()
	var trim := Materials.plain(Color(0.10, 0.10, 0.11), 0.6)
	var chrome := Materials.plain(Color(0.55, 0.56, 0.58), 0.3)
	var tyre := Materials.plain(Color(0.05, 0.05, 0.05), 0.9)
	var snow := Materials.snow(0.0)
	# Кузов: низ, капот, крышка багажника — классический «трёхобъёмник».
	_box(root, "Body", Vector3(1.64, 0.62, 4.1), Vector3(0, 0.62, 0), lower)
	_box(root, "Hood", Vector3(1.58, 0.06, 1.2), Vector3(0, 0.96, -1.43), upper)
	_box(root, "Trunk", Vector3(1.58, 0.06, 0.9), Vector3(0, 0.96, 1.6), upper)
	# Кабина: тёмные стёкла, белые стойки и крыша.
	_box(root, "SideGlass", Vector3(1.46, 0.48, 1.5), Vector3(0, 1.21, 0.2), glass)
	var windshield := _box(root, "Windshield", Vector3(1.42, 0.62, 0.04), Vector3(0, 1.2, -0.72), glass)
	windshield.rotation.x = deg_to_rad(-38.0)
	var rear := _box(root, "RearWindow", Vector3(1.42, 0.58, 0.04), Vector3(0, 1.2, 1.12), glass)
	rear.rotation.x = deg_to_rad(34.0)
	_box(root, "Roof", Vector3(1.42, 0.06, 1.36), Vector3(0, 1.47, 0.2), upper)
	for x in [-0.72, 0.72]:
		for z in [-0.52, 0.2, 0.9]:
			_box(root, "Pillar", Vector3(0.05, 0.5, 0.07), Vector3(x, 1.21, z), upper)
		_box(root, "Molding", Vector3(0.02, 0.04, 3.9), Vector3(x * 1.14, 0.8, 0), trim)
		_box(root, "Mirror", Vector3(0.14, 0.08, 0.06), Vector3(x * 1.22, 1.02, -0.62), trim)
	# Перед: решётка, прямоугольные фары, бампер, номер.
	_box(root, "Grille", Vector3(0.9, 0.18, 0.04), Vector3(0, 0.78, -2.06), trim)
	var head := Materials.plain(Color(1.0, 0.95, 0.80), 0.2, Color(1.0, 0.92, 0.70), 1.6)
	var tail := Materials.plain(Color(0.75, 0.06, 0.05), 0.3, Color(0.9, 0.05, 0.03), 1.2)
	var amber := Materials.plain(Color(0.95, 0.55, 0.10), 0.3)
	for x in [-0.6, 0.6]:
		_box(root, "Headlight", Vector3(0.28, 0.16, 0.04), Vector3(x, 0.78, -2.07), head)
		_box(root, "Turn", Vector3(0.18, 0.06, 0.04), Vector3(x, 0.62, -2.07), amber)
		_box(root, "Taillight", Vector3(0.38, 0.16, 0.04), Vector3(x, 0.8, 2.07), tail)
	for z in [-2.1, 2.1]:
		_box(root, "Bumper", Vector3(1.72, 0.1, 0.12), Vector3(0, 0.48, z), chrome)
	_plate(root, -2.17, PI)
	_plate(root, 2.17, 0.0)
	# Колёса с колпаками.
	for x in [-0.78, 0.78]:
		for z in [-1.25, 1.25]:
			var wheel := _cylinder(root, "Wheel", 0.32, 0.2, Vector3(x, 0.32, z), tyre)
			wheel.rotation.z = PI * 0.5
			var cap := _cylinder(root, "Hubcap", 0.15, 0.22, Vector3(x, 0.32, z), chrome)
			cap.rotation.z = PI * 0.5
	# Снег на крыше, капоте и багажнике (кадры 01, 04).
	_box(root, "SnowRoof", Vector3(1.34, 0.08, 1.24), Vector3(0, 1.54, 0.22), snow)
	_box(root, "SnowHood", Vector3(1.3, 0.05, 0.7), Vector3(0, 1.01, -1.28), snow)
	_box(root, "SnowTrunk", Vector3(1.3, 0.05, 0.6), Vector3(0, 1.01, 1.62), snow)
	return root

static func _paint(dirt: float, rust: float, half_height: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PAINT
	material.set_shader_parameter("dirt_amount", dirt)
	material.set_shader_parameter("rust_amount", rust)
	material.set_shader_parameter("half_height", half_height)
	return material

static func _dark_glass() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.07, 0.09, 0.11)
	material.roughness = 0.08
	material.metallic = 0.3
	return material

static func _box(parent: Node3D, name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
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

static func _plate(parent: Node3D, z: float, yaw: float) -> void:
	var holder := Node3D.new()
	holder.name = "Plate"
	holder.position = Vector3(0, 0.6, z)
	holder.rotation.y = yaw
	parent.add_child(holder)
	_box(holder, "PlateBase", Vector3(0.52, 0.12, 0.02), Vector3.ZERO, Materials.plain(Color(0.92, 0.92, 0.90), 0.5))
	var label := Label3D.new()
	label.name = "PlateText"
	label.text = PLATE
	label.font_size = 48
	label.pixel_size = 0.0016
	label.modulate = Color(0.05, 0.05, 0.05)
	label.outline_size = 0
	label.position = Vector3(0, 0, 0.012)
	label.double_sided = false
	holder.add_child(label)
