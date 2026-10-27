extends StaticBody3D
## Заглушка белой «Лады» для greybox: неподвижная, на слое Car. Заменяется в DRIVE-01.

const Greybox = preload("res://game/world/greybox.gd")

const SIZE := Vector3(1.7, 1.4, 4.1)

func _ready() -> void:
	collision_layer = 4  # Car
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = SIZE.y * 0.5
	add_child(collider)
	var body := Greybox.mesh_box(Vector3(SIZE.x, 0.8, SIZE.z), Color(0.92, 0.92, 0.88))
	body.position.y = 0.55
	add_child(body)
	var cabin := Greybox.mesh_box(Vector3(SIZE.x * 0.9, 0.55, SIZE.z * 0.5), Color(0.75, 0.78, 0.80))
	cabin.position = Vector3(0.0, 1.2, 0.2)
	add_child(cabin)
