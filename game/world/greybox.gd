extends RefCounted
## Серые примитивы для greybox. Визуальная часть заменяется в ART-01/ART-02.

const COLORS := {
	"panel": Color(0.55, 0.56, 0.58),
	"panel_low": Color(0.62, 0.58, 0.52),
	"garage": Color(0.42, 0.40, 0.38),
	"fence": Color(0.25, 0.32, 0.28),
	"prop": Color(0.45, 0.35, 0.28),
	"snow": Color(0.86, 0.88, 0.92),
	"parked_car": Color(0.55, 0.30, 0.25),
	"kiosk": Color(0.28, 0.45, 0.36),
	"lamp": Color(0.2, 0.2, 0.22),
	"canopy": Color(0.40, 0.40, 0.42),
	"ground": Color(0.80, 0.82, 0.86),
	"road": Color(0.22, 0.22, 0.24),
	"sidewalk": Color(0.55, 0.56, 0.60),
	"yard_road": Color(0.40, 0.40, 0.42),
}

static var _materials := {}

static func material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_materials[color] = m
	return _materials[color]

static func mesh_box(size: Vector3, color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = material(color)
	var node := MeshInstance3D.new()
	node.mesh = box
	return node

static func mesh_sphere(radius: float, color: Color) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.material = material(color)
	var node := MeshInstance3D.new()
	node.mesh = sphere
	return node

static func mesh_capsule(radius: float, height: float, color: Color) -> MeshInstance3D:
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = height
	capsule.material = material(color)
	var node := MeshInstance3D.new()
	node.mesh = capsule
	return node

static func mesh_cylinder(top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.material = material(color)
	var node := MeshInstance3D.new()
	node.mesh = cylinder
	return node

## Неподвижная коробка с коллизией; center — центр коробки.
static func solid_box(name: String, center: Vector3, size: Vector3, color: Color, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = center
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.add_child(mesh_box(size, color))
	return body
