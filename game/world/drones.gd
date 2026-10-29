extends Node3D
## Мини-дроны ГСУМ «уточняют маршруты» (PUNCH-01, решение владельца 29.10): идея ос-камер *Hit & Run* без ассетов.
## Дрон летит по петле Layout.DRONE_LOOPS (2–3 м/с, 1,6–2,2 м), жужжит (SoundDirector, 3D по удалению). Илюша пешком (не в
## укрытии, без диалога) ближе ENGAGE_DISTANCE — один дрон подлетает и зависает в HOVER_DISTANCE перед ним, чуть
## сбоку, покачиваясь и мигая красным («смотрит»), через HOVER_SECONDS улетает на свою петлю и IGNORE_SECONDS его не
## замечает. Удар Илюши (Ilyusha.punch_landed) по дрону — дрон рассыпается 4–6 обломками (исчезают за DEBRIS_SECONDS),
## хлопок, 5 монет через Coins.spawn_burst (если узел Coins есть — COINS-01), возрождение через 60–90 с на другой
## свободной петле. Удар по патрулю (дети Patrols) — субтитр PATROL_GAG через SoundDirector.show_gag не чаще раза в
## GAG_COOLDOWN; по жителям и Бабке — ничего. Провала и подозрения нет.
## Коллизий нет: попадание — Area3D на слое HIT_LAYER (5-й бит, вне World/Player/Car/Interact): транспорт, лучи
## наблюдателей (маска World|Car, без областей), пружина камеры и зонд E их не видят. Дроны не сенсоры: в группе
## detection_sensors их нет. Узел создаёт LevelGeometry (DemoWorld/LevelGeometry/Drones). Случайности — только из
## RandomNumberGenerator с SEED.
## Облик — свой, из объёмов Godot, по форме недорогих мини-дронов с защитой винтов (Ryze Tello с кольцами, Eachine
## E010): плоский корпус 20 см (×DRONE_SCALE в кадре) с камерой-глазком и LED спереди, четыре луча крестом, моторы, винты в
## кольцах. Без логотипов: мелко «ГСУМ» на крышке.

const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")

signal drone_broken(drone: Node3D)
signal drone_respawned(drone: Node3D)

const GROUP := &"drones"
const SEED := 2930
const HIT_LAYER := 16
const HIT_RADIUS := 0.35
## Масштаб облика: модель с корпусом 0,20 м в кадре игровой камеры (4,3 м за Илюшей) читалась палочкой в 50 px
## (кадр PUNCH-01/01, 29.10) — в кадре корпус 0,30 м, размах 0,54 м.
const DRONE_SCALE := 1.5
const WATCH_TILT := 0.35         # рад: при осмотре нос вниз, к Илюше, — крышка с «ГСУМ» видна из-за его спины
const ENGAGE_DISTANCE := 6.0     # м по горизонтали от Илюши до дрона: ближе — подлёт
const DISENGAGE_DISTANCE := 12.0 # м: Илюша убежал — дрон бросает и улетает
const HOVER_DISTANCE := 2.0      # м перед Илюшей
const HOVER_SIDE := 0.6          # м вбок, чтобы из-за спины камеры дрон не прятался за головой
const HOVER_HEIGHT := 1.9        # м над землёй: на уровне лица фигуры 1,8 м, над головой в кадре камеры
const HOVER_SECONDS := 5.0
const IGNORE_SECONDS := 12.0     # после «осмотра» — не подлетать снова
const APPROACH_SPEED := 3.5
const FOLLOW_SPEED := 4.5        # м/с: держится перед идущим Илюшей (ходьба 4 м/с)
const LEAVE_SPEED := 3.0
const RESPAWN := Vector2(60.0, 90.0)
const RESPAWN_FAR := 15.0        # м: место возрождения по возможности не ближе к Илюше
const DEBRIS_SECONDS := 1.5
const COINS_PER_DRONE := 5
const PATROL_GAG := "Гражданин, руками не размахивайте"
const GAG_COOLDOWN := 20.0
const PROP_SPIN := 31.0          # рад/с — винты; размытый диск поверх

var drones: Array = []
## Для проверок: сбито, возрождено, монетных россыпей, показано субтитров патруля, удары по жителям/Бабке.
var breaks := 0
var respawns := 0
var coin_bursts := 0
var gags := 0
var harmless_hits := 0
## Последние россыпи: [позиция, число монет] — для проверок.
var bursts: Array = []
var debris: Array = []
var clock := 0.0

var _rng := RandomNumberGenerator.new()
var _world: Node
var _player: Node3D
var _engaged: Drone
var _last_gag := -INF
var _loops: Array = []      # [{points: Array[Vector3], lengths: Array[float], total, height, speed}]

func _init() -> void:
	name = "Drones"

func _ready() -> void:
	add_to_group(GROUP)
	_rng.seed = SEED
	_world = _find_world()
	if _world:
		_player = _world.get_node_or_null("Ilyusha")
	if _player and _player.has_signal("punch_landed"):
		_player.punch_landed.connect(_on_punch_landed)
	for spec: Array in Layout.DRONE_LOOPS:
		var points: Array[Vector3] = []
		for p: Vector2 in spec[0]:
			points.append(Vector3(p.x, 0.0, p.y))
		var lengths: Array[float] = [0.0]
		var total := 0.0
		for i in points.size():
			total += points[i].distance_to(points[(i + 1) % points.size()])
			lengths.append(total)
		_loops.append({"points": points, "lengths": lengths, "total": total, "height": spec[1], "speed": spec[2]})
	var shared := Drone.shared_parts()
	for i in Layout.DRONE_START_LOOPS.size():
		var drone := Drone.new()
		drone.name = "Drone%d" % i
		drone.index = i
		drone.phase = float(i) * 1.37
		add_child(drone)
		drone.build(shared)
		var loop: int = Layout.DRONE_START_LOOPS[i]
		_place_on_loop(drone, loop, fmod(float(i) * 3.7, _loops[loop]["total"]))
		drones.append(drone)

func _find_world() -> Node:
	var node := get_parent()
	while node:
		if node is DemoWorld:
			return node
		node = node.get_parent()
	return null

func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	clock += delta
	var watcher := _watchable_player()
	if _engaged and (not is_instance_valid(_engaged) or _engaged.state == &"broken"):
		_engaged = null
	for drone: Drone in drones:
		_update_drone(drone, delta, watcher)
	_update_debris(delta)

## Илюша, которого можно «осматривать»: пешком, виден, не в укрытии, без диалога и провала. Иначе null.
func _watchable_player() -> Node3D:
	if _player == null or not is_instance_valid(_player) or not _player.visible:
		return null
	if _world:
		if _world.get("control_mode") != &"on_foot" or _world.get("ui_blocking") == true:
			return null
		if _world.has_method("is_stealth_failing") and _world.is_stealth_failing():
			return null
	if _player.get("hide_mode") != null and _player.hide_mode != HideTuning.NONE:
		return null
	return _player

# --- полёт ---

func _update_drone(drone: Drone, delta: float, watcher: Node3D) -> void:
	drone.timer += delta
	drone.ignore_left = maxf(drone.ignore_left - delta, 0.0)
	var before := drone.position
	match drone.state:
		&"broken":
			drone.respawn_left -= delta
			if drone.respawn_left <= 0.0:
				_respawn(drone)
			return
		&"patrol":
			var loop: Dictionary = _loops[drone.loop]
			drone.s = fmod(drone.s + float(loop["speed"]) * delta, float(loop["total"]))
			drone.position = _loop_point(drone.loop, drone.s) + Vector3.UP * _patrol_height(drone)
			if watcher and _engaged == null and drone.ignore_left <= 0.0 and _flat(drone.position).distance_to(_flat(watcher.global_position)) < ENGAGE_DISTANCE:
				_engaged = drone
				drone.state = &"approach"
				drone.timer = 0.0
				drone.approaches += 1
		&"approach", &"hover":
			if watcher == null or _flat(drone.position).distance_to(_flat(watcher.global_position)) > DISENGAGE_DISTANCE:
				_leave(drone)
			else:
				var target := hover_point(watcher)
				if drone.state == &"approach":
					drone.position = drone.position.move_toward(target, APPROACH_SPEED * delta)
					if drone.position.distance_to(target) < 0.3:
						drone.state = &"hover"
						drone.timer = 0.0
				else:
					target.y += 0.05 * sin(drone.timer * 3.1 + drone.phase)
					drone.position = drone.position.move_toward(target, FOLLOW_SPEED * delta)
					drone.hover_time += delta
					if drone.timer >= HOVER_SECONDS:
						_leave(drone)
		&"leave":
			var loop: Dictionary = _loops[drone.loop]
			var goal := _loop_point(drone.loop, drone.s) + Vector3.UP * float(loop["height"])
			drone.position = drone.position.move_toward(goal, LEAVE_SPEED * delta)
			if drone.position.distance_to(goal) < 0.05:
				drone.state = &"patrol"
				drone.timer = 0.0
	var moved := drone.position - before
	var look_at_player := drone.state == &"hover" or (drone.state == &"approach" and watcher != null)
	var heading := drone.rotation.y
	if look_at_player and watcher:
		var to := watcher.global_position - drone.global_position
		heading = atan2(-to.x, -to.z)
	elif Vector2(moved.x, moved.z).length() > 0.0005:
		heading = atan2(-moved.x, -moved.z)
	drone.rotation.y = lerp_angle(drone.rotation.y, heading, clampf(6.0 * delta, 0.0, 1.0))
	drone.animate(delta, moved.length() / delta)

func _patrol_height(drone: Drone) -> float:
	return float(_loops[drone.loop]["height"]) + Layout.DRONE_BOB * sin(drone.timer * 1.3 + drone.phase)

## Точка зависания перед Илюшей: HOVER_DISTANCE по взгляду облика, HOVER_SIDE вправо, HOVER_HEIGHT над землёй;
## стена или машина между — ближе, перед препятствием (луч по World|Car).
func hover_point(watcher: Node3D) -> Vector3:
	var look: Node3D = watcher.get("visual") if watcher.get("visual") is Node3D else watcher
	var forward := -look.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	var base := watcher.global_position
	var target := base + forward * HOVER_DISTANCE + right * HOVER_SIDE
	target.y = base.y + HOVER_HEIGHT
	var from := base + Vector3.UP * HOVER_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, target, 1 | 4)
	if watcher is CollisionObject3D:
		query.exclude = [(watcher as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var dir := (target - from).normalized()
		target = hit["position"] - dir * 0.4
	return target

func _leave(drone: Drone) -> void:
	if _engaged == drone:
		_engaged = null
	drone.state = &"leave"
	drone.timer = 0.0
	drone.ignore_left = IGNORE_SECONDS
	drone.s = _closest_s(drone.loop, drone.position)

func _place_on_loop(drone: Drone, loop: int, s: float) -> void:
	drone.loop = loop
	drone.s = s
	drone.state = &"patrol"
	drone.timer = 0.0
	drone.position = _loop_point(loop, s) + Vector3.UP * _patrol_height(drone)
	var ahead := _loop_point(loop, fmod(s + 0.5, float(_loops[loop]["total"])))
	var dir := ahead - _loop_point(loop, s)
	drone.rotation.y = atan2(-dir.x, -dir.z)

func _loop_point(loop: int, s: float) -> Vector3:
	var data: Dictionary = _loops[loop]
	var points: Array[Vector3] = data["points"]
	var lengths: Array[float] = data["lengths"]
	for i in points.size():
		if s <= lengths[i + 1]:
			var span := lengths[i + 1] - lengths[i]
			var k := (s - lengths[i]) / span if span > 0.0 else 0.0
			return points[i].lerp(points[(i + 1) % points.size()], k)
	return points[0]

func _closest_s(loop: int, p: Vector3) -> float:
	var data: Dictionary = _loops[loop]
	var points: Array[Vector3] = data["points"]
	var lengths: Array[float] = data["lengths"]
	var best := INF
	var best_s := 0.0
	var flat := _flat(p)
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var q := Geometry3D.get_closest_point_to_segment(flat, a, b)
		var d := q.distance_to(flat)
		if d < best:
			best = d
			best_s = lengths[i] + a.distance_to(q)
	return best_s

## Петля, где сейчас дрон (для проверок): индекс в Layout.DRONE_LOOPS.
func loop_points(loop: int) -> Array[Vector3]:
	return _loops[loop]["points"]

static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)

# --- удар ---

func _on_punch_landed(targets: Array) -> void:
	for target in targets:
		if target is Drone:
			break_drone(target)
		elif target is Node and _is_patrol(target):
			_patrol_gag()
		else:
			harmless_hits += 1

func _is_patrol(node: Node) -> bool:
	var parent := node.get_parent()
	return parent != null and parent.name == &"Patrols"

func _patrol_gag() -> void:
	if clock - _last_gag < GAG_COOLDOWN and _last_gag > -INF:
		return
	_last_gag = clock
	var sound: Node = _world.get_node_or_null("SoundDirector") if _world else null
	if sound and sound.has_method("show_gag"):
		sound.show_gag([PATROL_GAG], 2.5)
		gags += 1

## Сбить дрон: обломки, хлопок (сигнал drone_broken), монеты, таймер возрождения. Сбитый — без попаданий и звука.
func break_drone(drone: Drone) -> void:
	if drone.state == &"broken":
		return
	if _engaged == drone:
		_engaged = null
	var at := drone.global_position
	drone.state = &"broken"
	drone.timer = 0.0
	drone.breaks += 1
	drone.respawn_left = _rng.randf_range(RESPAWN.x, RESPAWN.y)
	drone.last_respawn_delay = drone.respawn_left
	drone.set_alive(false)
	breaks += 1
	_spawn_debris(drone, at)
	drone_broken.emit(drone)
	var coins := _coins()
	if coins:
		coins.spawn_burst(at, COINS_PER_DRONE)
		coin_bursts += 1
		bursts.append([at, COINS_PER_DRONE])

## Узел монет COINS-01: группа «coins» или узел «Coins» в мире; с методом spawn_burst. Нет — null.
func _coins() -> Node:
	var node: Node = get_tree().get_first_node_in_group(&"coins")
	if node == null and _world:
		node = _world.find_child("Coins", true, false)
	return node if node and node.has_method("spawn_burst") else null

func _respawn(drone: Drone) -> void:
	var busy := {}
	for other: Drone in drones:
		if other != drone and other.state != &"broken":
			busy[other.loop] = true
	var free: Array[int] = []
	var far: Array[int] = []
	for i in _loops.size():
		if busy.has(i) or i == drone.loop:
			continue
		free.append(i)
		if _player == null or _loop_distance(i, _player.global_position) >= RESPAWN_FAR:
			far.append(i)
	var pool: Array[int] = far if not far.is_empty() else free
	var loop: int = drone.loop if pool.is_empty() else pool[_rng.randi() % pool.size()]
	drone.previous_loop = drone.loop
	_place_on_loop(drone, loop, _rng.randf_range(0.0, float(_loops[loop]["total"])))
	drone.ignore_left = 3.0
	drone.set_alive(true)
	respawns += 1
	drone_respawned.emit(drone)

func _loop_distance(loop: int, p: Vector3) -> float:
	var s := _closest_s(loop, p)
	return _flat(_loop_point(loop, s)).distance_to(_flat(p))

# --- обломки ---

func _spawn_debris(drone: Drone, at: Vector3) -> void:
	var parts := drone.debris_parts()
	var count := _rng.randi_range(4, 6)
	for i in count:
		var spec: Array = parts[i % parts.size()]
		var piece := MeshInstance3D.new()
		piece.name = "DroneDebris"
		piece.mesh = spec[0]
		piece.material_override = spec[1]
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		piece.global_position = at + Vector3(_rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.03, 0.05), _rng.randf_range(-0.08, 0.08))
		var a := TAU * float(i) / float(count) + _rng.randf_range(-0.3, 0.3)
		var velocity := Vector3(cos(a) * _rng.randf_range(1.5, 3.0), _rng.randf_range(1.5, 3.2), sin(a) * _rng.randf_range(1.5, 3.0))
		var spin := Vector3(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12), _rng.randf_range(-12, 12))
		debris.append({"node": piece, "velocity": velocity, "spin": spin, "age": 0.0})

func _update_debris(delta: float) -> void:
	var keep: Array = []
	for d: Dictionary in debris:
		var piece: MeshInstance3D = d["node"]
		d["age"] = float(d["age"]) + delta
		var age: float = d["age"]
		if age >= DEBRIS_SECONDS or not is_instance_valid(piece):
			if is_instance_valid(piece):
				piece.queue_free()
			continue
		var v: Vector3 = d["velocity"]
		v.y -= 9.8 * delta
		var p := piece.global_position + v * delta
		if p.y < 0.03:   # о снег: гаснет и ложится
			p.y = 0.03
			v = Vector3(v.x * 0.4, absf(v.y) * 0.25, v.z * 0.4)
		d["velocity"] = v
		piece.global_position = p
		piece.rotation += (d["spin"] as Vector3) * delta
		var fade := clampf((DEBRIS_SECONDS - age) / 0.5, 0.0, 1.0)
		piece.scale = Vector3.ONE * DRONE_SCALE * maxf(fade, 0.01)
		keep.append(d)
	debris = keep

# --- облик ---

## Мини-дрон: корпус 0,20 × 0,11 × 0,05 м (×DRONE_SCALE), лучи крестом к четырём винтам в кольцах (размах 0,36 м), камера-глазок и
## LED спереди, на крышке — «ГСУМ». Перед — −Z. Ноль тел; только Area3D попадания.
class Drone extends Node3D:
	var index := 0
	var phase := 0.0
	var loop := 0
	var previous_loop := -1
	var s := 0.0
	var state: StringName = &"patrol"   # patrol, approach, hover, leave, broken
	var timer := 0.0
	var ignore_left := 0.0
	var respawn_left := 0.0
	var last_respawn_delay := 0.0
	var breaks := 0
	var approaches := 0
	var hover_time := 0.0
	var hit_area: Area3D
	var visual: Node3D
	var led: MeshInstance3D
	var _parts: Dictionary
	var _props: Array[Node3D] = []
	var _spin := 0.0

	static func shared_parts() -> Dictionary:
		var body := BoxMesh.new()
		body.size = Vector3(0.11, 0.045, 0.20)
		var shell := SphereMesh.new()
		shell.radius = 0.06
		shell.height = 0.05
		shell.radial_segments = 12
		shell.rings = 4
		var arm := BoxMesh.new()
		arm.size = Vector3(0.018, 0.012, 0.13)
		var motor := CylinderMesh.new()
		motor.top_radius = 0.014
		motor.bottom_radius = 0.016
		motor.height = 0.026
		motor.radial_segments = 8
		var ring := TorusMesh.new()
		ring.inner_radius = 0.058
		ring.outer_radius = 0.068
		ring.rings = 16
		ring.ring_segments = 4
		var blade := BoxMesh.new()
		blade.size = Vector3(0.11, 0.003, 0.014)
		var disc := CylinderMesh.new()
		disc.top_radius = 0.056
		disc.bottom_radius = 0.056
		disc.height = 0.002
		disc.radial_segments = 16
		var eye := SphereMesh.new()
		eye.radius = 0.019
		eye.height = 0.038
		eye.radial_segments = 10
		eye.rings = 5
		var lens := SphereMesh.new()
		lens.radius = 0.009
		lens.height = 0.018
		lens.radial_segments = 8
		lens.rings = 4
		var bulb := SphereMesh.new()
		bulb.radius = 0.008
		bulb.height = 0.016
		bulb.radial_segments = 6
		bulb.rings = 3
		var blur := StandardMaterial3D.new()
		blur.albedo_color = Color(0.75, 0.77, 0.80, 0.22)
		blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blur.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return {
			"body": body, "shell": shell, "arm": arm, "motor": motor, "ring": ring, "blade": blade, "disc": disc,
			"eye": eye, "lens": lens, "bulb": bulb,
			"graphite": Materials.plain(Color(0.17, 0.18, 0.20), 0.45),
			"shell_mat": Materials.plain(Color(0.86, 0.87, 0.88), 0.35),
			"guard": Materials.plain(Color(0.95, 0.52, 0.12), 0.6),
			"black": Materials.plain(Color(0.03, 0.03, 0.04), 0.15),
			"lens_mat": Materials.plain(Color(0.10, 0.18, 0.30), 0.05, Color(0.35, 0.55, 0.9), 0.6),
			"blur": blur,
			"led_green": Materials.plain(Color(0.2, 0.9, 0.3), 0.4, Color(0.2, 1.0, 0.35), 3.0),
			"led_red": Materials.plain(Color(1.0, 0.15, 0.1), 0.4, Color(1.0, 0.1, 0.05), 4.0),
			"led_off": Materials.plain(Color(0.12, 0.05, 0.05), 0.4),
		}

	func build(parts: Dictionary) -> void:
		_parts = parts
		visual = Node3D.new()
		visual.name = "Visual"
		visual.scale = Vector3.ONE * DRONE_SCALE
		add_child(visual)
		_mesh(visual, parts["body"], Vector3.ZERO, parts["graphite"])
		var shell := _mesh(visual, parts["shell"], Vector3(0, 0.022, 0.01), parts["shell_mat"])
		shell.scale = Vector3(0.95, 1.0, 1.6)
		for k in 4:
			var sx := 1.0 if k % 2 == 0 else -1.0
			var sz := 1.0 if k < 2 else -1.0
			var hub := Vector3(sx * 0.115, 0.0, sz * 0.105)
			var arm := _mesh(visual, parts["arm"], hub * 0.55, parts["graphite"])
			arm.rotation.y = atan2(hub.x, hub.z)
			_mesh(visual, parts["motor"], hub + Vector3(0, 0.008, 0), parts["graphite"])
			_mesh(visual, parts["ring"], hub + Vector3(0, 0.012, 0), parts["guard"])
			var prop := Node3D.new()
			prop.position = hub + Vector3(0, 0.024, 0)
			visual.add_child(prop)
			_mesh(prop, parts["blade"], Vector3.ZERO, parts["black"])
			_mesh(prop, parts["disc"], Vector3(0, 0.002, 0), parts["blur"])
			prop.rotation.y = float(k) * 0.9
			_props.append(prop)
		# Камера-глазок на носу и LED над ней.
		_mesh(visual, parts["eye"], Vector3(0, 0.0, -0.1), parts["black"])
		_mesh(visual, parts["lens"], Vector3(0, 0.0, -0.116), parts["lens_mat"])
		led = _mesh(visual, parts["bulb"], Vector3(0.035, 0.026, -0.085), parts["led_green"])
		var label := Label3D.new()
		label.name = "Mark"
		label.text = "ГСУМ"
		label.font_size = 32
		label.pixel_size = 0.0011
		label.outline_size = 0
		label.modulate = Color(0.95, 0.95, 0.92)
		label.double_sided = false
		label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		label.position = Vector3(0, 0.049, 0.035)
		label.shaded = false
		label.no_depth_test = false
		visual.add_child(label)
		hit_area = Area3D.new()
		hit_area.name = "HitArea"
		hit_area.collision_layer = HIT_LAYER
		hit_area.collision_mask = 0
		hit_area.monitoring = false
		hit_area.monitorable = true
		var sphere := SphereShape3D.new()
		sphere.radius = HIT_RADIUS
		var shape := CollisionShape3D.new()
		shape.shape = sphere
		hit_area.add_child(shape)
		add_child(hit_area)

	func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = material
		mi.position = at
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		return mi

	## Покачивание, наклон по скорости, винты и LED: в патруле — зелёный раз в секунду, при осмотре — частый красный.
	func animate(delta: float, speed: float) -> void:
		_spin += PROP_SPIN * delta
		for i in _props.size():
			_props[i].rotation.y = _spin * (1.0 if i % 3 == 0 else -1.0) + float(i) * 0.9
		var watching := state == &"hover" or state == &"approach"
		var t := timer + phase
		var lean := clampf(speed * 0.06, 0.0, 0.25)
		visual.rotation.x = -lean + 0.05 * sin(t * 2.3) - (WATCH_TILT if state == &"hover" else 0.0)
		visual.rotation.z = 0.07 * sin(t * 1.7 + 0.4) + (0.18 * sin(t * 2.6) if state == &"hover" else 0.0)
		visual.position.y = 0.02 * sin(t * 4.1)
		var blink_on := fmod(t, 0.25) < 0.12 if watching else fmod(t, 1.0) < 0.15
		var material: Material = _parts["led_red"] if watching else _parts["led_green"]
		led.material_override = material if blink_on else _parts["led_off"]

	func set_alive(on: bool) -> void:
		visible = on
		hit_area.monitorable = on
		(hit_area.get_child(0) as CollisionShape3D).disabled = not on
		if on:
			visual.scale = Vector3.ONE * DRONE_SCALE * 0.3
			create_tween().tween_property(visual, "scale", Vector3.ONE * DRONE_SCALE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func is_flying() -> bool:
		return state != &"broken"

	## Обломки: [меш, материал] — половина корпуса, крышка, кольца, винт, луч.
	func debris_parts() -> Array:
		return [
			[_parts["body"], _parts["graphite"]], [_parts["ring"], _parts["guard"]], [_parts["shell"], _parts["shell_mat"]],
			[_parts["ring"], _parts["guard"]], [_parts["blade"], _parts["black"]], [_parts["arm"], _parts["graphite"]],
		]
