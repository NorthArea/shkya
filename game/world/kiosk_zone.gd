extends Area3D
## KioskZone: площадка у киоска. Видит Илюшу (слой Player) и машину (слой Car).
## Что считать прибытием, решает мир по состоянию миссии.

const Layout = preload("res://game/world/layout.gd")

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 | 4
	monitoring = true
	monitorable = false
	var box := Layout.KIOSK_ZONE
	position = box.get_center()
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)

func is_occupied() -> bool:
	return has_overlapping_bodies()
