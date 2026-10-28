extends Area3D
## KioskZone: площадка у киоска. Видит Илюшу (слой Player) и машину (слой Car).
## Что считать прибытием, решает мир по состоянию миссии.
## Две коробки (EXT-01): парковка Layout.KIOSK_ZONE — для машины и Илюши; у окна Layout.KIOSK_WINDOW_ZONE — только
## для Илюши пешком (машина, подъехавшая к окну, прибытием не считается: парковка — южнее павильона, этап 4).

const Layout = preload("res://game/world/layout.gd")
const PLAYER_LAYER := 2

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 | 4
	monitoring = true
	monitorable = false
	for box: AABB in [Layout.KIOSK_ZONE, Layout.KIOSK_WINDOW_ZONE]:
		var shape := BoxShape3D.new()
		shape.size = box.size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = box.get_center()
		add_child(collider)

func is_occupied() -> bool:
	for body in get_overlapping_bodies():
		if body is CollisionObject3D and (body as CollisionObject3D).collision_layer & PLAYER_LAYER:
			return true
		# Машина — только на парковке: её начало внутри KIOSK_ZONE (по плоскости XZ).
		var p: Vector3 = body.global_position
		var zone := Layout.KIOSK_ZONE
		if p.x >= zone.position.x and p.x <= zone.end.x and p.z >= zone.position.z and p.z <= zone.end.z:
			return true
	return false
