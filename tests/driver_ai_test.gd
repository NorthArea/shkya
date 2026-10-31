extends SceneTree
## Developer scenarios; independent real-world acceptance is DRIVER01_ACCEPTANCE.
const AI = preload("res://game/vehicles/driver_ai.gd")
const Route = preload("res://game/vehicles/driver_route.gd")
const Layout = preload("res://game/world/layout.gd")
const Vehicle = preload("res://game/vehicles/path_vehicle.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var lane = Vehicle.LanePath.build(Layout.CAR_RING, Layout.RING_LANE, Vehicle.CAR_TURN_RADIUS)
	var route = Route.new()
	route.configure(lane, Vector3(1.62, 1.44, 4.07))
	var from: Vector3 = Layout.ROUTE_DETOUR[1]
	var goal: Vector3 = Layout.ROUTE_DRIVE[0]
	check(route.plan(from, Vector3.FORWARD, goal), "kiosk-to-home has a road route with northbound initial heading")
	var visits_north := false
	var visits_west := false
	for point in route.points:
		visits_north = visits_north or point.z < Layout.RING[2].z + 8.0
		visits_west = visits_west or point.x < Layout.RING[2].x + 8.0
	check(visits_north and visits_west, "northbound driver goes around the existing block instead of reversing across the street")
	check(route.length > 300.0, "detour has physical road distance")
	check(not route.plan(from, Vector3.FORWARD, Layout.KIOSK), "a goal inside the kiosk is unreachable by car")
	check(route.plan(from, Vector3.FORWARD, goal), "invalid goal does not poison the graph")
	var straight_limit := AI.curvature_speed(0.0)
	var snowy_corner := AI.curvature_speed(0.25)
	check(straight_limit == AI.MAX_SPEED and snowy_corner < 4.0, "snow lateral grip reduces tight corner speed")
	check(AI.braking_speed(0.0, 0.0) == 0.0, "zero remaining distance requires a stop")
	check(AI.braking_speed(2.0, 20.0) > AI.braking_speed(2.0, 2.0), "controller brakes before reaching the bend")
	var driver = AI.new()
	check(not driver.is_active(), "ordinary city driving is the default")
	check(not driver.set_mode(&"pursue"), "pursuit requires an actual target and vehicle")
	check(not driver.set_mode(&"race", null, []), "race requires explicit road waypoints")
	print("DRIVER_AI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
