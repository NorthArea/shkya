extends Node3D
## Транспорт на кольце арены (ARENA-01, часть T, контракт C8): три машины («Жигули», «Волга», «Газель») и
## троллейбус ЗиУ-9 маршрута 13. Троллейбус — по правой полосе кольца Layout.RING (по часовой стрелке), машины —
## во встречном направлении по своей правой полосе Layout.CAR_RING (ARENA-01 fix P2-2: на одной полосе с
## троллейбусом все три через 1–2 круга вставали колонной за ним). Старт троллейбуса — START_OFFSET, машин —
## равномерно по своей полосе с шагом length / TRAFFIC_CARS от CAR_START_OFFSET; ни один не стартует ближе
## MIN_START_CLEARANCE к CAR_SPAWN, стоянке у киоска и VAN_PARK (проверяет traffic_test.gd). Без случайностей.
## Узел создаёт LevelGeometry (ребёнок DemoWorld/LevelGeometry/Traffic, как Patrols); мир ищется вверх по дереву.
## Корпуса транспорта исключены из луча камеры, как тела NPC в Patrols: проезжающая машина не дёргает камеру.

const Layout = preload("res://game/world/layout.gd")
const PathVehicleScript = preload("res://game/vehicles/path_vehicle.gd")
const TrafficCarScript = preload("res://game/vehicles/traffic_car.gd")
const TrolleybusScript = preload("res://game/vehicles/trolleybus.gd")

## Смещение троллейбуса от начала его пути (конец дуги A∩B, полоса A на запад), м: на A у x = 6.
const START_OFFSET := 55.0
## Смещение первой машины от начала пути машин (конец дуги A∩B, полоса B на север, (73, 31)), м; дальше — через
## length / 3: «Жигули» на B у z = 1, «Волга» на C у x ≈ −5, «Газель» на D у z ≈ 21.
const CAR_START_OFFSET := 30.0
const CAR_KINDS: Array[StringName] = [&"zhiguli", &"volga", &"gazelle"]
const MIN_START_CLEARANCE := 20.0

var occupants_enabled := true
var path: PathVehicle.LanePath       # полоса троллейбуса (RING)
var car_path: PathVehicle.LanePath   # полоса машин (CAR_RING, встречная)
var vehicles: Array = []   # [Trolleybus, TrafficCar × 3]
var trolleybus: Trolleybus
var cars: Array = []

func _init() -> void:
	name = "Traffic"

func _ready() -> void:
	path = PathVehicle.LanePath.build(Layout.RING, Layout.RING_LANE, PathVehicle.TURN_RADIUS)
	car_path = PathVehicle.LanePath.build(Layout.CAR_RING, Layout.RING_LANE, PathVehicle.CAR_TURN_RADIUS)
	var count := 1 + Layout.TRAFFIC_CARS
	var offsets := start_offsets(path.length, car_path.length)
	trolleybus = TrolleybusScript.new()
	trolleybus.occupants_enabled = occupants_enabled
	trolleybus.name = "Trolleybus13"
	vehicles.append(trolleybus)
	for i in Layout.TRAFFIC_CARS:
		var car: TrafficCar = TrafficCarScript.new()
		car.kind = CAR_KINDS[i % CAR_KINDS.size()]
		car.name = "Car_%s" % car.kind
		vehicles.append(car)
		cars.append(car)
	trolleybus.peers = [trolleybus]
	for i in count:
		var vehicle: PathVehicle = vehicles[i]
		if vehicle != trolleybus:
			vehicle.peers = cars   # дистанция — только до своих на той же полосе
		add_child(vehicle)
		vehicle.setup(lane_of(vehicle), offsets[i])
	var world := _world()
	var rig: Node = world.get_node_or_null("CameraRig") if world else null
	if rig and rig.has_method("exclude_permanently"):
		for vehicle in vehicles:
			rig.call_deferred("exclude_permanently", vehicle.get_rid())   # CameraRig готовится позже LevelGeometry

## Смещения старта: [троллейбус на своей полосе, TRAFFIC_CARS машин равномерно по полосе машин].
static func start_offsets(trolley_length: float, car_length: float) -> Array[float]:
	var out: Array[float] = [fposmod(START_OFFSET, trolley_length)]
	for i in Layout.TRAFFIC_CARS:
		out.append(fposmod(CAR_START_OFFSET + car_length * i / Layout.TRAFFIC_CARS, car_length))
	return out

## Полоса транспорта: троллейбус — RING, машины — CAR_RING.
func lane_of(vehicle: PathVehicle) -> PathVehicle.LanePath:
	return path if vehicle == trolleybus else car_path

func _world() -> Node:
	var node := get_parent()
	while node:
		if node is DemoWorld:
			return node
		node = node.get_parent()
	return null

## Для тестов и перезапуска: вернуть всех на места старта.
func reset_positions() -> void:
	var offsets := start_offsets(path.length, car_path.length)
	for i in vehicles.size():
		var vehicle: PathVehicle = vehicles[i]
		vehicle.setup(lane_of(vehicle), offsets[i])
		vehicle.distance_travelled = 0.0
	trolleybus.dwell_left = 0.0
	trolleybus._set_doors(false)
