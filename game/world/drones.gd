extends Node3D
## Мини-дроны ГСУМ «уточняют маршруты» (PUNCH-01, решение владельца 29.10): идея ос-камер *Hit & Run* без ассетов.
## Дрон летит по петле Layout.DRONE_LOOPS (2–3 м/с, 1,6–2,2 м), жужжит (SoundDirector, 3D по удалению). Илюша пешком (не в
## укрытии, без диалога) ближе ENGAGE_DISTANCE — один дрон подлетает и зависает в HOVER_DISTANCE перед ним, чуть
## сбоку, покачиваясь, мигая чаще и светя на него прожектором («смотрит»), через HOVER_SECONDS улетает на свою петлю и
## IGNORE_SECONDS его не замечает. Удар Илюши (Ilyusha.punch_landed) по дрону — дрон рассыпается 4–6 обломками (исчезают за DEBRIS_SECONDS),
## хлопок, 5 монет через Coins.spawn_burst (если узел Coins есть — COINS-01), возрождение через 60–90 с на другой
## свободной петле. Удар по патрулю (дети Patrols) — субтитр PATROL_GAG через SoundDirector.show_gag не чаще раза в
## GAG_COOLDOWN; по Бабке — ничего, жители отвечают репликой push (Residents, TEXT-01). Провала и подозрения нет.
## Коллизий нет: попадание — Area3D на слое HIT_LAYER (5-й бит, вне World/Player/Car/Interact): транспорт, лучи
## наблюдателей (маска World|Car, без областей), пружина камеры и зонд E их не видят. Дроны не сенсоры: в группе
## detection_sensors их нет. Узел создаёт LevelGeometry (DemoWorld/LevelGeometry/Drones). Случайности — только из
## RandomNumberGenerator с SEED.
## Облик — свой, из объёмов Godot, по пропорциям недорогих мини-дронов с защитой винтов (Ryze Tello, Eachine E010 —
## только пропорции): плоский корпус с камерой в подвесе под носом, лучи крестом, моторы, винты в кольцах. PUNCH-02
## (поручение владельца 29.10 «перерисуй дронов в более заметных»): служебная окраска — оранжевый корпус с чёрными
## полосами и крупным «ГСУМ» на крышке и бортах, красно-синяя мигалка с ореолом (свой шейдер по образцу lamp_halo),
## светящиеся кольца винтов, антенна, белый прожектор вниз на снег (SpotLight3D — не больше SPOT_COUNT на весь рой:
## «смотрящий» дрон и ближайшие к камере; у остальных — светящееся пятно-декаль на снегу) и слабый конус луча; при
## подлёте луч поворачивается на Илюшу. Размер — по просвету петель: над тротуарами низ дрона выше головы Илюши
## (1,80 м) на петлях 2,0 м (низ петли 1,92) — поэтому корпус 0,40 м, а не больше.

const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")

signal drone_broken(drone: Node3D)
signal drone_respawned(drone: Node3D)

const GROUP := &"drones"
const SEED := 2930
const HIT_LAYER := 16
const HIT_RADIUS := 0.35
## Масштаб облика: модель с корпусом 0,21 м. PUNCH-01: ×1,5 (корпус 0,30 м, размах 0,55) терялся на фоне ночного города;
## PUNCH-02: ×1,9 — корпус 0,40 м, размах колец 0,73 м. Больше нельзя: низ дрона (подвес камеры, 0,10 м под центром
## с наклоном и покачиванием) над петлями 2,0 м (низ 1,92) должен проходить над головой Илюши 1,80 м (просветы —
## builds/checks/PUNCH-02/clearance.log).
const DRONE_SCALE := 1.9
const LEAN_PER_SPEED := 0.03     # рад на м/с: наклон по скорости (крупный дрон летит ровнее; низ не опускается на голову)
const LEAN_MAX := 0.09
const SPOT_COUNT := 2            # SpotLight3D на рой: «смотрящий» дрон первым, затем ближайшие к камере
const SPOT_REACH := 35.0         # м от камеры: дальше прожектор не включается, остаётся пятно на снегу
const SPOT_ENERGY := 5.0
const SPOT_RANGE := 7.0
const SPOT_ANGLE := 21.0         # градусов; конус луча — того же раствора
const HALO_SIZE := 1.6           # м, ореол мигалки
const POOL_SIZE := 1.5           # м, пятно на снегу под дроном без прожектора
const BEACON_PERIOD := 0.6       # с: красный-красный, синий-синий («стробы» служебной техники)
const BEACON_PERIOD_WATCH := 0.36
const WATCH_TILT := 0.35         # рад: при осмотре нос вниз, к Илюше, — крышка с «ГСУМ» видна из-за его спины
const ENGAGE_DISTANCE := 6.0     # м по горизонтали от Илюши до дрона: ближе — подлёт
const DISENGAGE_DISTANCE := 12.0 # м: Илюша убежал — дрон бросает и улетает
const HOVER_DISTANCE := 2.0      # м перед Илюшей
const HOVER_SIDE := 0.6          # м вбок, чтобы из-за спины камеры дрон не прятался за головой
const HOVER_SIDE_MAX := 1.0      # м: всё ещё внутри сферы удара при HOVER_DISTANCE и HOVER_HEIGHT
const VIEW_DRONE_RADIUS := 0.5   # м: охватывает кольца ×1,9 при любом yaw (размах по диагонали ≈0,98 м)
const VIEW_PLAYER_RADIUS := 0.28 # м: полуширина фигуры, которую оставляем свободной в проекции
const VIEW_CLEARANCE := 0.08     # м дополнительного просвета в плоскости героя
const HOVER_HEIGHT := 1.9        # м над землёй: на уровне лица фигуры 1,8 м, над головой в кадре камеры
const HOVER_SECONDS := 5.0
const IGNORE_SECONDS := 12.0     # после «осмотра» — не подлетать снова
const APPROACH_SPEED := 3.5
const FOLLOW_SPEED := 4.5        # м/с: держится перед идущим Илюшей (ходьба 4 м/с)
const LEAVE_SPEED := 3.0
## POLISH-03 B: на возврате с хлебом, пока улица Б перекрыта (MissionDirector.road_closed), рой «активнее»: по петлям
## быстрее, замечает Илюшу издалека, отвлекается ненадолго и сбитые возвращаются раньше. Включает RoadClosure.
const AGITATED_SPEED := 1.6
const AGITATED_ENGAGE := 9.0
const AGITATED_IGNORE := 5.0
const AGITATED_RESPAWN := 0.5     # множитель задержки возрождения
const RESPAWN := Vector2(60.0, 90.0)
const RESPAWN_FAR := 15.0        # м: место возрождения по возможности не ближе к Илюше
const DEBRIS_SECONDS := 1.5
const COINS_PER_DRONE := 5
const PATROL_GAG := "Гражданин, руками не машем!"
const GAG_COOLDOWN := 20.0

var drones: Array = []
## POLISH-03 B: рой «активнее» (set_agitated).
var agitated := false
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
var _hover_shape := SphereShape3D.new()

func _init() -> void:
	name = "Drones"
	_hover_shape.radius = VIEW_DRONE_RADIUS

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
	_update_lights(delta)
	_update_debris(delta)

## Прожекторы (PUNCH-02): SpotLight3D включён не больше чем у SPOT_COUNT дронов — у «смотрящего» (_engaged) и ближайших
## к камере в SPOT_REACH; у остальных — пятно-декаль на снегу. Луч «смотрящего» — на Илюшу (грудь), у прочих — вниз.
func _update_lights(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye: Vector3 = camera.global_position if camera else (_player.global_position if _player else Vector3.ZERO)
	var ranked: Array = []
	for drone: Drone in drones:
		if drone.state == &"broken":
			continue
		var d := -1.0 if drone == _engaged else drone.global_position.distance_to(eye)
		if d <= SPOT_REACH:
			ranked.append([d, drone])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var lit := {}
	for i in mini(SPOT_COUNT, ranked.size()):
		lit[ranked[i][1]] = true
	var chest := Vector3.INF
	if _player and is_instance_valid(_player):
		chest = _player.global_position + Vector3.UP * 1.1
	for drone: Drone in drones:
		var watching := drone == _engaged and (drone.state == &"approach" or drone.state == &"hover")
		drone.aim(delta, lit.has(drone), chest if watching else Vector3.INF)

## Сколько прожекторов SpotLight3D сейчас включено (для проверок и кадров).
func active_spots() -> int:
	var n := 0
	for drone: Drone in drones:
		if drone.spot.visible:
			n += 1
	return n

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
			drone.s = fmod(drone.s + float(loop["speed"]) * (AGITATED_SPEED if agitated else 1.0) * delta, float(loop["total"]))
			drone.position = _loop_point(drone.loop, drone.s) + Vector3.UP * _patrol_height(drone)
			if watcher and _engaged == null and drone.ignore_left <= 0.0 and _flat(drone.position).distance_to(_flat(watcher.global_position)) < engage_distance():
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

## POLISH-03 B: включить или снять «активный» режим роя (RoadClosure, пока улица Б перекрыта).
func set_agitated(on: bool) -> void:
	agitated = on

## Дальность, с которой дрон замечает Илюшу: в «активном» режиме — AGITATED_ENGAGE.
func engage_distance() -> float:
	return AGITATED_ENGAGE if agitated else ENGAGE_DISTANCE

## Точка зависания остаётся перед Илюшей в пределах его удара. Боковую точку выбираем по настоящей камере:
## радиусы силуэтов приводятся к глубине героя, поэтому камера спереди/сбоку тоже не получает дрон на линии лица.
## Объём колец не должен заходить в стену или машину; их проверяет сфера, а не только луч до центра.
func hover_point(watcher: Node3D) -> Vector3:
	var look: Node3D = watcher.get("visual") if watcher.get("visual") is Node3D else watcher
	var forward := -look.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	var base := watcher.global_position
	var from := base + Vector3.UP * HOVER_HEIGHT
	var camera := get_viewport().get_camera_3d()
	var target := _hover_clear_point(from, from + forward * HOVER_DISTANCE + right * HOVER_SIDE, watcher)
	var margin := _hover_view_margin(target, watcher, camera)
	if margin >= VIEW_CLEARANCE:
		return target
	for side: float in [HOVER_SIDE_MAX, -HOVER_SIDE, -HOVER_SIDE_MAX]:
		var candidate := _hover_clear_point(from, from + forward * HOVER_DISTANCE + right * side, watcher)
		var candidate_margin := _hover_view_margin(candidate, watcher, camera)
		if candidate_margin > margin:
			target = candidate
			margin = candidate_margin
	return target

func _hover_clear_point(from: Vector3, target: Vector3, watcher: Node3D) -> Vector3:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _hover_shape
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = target - from
	query.collision_mask = 1 | 4
	if watcher is CollisionObject3D:
		query.exclude = [(watcher as CollisionObject3D).get_rid()]
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	return from.lerp(target, fractions[0])

## Положительное значение — просвет между горизонтальными проекциями дрона и фигуры. Дрон за камерой
## не мешает кадру; очень близкий к камере получает худшую оценку. Высота не используется как способ скрыть дрон.
func _hover_view_margin(target: Vector3, watcher: Node3D, camera: Camera3D) -> float:
	if camera == null:
		return INF
	var to_player := _flat(watcher.global_position - camera.global_position)
	var distance := to_player.length()
	if distance < 0.1:
		return 0.0
	var direction := to_player / distance
	var to_drone := _flat(target - camera.global_position)
	var depth := to_drone.dot(direction)
	if depth <= 0.0:
		return INF
	var side := absf(to_drone.dot(direction.cross(Vector3.UP)))
	return (side - VIEW_DRONE_RADIUS) * distance / maxf(depth, 0.1) - VIEW_PLAYER_RADIUS

func _leave(drone: Drone) -> void:
	if _engaged == drone:
		_engaged = null
	drone.state = &"leave"
	drone.timer = 0.0
	drone.ignore_left = AGITATED_IGNORE if agitated else IGNORE_SECONDS
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
	drone.respawn_left = _rng.randf_range(RESPAWN.x, RESPAWN.y) * (AGITATED_RESPAWN if agitated else 1.0)
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

## Ореол мигалки (PUNCH-02): спрайт лицом к камере, складывается со сценой — по образцу shaders/lamp_halo (CITY-01 L),
## но цвет и яркость — свои у каждого дрона (instance uniform), не MultiMesh. Сдвинут от камеры за дрон (near_push):
## оранжевый корпус не заливается красным и синим, свечение — ореолом вокруг силуэта; вблизи камеры (ближе 3,5–9 м) гаснет — там дрон крупный и читается сам.
const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
instance uniform vec3 tint = vec3(1.0);
instance uniform float power = 1.0;
uniform float energy = 1.1;
uniform float core = 22.0;
uniform float wide = 3.5;
uniform float wide_share = 0.22;
uniform float near_fade = 3.5;    // м: ближе дрон крупный и читается сам — ореол не заливает корпус
uniform float near_push = -0.35;  // м: за дроном — корпус закрывает ядро и не окрашивается, свечение вокруг силуэта
varying float fade;
void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float dist = length(center);
	center -= normalize(center) * min(near_push, dist * 0.5);
	VERTEX = center + VERTEX * size;
	NORMAL = vec3(0.0, 0.0, 1.0);
	fade = smoothstep(near_fade, near_fade * 2.5, dist);   // 3,5 → 8,75 м
}
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	float glow = exp(-r2 * core) + wide_share * exp(-r2 * wide);
	glow *= 1.0 - smoothstep(0.75, 1.0, sqrt(r2));
	ALBEDO = tint * glow * energy * power * fade;
}
"""
## Конус луча прожектора: слабое свечение, к краям конуса и к земле гаснет. Ось меша — Y, вершина (у лампы) — y = +0,5.
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
instance uniform float power = 1.0;
uniform vec3 color = vec3(0.85, 0.92, 1.0);
uniform float energy = 0.08;
varying float along;
void vertex() {
	along = clamp(VERTEX.y + 0.5, 0.0, 1.0);
}
void fragment() {
	float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = color * energy * power * pow(edge, 1.5) * (0.25 + 0.75 * along);
}
"""
const BEACON_RED := Vector3(1.0, 0.12, 0.08)
const BEACON_BLUE := Vector3(0.22, 0.42, 1.0)

## Дрон ГСУМ (PUNCH-02), размеры модели до ×DRONE_SCALE: корпус 0,12 × 0,05 × 0,21 м, оранжевый с двумя чёрными полосами
## у кормы; лучи крестом к четырём винтам в светящихся ободах-«стаканах» (размах 0,38 м); подвес камеры под носом; мигалка
## красный/синий на крышке и антенна у кормы; «ГСУМ» — на крышке (Label3D, читается спереди: при осмотре нос
## опущен к Илюше) и на бортах (TextMesh). Прожектор, конус луча, ореол и пятно на снегу — вне облика (без наклона).
## Перед — −Z. Ноль тел; только Area3D попадания.
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
	var halo: MeshInstance3D
	var spot: SpotLight3D
	var beam: MeshInstance3D
	var pool: Decal
	var red_on := false
	var blue_on := false
	var _parts: Dictionary
	var _red: MeshInstance3D
	var _blue: MeshInstance3D
	var _pivot: Node3D
	var _beam_arm: Node3D
	var _beam_dir := Vector3.DOWN
	var _beam_length := 2.0

	static func shared_parts() -> Dictionary:
		var body := BoxMesh.new()
		body.size = Vector3(0.12, 0.05, 0.21)
		var stripe := BoxMesh.new()
		stripe.size = Vector3(0.124, 0.054, 0.022)
		var arm := BoxMesh.new()
		arm.size = Vector3(0.02, 0.014, 2.0 * Vector2(0.12, 0.11).length())
		var motor := CylinderMesh.new()
		motor.top_radius = 0.016
		motor.bottom_radius = 0.018
		motor.height = 0.03
		motor.radial_segments = 8
		# Защита винта — светящийся обод-«стакан» (как у E010): с ребра камеры читается полосой, сверху — кольцом.
		var ring := CylinderMesh.new()
		ring.top_radius = 0.068
		ring.bottom_radius = 0.066
		ring.height = 0.026
		ring.radial_segments = 20
		ring.rings = 1
		ring.cap_top = false
		ring.cap_bottom = false
		var ring_glow := StandardMaterial3D.new()
		ring_glow.albedo_color = Color(0.82, 0.93, 1.0)
		ring_glow.roughness = 0.3
		ring_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring_glow.emission_enabled = true
		ring_glow.emission = Color(0.55, 0.82, 1.0)
		ring_glow.emission_energy_multiplier = 1.4
		var disc := CylinderMesh.new()
		disc.top_radius = 0.054
		disc.bottom_radius = 0.054
		disc.height = 0.002
		disc.radial_segments = 16
		var gimbal := SphereMesh.new()
		gimbal.radius = 0.02
		gimbal.height = 0.036
		gimbal.radial_segments = 10
		gimbal.rings = 5
		var lens := SphereMesh.new()
		lens.radius = 0.01
		lens.height = 0.02
		lens.radial_segments = 8
		lens.rings = 4
		var beacon := BoxMesh.new()
		beacon.size = Vector3(0.034, 0.014, 0.02)
		var antenna := CylinderMesh.new()
		antenna.top_radius = 0.0022
		antenna.bottom_radius = 0.003
		antenna.height = 0.085
		antenna.radial_segments = 4
		var mark := TextMesh.new()
		mark.text = "ГСУМ"
		mark.font_size = 16
		mark.pixel_size = 0.0027
		mark.depth = 0.0
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var halo_shader := Shader.new()
		halo_shader.code = HALO_SHADER
		var halo_mat := ShaderMaterial.new()
		halo_mat.shader = halo_shader
		var cone := CylinderMesh.new()
		cone.top_radius = 0.012
		cone.bottom_radius = tan(deg_to_rad(SPOT_ANGLE))
		cone.height = 1.0
		cone.radial_segments = 16
		cone.rings = 1
		cone.cap_top = false
		cone.cap_bottom = false
		var beam_shader := Shader.new()
		beam_shader.code = BEAM_SHADER
		var beam_mat := ShaderMaterial.new()
		beam_mat.shader = beam_shader
		var pool_tex := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(0.45, Color(0.55, 0.55, 0.55, 0.55))
		pool_tex.gradient = g
		pool_tex.fill = GradientTexture2D.FILL_RADIAL
		pool_tex.fill_from = Vector2(0.5, 0.5)
		pool_tex.fill_to = Vector2(1.0, 0.5)
		pool_tex.width = 64
		pool_tex.height = 64
		var blur := StandardMaterial3D.new()
		blur.albedo_color = Color(0.80, 0.82, 0.86, 0.16)
		blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blur.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return {
			"body": body, "stripe": stripe, "arm": arm, "motor": motor, "ring": ring, "disc": disc, "gimbal": gimbal,
			"lens": lens, "beacon": beacon, "antenna": antenna, "mark": mark, "quad": quad, "cone": cone,
			"halo_mat": halo_mat, "beam_mat": beam_mat, "pool_tex": pool_tex, "blur": blur,
			# Служебная окраска: оранжевый со слабым самосвечением (световозвращающая плёнка ночью), чёрные полосы.
			"orange": Materials.plain(Color(1.0, 0.36, 0.0), 0.45, Color(1.0, 0.33, 0.0), 0.3),
			"black": Materials.plain(Color(0.03, 0.03, 0.04), 0.3),
			"graphite": Materials.plain(Color(0.17, 0.18, 0.20), 0.45),
			"ring_glow": ring_glow,
			"lens_mat": Materials.plain(Color(0.10, 0.18, 0.30), 0.05, Color(0.35, 0.55, 0.9), 0.8),
			"red_on": Materials.plain(Color(1.0, 0.12, 0.06), 0.4, Color(1.0, 0.06, 0.03), 9.0),
			"red_off": Materials.plain(Color(0.32, 0.04, 0.03), 0.4, Color(1.0, 0.06, 0.03), 0.25),
			"blue_on": Materials.plain(Color(0.15, 0.35, 1.0), 0.4, Color(0.10, 0.30, 1.0), 10.0),
			"blue_off": Materials.plain(Color(0.04, 0.08, 0.32), 0.4, Color(0.10, 0.30, 1.0), 0.25),
		}

	func build(parts: Dictionary) -> void:
		_parts = parts
		visual = Node3D.new()
		visual.name = "Visual"
		visual.scale = Vector3.ONE * DRONE_SCALE
		add_child(visual)
		_mesh(visual, parts["body"], Vector3.ZERO, parts["orange"])
		_mesh(visual, parts["stripe"], Vector3(0, 0, 0.045), parts["black"])
		_mesh(visual, parts["stripe"], Vector3(0, 0, 0.08), parts["black"])
		var diag := atan2(0.12, 0.11)
		for k in 2:
			var arm := _mesh(visual, parts["arm"], Vector3(0, 0.004, 0), parts["black"])
			arm.rotation.y = diag if k == 0 else -diag
		for k in 4:
			var sx := 1.0 if k % 2 == 0 else -1.0
			var sz := 1.0 if k < 2 else -1.0
			var hub := Vector3(sx * 0.12, 0.0, sz * 0.11)
			_mesh(visual, parts["motor"], hub + Vector3(0, 0.008, 0), parts["graphite"])
			_mesh(visual, parts["ring"], hub + Vector3(0, 0.016, 0), parts["ring_glow"])
			_mesh(visual, parts["disc"], hub + Vector3(0, 0.026, 0), parts["blur"])
		# Подвес камеры под носом.
		_mesh(visual, parts["gimbal"], Vector3(0, -0.022, -0.078), parts["black"])
		_mesh(visual, parts["lens"], Vector3(0, -0.024, -0.097), parts["lens_mat"])
		# Мигалка на крышке: красный слева, синий справа; антенна у кормы справа.
		_red = _mesh(visual, parts["beacon"], Vector3(-0.019, 0.032, -0.03), parts["red_off"])
		_blue = _mesh(visual, parts["beacon"], Vector3(0.019, 0.032, -0.03), parts["blue_off"])
		_mesh(visual, parts["antenna"], Vector3(0.045, 0.025 + 0.0425, 0.088), parts["black"])
		# «ГСУМ» на бортах (читается слева направо с каждой стороны) и на крышке.
		var right := _mesh(visual, parts["mark"], Vector3(0.0605, -0.002, -0.035), parts["black"])
		right.rotation.y = PI * 0.5
		var left := _mesh(visual, parts["mark"], Vector3(-0.0605, -0.002, -0.035), parts["black"])
		left.rotation.y = -PI * 0.5
		var label := Label3D.new()
		label.name = "Mark"
		label.text = "ГСУМ"
		label.font_size = 40
		label.pixel_size = 0.001
		label.outline_size = 0
		label.modulate = Color(0.02, 0.02, 0.03)
		label.double_sided = false
		label.shaded = false
		label.no_depth_test = false
		# Лицом вверх, верх букв — к корме: читается спереди и сверху (нос опущен к Илюше при осмотре).
		label.transform = Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)), Vector3(0, 0.0258, -0.045))
		visual.add_child(label)
		# Ореол мигалки — над крышкой, вне облика (без наклона и масштаба облика).
		halo = _mesh(self, parts["quad"], Vector3(0, 0.07, -0.05), parts["halo_mat"])
		halo.name = "Halo"
		halo.scale = Vector3.ONE * HALO_SIZE
		halo.set_instance_shader_parameter("power", 0.0)
		# Прожектор в подвесе: луч вниз, при осмотре — на Илюшу.
		_pivot = Node3D.new()
		_pivot.name = "SpotPivot"
		_pivot.position = Vector3(0, -0.045, -0.15)
		add_child(_pivot)
		spot = SpotLight3D.new()
		spot.name = "Spot"
		spot.light_color = Color(0.92, 0.96, 1.0)
		spot.light_energy = SPOT_ENERGY
		spot.spot_range = SPOT_RANGE
		spot.spot_angle = SPOT_ANGLE
		preload("res://game/world/lighting.gd").configure_local_shadow(spot)
		spot.light_specular = 0.25
		spot.light_volumetric_fog_energy = 0.0   # луч рисует конус-меш; объёмный туман от прожектора — лишняя цена кадра
		spot.visible = false
		_pivot.add_child(spot)
		_beam_arm = Node3D.new()
		_beam_arm.name = "BeamArm"
		_pivot.add_child(_beam_arm)
		beam = _mesh(_beam_arm, parts["cone"], Vector3(0, 0, -0.5), parts["beam_mat"])
		beam.name = "Beam"
		beam.rotation.x = PI * 0.5
		pool = Decal.new()
		pool.name = "Pool"
		pool.top_level = true
		pool.size = Vector3(POOL_SIZE, 0.8, POOL_SIZE)
		pool.texture_albedo = parts["pool_tex"]
		pool.texture_emission = parts["pool_tex"]
		pool.albedo_mix = 0.25
		pool.emission_energy = 1.4
		pool.modulate = Color(0.85, 0.92, 1.0)
		add_child(pool)
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

	## Покачивание, наклон по скорости, мигалка: красный дважды, синий дважды за BEACON_PERIOD (при подлёте и осмотре —
	## чаще), ореол — цветом горящей половины.
	func animate(_delta: float, speed: float) -> void:
		var watching := state == &"hover" or state == &"approach"
		var t := timer + phase
		var lean := clampf(speed * LEAN_PER_SPEED, 0.0, LEAN_MAX)
		visual.rotation.x = -lean + 0.03 * sin(t * 2.3) - (WATCH_TILT if state == &"hover" else 0.0)
		visual.rotation.z = 0.05 * sin(t * 1.7 + 0.4) + (0.18 * sin(t * 2.6) if state == &"hover" else 0.0)
		visual.position.y = 0.01 * sin(t * 4.1)
		var u := fmod(t / (BEACON_PERIOD_WATCH if watching else BEACON_PERIOD), 1.0)
		var red := u < 0.1 or (u > 0.17 and u < 0.27)
		var blue := (u > 0.5 and u < 0.6) or (u > 0.67 and u < 0.77)
		if red != red_on:
			red_on = red
			_red.material_override = _parts["red_on"] if red else _parts["red_off"]
		if blue != blue_on:
			blue_on = blue
			_blue.material_override = _parts["blue_on"] if blue else _parts["blue_off"]
		halo.set_instance_shader_parameter("tint", BEACON_RED if red else BEACON_BLUE)
		halo.set_instance_shader_parameter("power", 1.0 if red or blue else 0.1)

	## Прожектор: spot_on — SpotLight3D включён (иначе пятно-декаль на снегу); target — точка, куда светить (Илюша),
	## Vector3.INF — вниз. Луч доворачивается плавно.
	func aim(delta: float, spot_on: bool, target: Vector3) -> void:
		var want := Vector3.DOWN
		var length := maxf(_pivot.global_position.y, 0.3)
		var watching := target != Vector3.INF
		if watching:
			var to := target - _pivot.global_position
			if to.length() > 0.2:
				want = to.normalized()
				length = clampf(to.length(), 0.5, 5.0)
		var k := clampf(6.0 * delta, 0.0, 1.0)
		var mixed := _beam_dir.lerp(want, k)
		_beam_dir = mixed.normalized() if mixed.length_squared() > 0.0001 else want
		_beam_length = lerpf(_beam_length, length, k)
		var up := Vector3.FORWARD if absf(_beam_dir.y) > 0.98 else Vector3.UP
		_pivot.global_basis = Basis.looking_at(_beam_dir, up)
		_beam_arm.scale = Vector3.ONE * _beam_length
		beam.set_instance_shader_parameter("power", (1.8 if watching else 1.0) * (1.0 if spot_on else 0.6))
		spot.visible = spot_on
		pool.visible = not spot_on
		pool.global_position = Vector3(global_position.x, 0.2, global_position.z)

	func set_alive(on: bool) -> void:
		visible = on
		hit_area.monitorable = on
		(hit_area.get_child(0) as CollisionShape3D).disabled = not on
		if not on:
			spot.visible = false
		if on:
			visual.scale = Vector3.ONE * DRONE_SCALE * 0.3
			create_tween().tween_property(visual, "scale", Vector3.ONE * DRONE_SCALE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func is_flying() -> bool:
		return state != &"broken"

	## Обломки: [меш, материал] — корпус, кольца, полоса, луч, мотор.
	func debris_parts() -> Array:
		return [
			[_parts["body"], _parts["orange"]], [_parts["ring"], _parts["ring_glow"]], [_parts["stripe"], _parts["black"]],
			[_parts["ring"], _parts["ring_glow"]], [_parts["arm"], _parts["black"]], [_parts["motor"], _parts["graphite"]],
		]
