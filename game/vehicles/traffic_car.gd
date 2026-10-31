class_name TrafficCar
extends PathVehicle
## Машина на кольце (ARENA-01, часть T; облик — CITY-02 V): «Жигули» (ВАЗ-2106), «Волга» (ГАЗ-3110) или «Газель»
## (цельнометаллическая ГАЗ-2705). Все кузова — общие меши соответствующих визуальных провайдеров.
## Колёса с дисками и протектором крутятся, фары горят,
## габариты ярче при торможении, снег на крыше, выхлоп на морозе. kind задаётся до добавления в дерево.
## Скорость 9 м/с (C8). Перед — −Z.

const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const LadaVisual = preload("res://game/vehicles/lada_visual.gd")
const Gaz3110 = preload("res://game/vehicles/gaz3110_visual.gd")
const Gazelle = preload("res://game/vehicles/gazelle_visual.gd")
const DriverAI = preload("res://game/vehicles/driver_ai.gd")
const DRIVER_STEER_RATE := 2.5

const KINDS := {
	&"zhiguli": {"size": Vector3(1.62, 1.44, 4.07), "wheelbase": 2.42, "radius": 0.32, "paint": Color(0.62, 0.12, 0.08), "plate": "в417ам 54"},
	&"volga": {"size": Gaz3110.SIZE, "wheelbase": Gaz3110.WHEELBASE, "radius": Gaz3110.WHEEL_RADIUS, "paint": Color(0.80, 0.72, 0.52), "plate": "к208ро 154"},
	&"gazelle": {"size": Gazelle.SIZE, "wheelbase": Gazelle.WHEELBASE, "radius": Gazelle.WHEEL_RADIUS, "paint": Color(0.16, 0.30, 0.55), "plate": "т655ес 54"},
}

var kind: StringName = &"zhiguli"
var driver_ai: DriverAI = DriverAI.new()
var _driver_speed := 0.0
var _driver_steer := 0.0
var _driver_yaw := 0.0

func _init() -> void:
	super._init()
	cruise_speed = 9.0
	corner_speed = 5.0
	can_yield = true   # POLISH-03 C: встречной «Ладе» уступает, прижимаясь к обочине

func _ready() -> void:
	var spec: Dictionary = KINDS[kind]
	size = spec["size"]
	wheelbase = spec["wheelbase"]
	wheel_radius = spec["radius"]
	super._ready()
	collision_mask = VehicleImpact.SAFE_MASK
	var mass := 1045.0
	if kind == &"volga":
		mass = 1470.0
	elif kind == &"gazelle":
		mass = 2100.0
	VehicleImpact.register(self, mass, size, visual, receive_vehicle_impact, vehicle_velocity, vehicle_yaw)
	driver_ai.attach(self)

func setup(lane_path: LanePath, offset: float) -> void:
	driver_ai.clear()
	_driver_speed = 0.0
	_driver_steer = 0.0
	_driver_yaw = 0.0
	super.setup(lane_path, offset)
	if is_inside_tree():
		driver_ai.attach(self)

## Mission/test entry points. Merely creating city traffic never enables these modes.
func start_driving(mode: StringName, target: Node3D = null, waypoints: Array[Vector3] = []) -> bool:
	var was_active := driver_ai.is_active()
	var accepted := driver_ai.set_mode(mode, target, waypoints)
	if driver_ai.is_active():
		_driver_speed = clampf(_actual_velocity.dot(-global_basis.z), -DriverAI.REVERSE_SPEED, DriverAI.MAX_SPEED)
		_driver_steer = 0.0
		_driver_yaw = 0.0
	elif was_active:
		_return_to_lane()
	return accepted

func stop_driving() -> void:
	var was_active := driver_ai.is_active()
	driver_ai.clear()
	if was_active:
		_return_to_lane()

func _return_to_lane() -> void:
	if not impact_active:
		impact_active = true
		impact_velocity = _actual_velocity
		impact_yaw = _driver_yaw
		_impact_recovering = false
	_driver_speed = 0.0
	_driver_steer = 0.0
	_driver_yaw = 0.0

func _physics_process(delta: float) -> void:
	if path == null or delta <= 0.0:
		return
	if impact_active and driver_ai.is_active():
		driver_ai.suspend(delta)
	if impact_active or not driver_ai.is_active():
		super._physics_process(delta)
		return
	_driver_step(delta)

func vehicle_yaw() -> float:
	return impact_yaw if impact_active else _driver_yaw

func _impact_step(delta: float) -> void:
	super._impact_step(delta)
	# An explicit driver resumes from its displaced pose only after the physical impact has settled.
	if _impact_recovering and driver_ai.is_active():
		impact_active = false
		_impact_recovering = false
		_driver_speed = 0.0
		_driver_yaw = 0.0
		_actual_velocity = Vector3.ZERO

func _driver_step(delta: float) -> void:
	var command := driver_ai.tick(delta)
	var desired: float = command["target_speed"]
	if command["reverse"]:
		desired = -minf(desired, DriverAI.REVERSE_SPEED)
	var previous_speed := absf(_driver_speed)
	if _driver_speed * desired < 0.0:
		_driver_speed = move_toward(_driver_speed, 0.0, DriverAI.DECEL * delta)
	else:
		var rate := DriverAI.ACCEL if absf(desired) > previous_speed else DriverAI.DECEL
		_driver_speed = move_toward(_driver_speed, desired, rate * delta)
	_driver_steer = move_toward(_driver_steer, command["steering"], DRIVER_STEER_RATE * delta)
	_driver_yaw = -_driver_speed / wheelbase * tan(_driver_steer * DriverAI.MAX_STEER)
	var forward := (-global_basis.z).rotated(Vector3.UP, _driver_yaw * delta * 0.5)
	var motion := forward * _driver_speed * delta
	# The shared solver observes the commanded velocity at the contact before its impulse is applied.
	_actual_velocity = motion / delta
	var moved := VehicleImpact.safe_move(self, motion, 0.0, size)
	_actual_velocity = moved / delta
	if not impact_active:
		# A bicycle cannot steer its chassis without wheel travel. Impact spin remains independent.
		var travel_fraction := clampf(moved.length() / maxf(motion.length(), 0.00001), 0.0, 1.0)
		_driver_yaw *= travel_fraction
		VehicleImpact.safe_move(self, Vector3.ZERO, _driver_yaw * delta, size)
	if not impact_active and moved.length_squared() + 0.000001 < motion.length_squared():
		_driver_speed = moved.dot(forward) / delta
	speed = signf(_driver_speed) * moved.length() / delta
	last_decel = maxf((previous_speed - absf(speed)) / delta, 0.0)
	distance_travelled += moved.length()
	s = path.offset_of(global_position)
	blocked_by = driver_ai.blocked_by
	obstacle_gap = driver_ai.obstacle_gap
	blocked_time = blocked_time + delta if blocked_by != null and absf(speed) < 0.05 else 0.0
	limit_reason = driver_ai.reason
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.UP, -moved.dot(forward) / wheel_radius)
	_tail.emission_energy_multiplier = 3.5 if absf(desired) < previous_speed or absf(speed) < 0.05 else 0.8

func _build_visual() -> Node3D:
	if kind == &"gazelle":
		return _gazelle()
	if kind == &"volga":
		return _volga()
	return _sedan(&"vaz2106")

func _head() -> StandardMaterial3D:
	return VehicleMesh.lamp(Color(1.0, 0.95, 0.80), Color(1.0, 0.90, 0.66), 2.2)

func _volga() -> Node3D:
	var spec: Dictionary = KINDS[&"volga"]
	var root := Gaz3110.build(spec["paint"], spec["plate"], 0.1)
	var body_mesh := root.get_node("Body/BodyMesh") as MeshInstance3D
	var slots: Array = body_mesh.mesh.get_meta("slots", [])
	body_mesh.set_surface_override_material(slots.find("head"), _head())
	body_mesh.set_surface_override_material(slots.find("tail"), _tail)
	# PathVehicle rotates the mesh's local Y axis; WheelPivot holds the fixed axle position.
	for child in root.get_children():
		if String(child.name).begins_with("WheelPivot"):
			_wheels.append(child.get_node("Wheel") as Node3D)
	VehicleMesh.exhaust(root, Vector3(0.58, 0.215, 2.36))
	return root

## Седан: кузов LadaVisual в цвете машины, свои фары и габариты (_tail ярче при торможении).
func _sedan(model: StringName) -> Node3D:
	var root := Node3D.new()
	var spec: Dictionary = KINDS[kind]
	var paint := VehicleMesh.paint(spec["paint"], 0.3, 0.85, 0.35, 0.65)
	LadaVisual.dress(root, model, paint, VehicleMesh.glass(0.04), _head(), _tail, spec["plate"], 0.1)
	var sedan: Dictionary = LadaVisual.SEDANS[model]
	for spot in LadaVisual.wheel_spots(model):
		_wheels.append(VehicleMesh.add_wheel(root, spot, wheel_radius, sedan["wheel_w"], sedan["wheel_style"]))
	VehicleMesh.exhaust(root, Vector3(-0.45, 0.29, float(sedan["length"]) * 0.5 + 0.1))
	return root

## Общая цельнометаллическая 2705: тот же kind и место в потоке, собственные лампы.
func _gazelle() -> Node3D:
	var spec: Dictionary = KINDS[&"gazelle"]
	var root := Gazelle.build(spec["paint"], spec["plate"], 0.1, Gazelle.CARGO)
	var body_mesh := root.get_node("Body/BodyMesh") as MeshInstance3D
	var slots: Array = body_mesh.mesh.get_meta("slots", [])
	body_mesh.set_surface_override_material(slots.find("head"), _head())
	body_mesh.set_surface_override_material(slots.find("tail"), _tail)
	# Provider owns isolated paint/amber materials; pivots keep all six axle centers
	# while PathVehicle spins each wheel around its transverse local UP axis.
	for child in root.get_children():
		if String(child.name).begins_with("WheelPivot"):
			_wheels.append(child.get_node("Wheel") as Node3D)
	var exhaust := VehicleMesh.exhaust(root, Vector3(-0.95, 0.255, 0.72))
	exhaust.direction = Vector3(-0.25, 0.10, 0.12).normalized()
	return root
