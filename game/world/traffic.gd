extends Node3D
## Транспорт на кольце арены (ARENA-01, часть T, контракт C8): три машины («Жигули», «Волга», «Газель») и
## троллейбус ЗиУ-9 маршрута 13. Путь — правая полоса кольца Layout.RING (PathVehicle.LanePath), старт —
## равномерно по кольцу с шагом length / 4 от START_OFFSET; ни один не стартует ближе MIN_START_CLEARANCE к
## CAR_SPAWN, KIOSK_ZONE и VAN_PARK (проверяет traffic_test.gd). Без случайностей.
## Узел создаёт LevelGeometry (ребёнок DemoWorld/LevelGeometry/Traffic, как Patrols); мир ищется вверх по дереву.
## Корпуса транспорта исключены из луча камеры, как тела NPC в Patrols: проезжающая машина не дёргает камеру.

const Layout = preload("res://game/world/layout.gd")
const PathVehicleScript = preload("res://game/vehicles/path_vehicle.gd")
const TrafficCarScript = preload("res://game/vehicles/traffic_car.gd")
const TrolleybusScript = preload("res://game/vehicles/trolleybus.gd")

## Смещение троллейбуса от начала пути (конец дуги A∩B, полоса A на запад), м; машины — через length / 4.
## 55 м: троллейбус на A у x = 6, «Жигули» на D, «Волга» на C у x = 4, «Газель» на B у z = −35.
const START_OFFSET := 55.0
const CAR_KINDS: Array[StringName] = [&"zhiguli", &"volga", &"gazelle"]
const MIN_START_CLEARANCE := 20.0

var path: PathVehicle.LanePath
var vehicles: Array = []   # [Trolleybus, TrafficCar × 3] — в порядке по кольцу
var trolleybus: Trolleybus
var cars: Array = []

func _init() -> void:
	name = "Traffic"

func _ready() -> void:
	path = PathVehicle.LanePath.build(Layout.RING, Layout.RING_LANE, PathVehicle.TURN_RADIUS)
	var count := 1 + Layout.TRAFFIC_CARS
	var offsets := start_offsets(path.length)
	trolleybus = TrolleybusScript.new()
	trolleybus.name = "Trolleybus13"
	vehicles.append(trolleybus)
	for i in Layout.TRAFFIC_CARS:
		var car: TrafficCar = TrafficCarScript.new()
		car.kind = CAR_KINDS[i % CAR_KINDS.size()]
		car.name = "Car_%s" % car.kind
		vehicles.append(car)
		cars.append(car)
	for i in count:
		var vehicle: PathVehicle = vehicles[i]
		vehicle.peers = vehicles
		add_child(vehicle)
		vehicle.setup(path, offsets[i])
	var world := _world()
	var rig: Node = world.get_node_or_null("CameraRig") if world else null
	if rig and rig.has_method("exclude_permanently"):
		for vehicle in vehicles:
			rig.call_deferred("exclude_permanently", vehicle.get_rid())   # CameraRig готовится позже LevelGeometry

## Смещения старта: троллейбус и TRAFFIC_CARS машин равномерно по кольцу.
static func start_offsets(length: float) -> Array[float]:
	var count := 1 + Layout.TRAFFIC_CARS
	var out: Array[float] = []
	for i in count:
		out.append(fposmod(START_OFFSET + length * i / count, length))
	return out

func _world() -> Node:
	var node := get_parent()
	while node:
		if node is DemoWorld:
			return node
		node = node.get_parent()
	return null

## Для тестов и перезапуска: вернуть всех на места старта.
func reset_positions() -> void:
	var offsets := start_offsets(path.length)
	for i in vehicles.size():
		var vehicle: PathVehicle = vehicles[i]
		vehicle.setup(path, offsets[i])
		vehicle.distance_travelled = 0.0
	trolleybus.dwell_left = 0.0
	trolleybus._set_doors(false)
