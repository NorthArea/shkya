extends Node3D
## Живность и мелочи города Н. (CITY-01, часть A): серые вороны на проводах и валах у A∩B, дворняга за гаражами
## киоска, кошка на подоконнике первого этажа у подъезда, мусор у контейнеров. Всё — простые объёмы в манере
## проекта, без чужих ассетов. Узел создаёт LevelGeometry (ребёнок DemoWorld/LevelGeometry/Ambient, после Residents);
## мир ищется вверх по дереву.
## Коллизий нет ни у кого, кроме собаки: её тело — AnimatableBody3D на слое Car (4), маска 0, как у жителей
## (PEOPLE-01): Илюша в неё упирается и не толкает, «Лада» (маска World) проходит сквозь, луч наблюдателей и пружина
## камеры (маска 1) её не видят. Собака отходит от «Лады», а подошедшему вплотную Илюше даёт себя погладить.
## Звук — SoundDirector: слушает сигналы crow_cawed / dog_barked (только слушает, ничем не управляет).
## Без случайностей вне seed: расписания лая и карканья — RandomNumberGenerator с фиксированным SEED.
## PEOPLE-03 (P2): голуби (конёк голубятни Z6, снег у неё, мусор у контейнеров двора) и синицы у кормушки Z2 — тот же
## класс птицы (Crow, вид species), свои стайки: Илюша пешком или «Лада» ближе своего радиуса — взлетает вся стайка,
## кружит над местом и садится обратно, когда рядом никого. Голуби на снегу клюют. Сигналы для SoundDirector:
## pigeon_cooed (воркование сидящего голубя по расписанию) и birds_flushed (хлопанье крыльев стайки при взлёте).

const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")

signal crow_cawed(crow: Node3D)
signal dog_barked(dog: Node3D)
signal dog_petted(actor: Node)
signal pigeon_cooed(bird: Node3D)
signal birds_flushed(bird: Node3D)

const GROUP := &"ambient"
const SEED := 2910

# --- вороны ---
## Насесты: поперечина контактной сети улицы A на x = 54 (SPAN_Y 7,85, провис 0,35 между z 22 и 42), контактный
## провод A (z 30,5, высота 7,0, провис 0,22 между опорами x 54 и 78), контактный провод B (x 68,5, от z 25 к 10)
## и валы снега (верх 0,9 м): южный вал A и западный вал B. Высота на проводе — по параболе провиса + 0,02 м
## (y = верх − 4·провис·k·(1 − k)). На поперечине — не ближе 1,6 м к светильнику фонаря (54, 23,8): иначе ворона в его ореоле.
const CROW_PERCHES: Array[Vector3] = [
	Vector3(54.0, 7.67, 23.9), Vector3(54.0, 7.63, 26.4), Vector3(54.0, 7.70, 39.2),   # первая — из ореола фонаря (проверка CITY-01)
	Vector3(59.0, 6.875, 30.5), Vector3(60.1, 6.853, 30.5),
	Vector3(68.5, 6.80, 17.0), Vector3(68.5, 6.80, 15.8),
	Vector3(57.5, 0.92, 39.6), Vector3(63.4, 0.92, 8.0),
]
## Поворот вороны на насесте (на проводе — поперёк провода, клювом на улицу).
const CROW_YAWS: Array[float] = [PI * 0.5, -PI * 0.5, PI * 0.5, 0.0, PI, PI * 0.5, -PI * 0.5, 0.3, -PI * 0.5]
const CROW_SCALE := 1.3
const FLUSH_DISTANCE := 6.0     # м по горизонтали от насеста: машина или Илюша ближе — взлёт
const CALM_DISTANCE := 8.0      # м: возвращаться, только когда рядом с насестом никого
const FLY_MIN := 5.0            # с в воздухе не меньше
const CIRCLE_SPEED := 1.1       # рад/с
const RETURN_SPEED := 5.0       # м/с
const CAW_GAP := 0.5            # с: не чаще одного «кар» за полсекунды на всю стаю
const IDLE_CAW := Vector2(7.0, 16.0)

# --- PEOPLE-03 (P2): голуби и синицы ---
## Голуби: стайки [насесты]. Конёк голубятни (Layout PropDovecote (88; 110), конёк на высоте 4,65 вдоль x, z 110,2);
## на снегу перед ней; у контейнеров двора (BINS, z 64,9…66,1) — среди мусора LITTER, южнее.
const PIGEON_FLOCKS: Array = [
	[Vector3(87.0, 4.7, 110.2), Vector3(87.7, 4.7, 110.2), Vector3(88.9, 4.7, 110.2)],
	[Vector3(85.6, 0.0, 107.4), Vector3(86.6, 0.0, 106.9), Vector3(90.4, 0.0, 107.5)],
	[Vector3(-34.8, 0.0, 67.9), Vector3(-32.9, 0.0, 68.3), Vector3(-30.7, 0.0, 67.8)],
]
## Синицы у кормушки Z2 (Props.FEEDER_BIRCH (−66; 98): пакет на берёзе, крыша 1,87): на крыше, у окошка и на верёвке
## с бельём рядом.
const TIT_FLOCKS: Array = [[Vector3(-65.75, 1.87, 98.0), Vector3(-65.75, 1.62, 98.1), Vector3(-66.4, 1.99, 98.4)]]
const PIGEON_FLUSH := 5.0       # м по горизонтали: ближе — взлёт стайки
const TIT_FLUSH := 4.0
const BIRD_CALM := 8.0          # м: садятся, только когда рядом с местом никого
const COO_INTERVAL := Vector2(6.0, 14.0)
const WINGS_GAP := 0.5          # с: не чаще одного хлопанья крыльев на всех

# --- собака ---
## Петля за гаражами киоска (западная стена Garages_Kiosk — x = 42, тополя (36, −68) и (36, −82)); до дорог и
## тротуаров (улица C, z ≤ −89) — больше 2 м, со стелс-проходом у гаражей (x 50…53) не пересекается.
const DOG_LOOP: Array[Vector3] = [Vector3(40.6, 0, -84.0), Vector3(40.6, 0, -67.0), Vector3(38.6, 0, -66.0), Vector3(38.4, 0, -80.0)]
const DOG_PAUSE_POINTS: Array[int] = [0, 2]
const DOG_PAUSE := 3.0
const DOG_AREA := Rect2(37.4, -87.0, 4.0, 23.0)   # x 37,4…41,4, z −87…−64: собака из неё не выходит
const DOG_SPEED := 1.1
const DOG_FLEE_SPEED := 2.4
const DOG_FLEE_DISTANCE := 4.0  # м до Илюши (до «Лады» — +1 м): отходит
const DOG_CALM_DISTANCE := 6.0
const DOG_KEEP := 1.2           # м: ближе к Илюше собака не шагает
const DOG_GREETING_RANGE := 2.6 # подошёл достаточно близко — ждёт прикосновения, не убегает
const DOG_PET_REACH := 2.25
const DOG_PET_SECONDS := 2.4
const BARK_INTERVAL := Vector2(20.0, 40.0)
const DOG_BODY := Vector3(0.36, 0.7, 0.95)

# --- кошка и мусор ---
## Подоконник окна первого этажа H1 (северный фасад z = 108, окно x −32,2…−30,8 по сетке facade.gdshader: шаг 3,
## ширина 1,4, низ проёма 0,85), восточнее лавки у подъезда.
const CAT_SILL := Vector3(-31.5, 0.85, 107.9)
## Мусор у контейнеров: [x, z, поворот, вид]. Двор (BINS, проезд южнее), H10 (H10_BINS, крышками во двор, южнее),
## киоск (KIOSK_BINS) — за краем бетонной площадки (шире коробки на 0,4 м). Газета, картонка и мешки без коллизий,
## по высоте ниже 0,2 м.
const LITTER: Array = [
	[-34.2, 67.0, 0.4, &"paper"], [-31.6, 66.9, 1.2, &"sack"], [-29.8, 67.5, 2.1, &"paper"],
	[-31.2, -70.9, 0.8, &"paper"], [-28.6, -70.8, 2.6, &"sack"],
	[55.9, -61.2, 1.7, &"paper"], [54.5, -64.3, 0.3, &"sack"],   # у KIOSK_BINS: fix5 — +2,5 м к востоку вместе с контейнерами
]

var crows: Array = []
var dog: Node3D
var dog_body: AnimatableBody3D
var dog_state: StringName = &"walk"   # walk, pause, flee, return, greet, pet
var dog_interactable: Interactable
var dog_pets := 0
var _dog_pet_left := 0.0
var dog_target := 1
var dog_barks := 0
var dog_bark_times: Array[float] = []
var cat: Node3D
var litter: Array = []
var flushes := {&"player": 0, &"car": 0, &"traffic": 0}
var clock := 0.0
var pigeons: Array = []          # PEOPLE-03: голуби (Crow, species &"pigeon")
var tits: Array = []             # синицы
var flocks: Array = []           # [птицы, радиус взлёта]
var bird_flushes := {&"pigeon": 0, &"tit": 0}
var coos := 0
var _next_coo := 0.0
var _wings_cooldown := 0.0

var _rng := RandomNumberGenerator.new()
var _world: Node
var _player: Node3D
var _lada: Node3D
var _caw_cooldown := 0.0
var _next_idle_caw := 0.0
var _next_bark := 0.0
var _dog_wait := 0.0
var _dog_legs: Array[Node3D] = []
var _dog_head: Node3D
var _dog_tail: Node3D
var _dog_walk_phase := 0.0
var _cat_head: Node3D
var _cat_tail: Node3D

func _init() -> void:
	name = "Ambient"

func _ready() -> void:
	add_to_group(GROUP)
	_rng.seed = SEED
	_world = _find_world()
	if _world:
		_player = _world.get_node_or_null("Ilyusha")
		_lada = _world.get_node_or_null("Car")
	for i in CROW_PERCHES.size():
		var crow := Crow.new()
		crow.name = "Crow%d" % i
		crow.perch = CROW_PERCHES[i]
		crow.perch_yaw = CROW_YAWS[i]
		crow.phase = float(i) * 1.7
		crow.circle_dir = 1.0 if i % 2 == 0 else -1.0
		crow.rise = 4.0 + float(i % 3)
		crow.radius = 4.0 + float(i % 2) * 1.5
		add_child(crow)
		crow.build(CROW_SCALE)
		crow.land()
		crows.append(crow)
	_build_dog()
	_build_cat()
	_build_litter()
	_build_small_birds()
	_next_idle_caw = _rng.randf_range(IDLE_CAW.x, IDLE_CAW.y)
	_next_bark = _rng.randf_range(BARK_INTERVAL.x, BARK_INTERVAL.y)
	var rig: Node = _world.get_node_or_null("CameraRig") if _world else null
	if rig and rig.has_method("exclude_permanently"):
		rig.call_deferred("exclude_permanently", dog_body.get_rid())   # CameraRig готовится позже LevelGeometry

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
	var threats := _threats()
	_update_crows(delta, threats)
	_update_small_birds(delta, threats)
	_update_dog(delta)
	_update_cat()

## Кто пугает: [позиция XZ, вид]. Илюша — только пешком (в машине его место — «Лада»).
func _threats() -> Array:
	var out := []
	if _player and is_instance_valid(_player) and _player.visible and (_world == null or _world.get("control_mode") != &"in_car"):
		out.append([_flat(_player.global_position), &"player"])
	if _lada and is_instance_valid(_lada):
		out.append([_flat(_lada.global_position), &"car"])
	for vehicle in get_tree().get_nodes_in_group(&"traffic_vehicles"):
		out.append([_flat((vehicle as Node3D).global_position), &"traffic"])
	return out

static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)

## Ближайшая угроза к точке: [расстояние, вид].
static func _nearest(point: Vector3, threats: Array) -> Array:
	var best := INF
	var kind: StringName = &""
	var p := _flat(point)
	for t in threats:
		var d: float = p.distance_to(t[0])
		if d < best:
			best = d
			kind = t[1]
	return [best, kind]

# --- вороны ---

func _update_crows(delta: float, threats: Array) -> void:
	_caw_cooldown = maxf(_caw_cooldown - delta, 0.0)
	for crow: Crow in crows:
		var near := _nearest(crow.perch, threats)
		var d: float = near[0]
		match crow.state:
			&"sit":
				if d < FLUSH_DISTANCE:
					crow.take_off()
					flushes[near[1]] = int(flushes.get(near[1], 0)) + 1
					_caw(crow)
			&"fly":
				if crow.timer >= FLY_MIN and d >= CALM_DISTANCE:
					crow.state = &"return"
			&"return":
				if d < FLUSH_DISTANCE:
					crow.state = &"fly"
		crow.step(delta)
	if clock >= _next_idle_caw:
		_next_idle_caw = clock + _rng.randf_range(IDLE_CAW.x, IDLE_CAW.y)
		var sitting := crows.filter(func(c: Crow) -> bool: return c.state == &"sit")
		if not sitting.is_empty():
			_caw(sitting[_rng.randi() % sitting.size()])

func _caw(crow: Crow) -> void:
	if _caw_cooldown > 0.0:
		return
	_caw_cooldown = CAW_GAP
	crow.caws += 1
	crow_cawed.emit(crow)

# --- PEOPLE-03 (P2): голуби и синицы ---

func _build_small_birds() -> void:
	var n := 0
	for flock_spec in PIGEON_FLOCKS + TIT_FLOCKS:
		var pigeon: bool = PIGEON_FLOCKS.has(flock_spec)
		var flock := []
		for perch: Vector3 in flock_spec:
			var bird := Crow.new()
			bird.species = &"pigeon" if pigeon else &"tit"
			bird.name = "%s%d" % ["Pigeon" if pigeon else "Tit", n]
			bird.perch = perch
			bird.perch_yaw = float(n) * 2.1
			bird.phase = float(n) * 1.3
			bird.circle_dir = 1.0 if n % 2 == 0 else -1.0
			bird.rise = (5.0 + float(n % 3)) if pigeon else (2.2 + 0.4 * float(n % 2))
			bird.radius = (4.5 + float(n % 2)) if pigeon else 1.6
			add_child(bird)
			bird.build(1.0 if pigeon else 0.45)
			bird.land()
			(pigeons if pigeon else tits).append(bird)
			flock.append(bird)
			n += 1
		flocks.append([flock, PIGEON_FLUSH if pigeon else TIT_FLUSH])
	_next_coo = _rng.randf_range(COO_INTERVAL.x, COO_INTERVAL.y)

## Стайка взлетает целиком, когда угроза ближе её радиуса к любому насесту; садится каждая, когда рядом никого.
func _update_small_birds(delta: float, threats: Array) -> void:
	_wings_cooldown = maxf(_wings_cooldown - delta, 0.0)
	for f in flocks:
		var flock: Array = f[0]
		var near := INF
		for bird: Crow in flock:
			near = minf(near, _nearest(bird.perch, _bird_threats(threats))[0])
		if near < f[1] and flock.any(func(b: Crow) -> bool: return b.state == &"sit"):
			for bird: Crow in flock:
				if bird.state == &"sit":
					bird.take_off()
			bird_flushes[flock[0].species] = int(bird_flushes[flock[0].species]) + 1
			if _wings_cooldown <= 0.0:
				_wings_cooldown = WINGS_GAP
				birds_flushed.emit(flock[0])
		for bird: Crow in flock:
			match bird.state:
				&"fly":
					if bird.timer >= FLY_MIN and near >= BIRD_CALM:
						bird.state = &"return"
				&"return":
					if near < f[1]:
						bird.state = &"fly"
			bird.step(delta)
	if clock >= _next_coo:
		_next_coo = clock + _rng.randf_range(COO_INTERVAL.x, COO_INTERVAL.y)
		var sitting := pigeons.filter(func(b: Crow) -> bool: return b.state == &"sit")
		if not sitting.is_empty():
			coos += 1
			pigeon_cooed.emit(sitting[_rng.randi() % sitting.size()])

## Птиц у двора пугают только Илюша пешком и «Лада», не транспорт кольца (он далеко от их мест).
static func _bird_threats(threats: Array) -> Array:
	return threats.filter(func(t) -> bool: return t[1] != &"traffic")

## Птица (CITY-01: серая ворона; PEOPLE-03: голубь, синица — species). Ноль коллизий. Перед — −Z, начало — у лап.
## Ворона: серое туловище, чёрные голова, крылья и хвост. Голубь: сизый, тёмная голова, переливчатая шея, полосы на
## крыльях; на снегу клюёт. Синица: жёлтое брюшко, чёрная голова, белые щёки, зеленоватая спина.
class Crow extends Node3D:
	var species := &"crow"
	var perch := Vector3.ZERO
	var perch_yaw := 0.0
	var phase := 0.0
	var circle_dir := 1.0
	var rise := 5.0
	var radius := 4.0
	var state: StringName = &"sit"   # sit, fly, return
	var timer := 0.0
	var caws := 0
	var flights := 0
	## Сколько секунд длился последний полёт (взлёт → посадка).
	var last_flight := 0.0
	var _airborne := 0.0
	var _angle := 0.0
	var _wings: Array[Node3D] = []
	var _folded: Array[Node3D] = []
	var _head: Node3D
	var _last := Vector3.ZERO

	func build(scale_k: float) -> void:
		var black := Materials.plain(Color(0.05, 0.05, 0.06), 0.55)
		var grey := Materials.plain(Color(0.46, 0.46, 0.47), 0.8)
		var head_mat := black
		var wing_mat := black
		var tail_mat := black
		var beak_mat := black
		var neck_mat: Material = null
		match species:
			&"pigeon":
				grey = Materials.plain(Color(0.56, 0.59, 0.66), 0.8)
				head_mat = Materials.plain(Color(0.38, 0.40, 0.48), 0.8)
				wing_mat = Materials.plain(Color(0.50, 0.53, 0.60), 0.8)
				tail_mat = Materials.plain(Color(0.30, 0.31, 0.36), 0.8)
				beak_mat = Materials.plain(Color(0.85, 0.66, 0.62), 0.6)
				neck_mat = Materials.plain(Color(0.30, 0.50, 0.44), 0.4)
			&"tit":
				grey = Materials.plain(Color(0.95, 0.82, 0.18), 0.8)
				wing_mat = Materials.plain(Color(0.40, 0.50, 0.55), 0.8)
				tail_mat = wing_mat
				neck_mat = Materials.plain(Color(0.96, 0.96, 0.94), 0.8)   # белые щёки
		var root := Node3D.new()
		root.name = "Visual"
		root.scale = Vector3.ONE * scale_k
		add_child(root)
		var body := _mesh(root, _sphere(0.12), Vector3(0, 0.17, 0.0), grey)
		body.scale = Vector3(0.8, 0.85, 1.6)
		_head = Node3D.new()
		_head.position = Vector3(0, 0.27, -0.15)
		root.add_child(_head)
		_mesh(_head, _sphere(0.075), Vector3.ZERO, head_mat)
		if neck_mat:
			var neck := _mesh(_head, _sphere(0.07), Vector3(0, -0.06, 0.02), neck_mat)
			neck.scale = Vector3(1.05, 0.8, 0.9)
		var beak := CylinderMesh.new()
		beak.top_radius = 0.0
		beak.bottom_radius = 0.026
		beak.height = 0.09
		beak.radial_segments = 6
		var b := _mesh(_head, beak, Vector3(0, -0.01, -0.1), beak_mat)
		b.rotation.x = -PI * 0.5
		if species != &"crow":
			b.scale = Vector3(0.6, 0.6, 0.6)
		var tail := _mesh(root, _box(Vector3(0.1, 0.02, 0.18)), Vector3(0, 0.14, 0.24), tail_mat)
		tail.rotation.x = 0.25
		for x: float in [-1.0, 1.0]:
			var folded := _mesh(root, _sphere(0.12), Vector3(x * 0.075, 0.19, 0.05), wing_mat)
			folded.scale = Vector3(0.22, 0.42, 1.2)
			folded.rotation.x = 0.12
			_folded.append(folded)
			var pivot := Node3D.new()
			pivot.position = Vector3(x * 0.07, 0.21, -0.02)
			root.add_child(pivot)
			_mesh(pivot, _box(Vector3(0.32, 0.015, 0.17)), Vector3(x * 0.16, 0, 0), wing_mat)
			pivot.visible = false
			_wings.append(pivot)
			_mesh(root, _box(Vector3(0.012, 0.09, 0.012)), Vector3(x * 0.03, 0.045, 0.0), black)

	func _sphere(r: float) -> SphereMesh:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 10
		m.rings = 6
		return m

	func _box(size: Vector3) -> BoxMesh:
		var m := BoxMesh.new()
		m.size = size
		return m

	func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = material
		mi.position = at
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		return mi

	## Сесть на насест (старт и конец возврата).
	func land() -> void:
		if state != &"sit":
			last_flight = _airborne
		state = &"sit"
		timer = 0.0
		position = perch
		rotation = Vector3(0, perch_yaw, 0)
		_set_flying(false)
		_last = position

	func take_off() -> void:
		state = &"fly"
		timer = 0.0
		flights += 1
		_airborne = 0.0
		_angle = phase
		_set_flying(true)

	func _set_flying(on: bool) -> void:
		for w in _wings:
			w.visible = on
		for f in _folded:
			f.visible = not on

	## Точка на круге над насестом.
	func circle_point() -> Vector3:
		return perch + Vector3(cos(_angle) * radius, rise + 0.4 * sin(_angle * 2.0), sin(_angle) * radius)

	func step(delta: float) -> void:
		timer += delta
		match state:
			&"sit":
				# Голова изредка поворачивается — ворона «смотрит» по сторонам.
				_head.rotation.y = 0.5 * sin(timer * 0.7 + phase) * float(sin(timer * 0.23 + phase) > 0.3)
				if species == &"pigeon" and perch.y < 0.1:
					var k := fmod(timer + phase, 1.3)   # клюёт: голова к снегу
					_head.rotation.x = -0.9 * sin(clampf(k / 0.35, 0.0, 1.0) * PI)
				return
			&"fly":
				_airborne += delta
				_angle += CIRCLE_SPEED * circle_dir * delta
				var target := circle_point()
				var k := clampf(timer / 1.2, 0.0, 1.0)
				position = position.lerp(target, clampf(delta * (2.0 + 6.0 * k), 0.0, 1.0)) if k < 1.0 else target
			&"return":
				_airborne += delta
				var to := perch - position
				var dist := to.length()
				var stride := RETURN_SPEED * delta
				if dist <= stride:
					land()
					return
				position += to / dist * stride
		_flap()
		var moved := position - _last
		if Vector2(moved.x, moved.z).length() > 0.0005:
			rotation.y = atan2(-moved.x, -moved.z)
		_last = position

	func _flap() -> void:
		var a := sin(timer * TAU * (14.0 if species == &"tit" else 6.0)) * 0.8
		_wings[0].rotation.z = -a
		_wings[1].rotation.z = a


# --- собака ---

func _build_dog() -> void:
	dog = Node3D.new()
	dog.name = "Dog"
	add_child(dog)
	dog.position = DOG_LOOP[0]
	var fur := Materials.plain(Color(0.78, 0.55, 0.30), 0.9)
	var dark := Materials.plain(Color(0.40, 0.26, 0.14), 0.9)
	var light := Materials.plain(Color(0.93, 0.87, 0.74), 0.9)
	var nose := Materials.plain(Color(0.04, 0.04, 0.04), 0.4)
	var body := CapsuleMesh.new()
	body.radius = 0.15
	body.height = 0.72
	body.radial_segments = 10
	body.rings = 4
	var torso := _part(dog, body, Vector3(0, 0.44, 0.0), fur)
	torso.rotation.x = PI * 0.5
	_part(dog, _box(Vector3(0.2, 0.16, 0.2)), Vector3(0, 0.38, -0.24), light)   # светлая грудь
	_dog_head = Node3D.new()
	_dog_head.position = Vector3(0, 0.6, -0.38)
	dog.add_child(_dog_head)
	_part(_dog_head, _box(Vector3(0.2, 0.19, 0.22)), Vector3.ZERO, fur)
	_part(_dog_head, _box(Vector3(0.12, 0.1, 0.15)), Vector3(0, -0.04, -0.17), light)
	_part(_dog_head, _box(Vector3(0.05, 0.04, 0.03)), Vector3(0, -0.0, -0.255), nose)
	for x: float in [-1.0, 1.0]:
		var ear := _part(_dog_head, _box(Vector3(0.05, 0.12, 0.07)), Vector3(x * 0.1, 0.06, 0.03), dark)
		ear.rotation.z = x * 0.35
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var hip := Node3D.new()
		hip.position = Vector3(corner.x * 0.085, 0.34, corner.y * 0.25)
		dog.add_child(hip)
		_part(hip, _box(Vector3(0.07, 0.34, 0.07)), Vector3(0, -0.17, 0), fur if corner.y > 0 else light)
		_dog_legs.append(hip)
	_dog_tail = Node3D.new()
	_dog_tail.position = Vector3(0, 0.5, 0.38)
	_dog_tail.rotation.x = 0.7
	dog.add_child(_dog_tail)
	_part(_dog_tail, _box(Vector3(0.05, 0.05, 0.28)), Vector3(0, 0, 0.14), fur)
	dog_body = AnimatableBody3D.new()
	dog_body.name = "Body"
	dog_body.collision_layer = 4   # Car, как у жителей
	dog_body.collision_mask = 0
	dog_body.sync_to_physics = false
	var shape := BoxShape3D.new()
	shape.size = DOG_BODY
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = DOG_BODY.y * 0.5
	dog_body.add_child(collider)
	dog.add_child(dog_body)
	dog_interactable = Interactable.new()
	dog_interactable.name = "PetInteraction"
	dog_interactable.interaction_id = &"dog"
	dog_interactable.prompt = "E — ПОГЛАДИТЬ"
	dog_interactable.radius = 1.8
	dog_interactable.enabled = false
	dog_interactable.interacted.connect(_pet_dog)
	dog.add_child(dog_interactable)
	dog_target = 1
	_face(DOG_LOOP[1] - DOG_LOOP[0])

func _dog_player_ready() -> bool:
	var player := _player as Ilyusha
	if player == null or get_tree().paused:
		return false
	return player.visible and player.input_enabled and player.hide_mode == &"none" and player.can_change_hide_mode()

func _can_pet_dog(actor: Node) -> bool:
	if actor != _player or not _dog_player_ready() or _dog_pet_left > 0.0 or _dog_car_near():
		return false
	var offset := _player.global_position - dog.global_position
	if Vector2(offset.x, offset.z).length() > DOG_PET_REACH or absf(offset.y) > 0.8:
		return false
	var ray := PhysicsRayQueryParameters3D.create(_player.global_position + Vector3.UP * 0.9,
		dog.global_position + Vector3.UP * 0.6, 1 | 4 | 64)
	ray.exclude = [dog_body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _dog_car_near() -> bool:
	return is_instance_valid(_lada) and _flat(dog.global_position).distance_to(_flat(_lada.global_position)) < DOG_FLEE_DISTANCE + 1.0

func _pet_dog(actor: Node) -> void:
	if not _can_pet_dog(actor):
		return
	dog_pets += 1
	dog_state = &"pet"
	_dog_pet_left = DOG_PET_SECONDS
	dog_interactable.enabled = false
	_face(_player.global_position - dog.global_position)
	dog_petted.emit(actor)

func _part(parent: Node3D, mesh: Mesh, at: Vector3, material: Material, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _ball(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m

static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

func _face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.001:
		dog.rotation.y = atan2(-dir.x, -dir.z)

func _update_dog(delta: float) -> void:
	if clock >= _next_bark:
		_next_bark = clock + _rng.randf_range(BARK_INTERVAL.x, BARK_INTERVAL.y)
		dog_barks += 1
		dog_bark_times.append(clock)
		_dog_head.rotation.x = -0.35
		dog_barked.emit(dog)
	_dog_head.rotation.x = move_toward(_dog_head.rotation.x, 0.25 if dog_state == &"pause" else 0.0, delta * 1.5)
	var here := _flat(dog.global_position)
	if _dog_pet_left > 0.0:
		_dog_pet_left = maxf(0.0, _dog_pet_left - delta)
		if not _dog_car_near() and _dog_player_ready() and here.distance_to(_flat(_player.global_position)) <= DOG_PET_REACH + 0.3:
			_dog_head.rotation.x = -0.25 + 0.05 * sin(clock * 8.0)
			_animate_dog(0.0, delta)
			dog_interactable.enabled = false
			return
		_dog_pet_left = 0.0
	if dog_state == &"pet":
		dog_state = &"return"
		dog_target = _nearest_loop_point(here)
	var player_d := INF
	var flee_from := Vector3.INF
	if _player and is_instance_valid(_player) and (_world == null or _world.get("control_mode") != &"in_car"):
		player_d = here.distance_to(_flat(_player.global_position))
		if player_d < DOG_FLEE_DISTANCE and not (player_d <= DOG_GREETING_RANGE and _dog_player_ready()):
			flee_from = _flat(_player.global_position)
	if _lada and is_instance_valid(_lada):
		var lada_d := here.distance_to(_flat(_lada.global_position))
		if lada_d < DOG_FLEE_DISTANCE + 1.0 and (flee_from == Vector3.INF or lada_d < player_d):
			flee_from = _flat(_lada.global_position)
	var moved := 0.0
	if flee_from != Vector3.INF:
		dog_state = &"flee"
		moved = _dog_flee(here, flee_from, delta)
	elif player_d <= DOG_GREETING_RANGE and _dog_player_ready():
		dog_state = &"greet"
		_face(_player.global_position - here)
	elif dog_state == &"flee":
		if player_d >= DOG_CALM_DISTANCE:
			dog_state = &"return"
			dog_target = _nearest_loop_point(here)
	elif dog_state == &"pause":
		_dog_wait -= delta
		if _dog_wait <= 0.0:
			dog_state = &"walk"
			dog_target = (dog_target + 1) % DOG_LOOP.size()
	else:
		moved = _dog_walk(here, delta)
	_animate_dog(moved, delta)
	dog_interactable.enabled = _can_pet_dog(_player)

## Шаг по петле к dog_target; на точках паузы — постоять (нюхает снег).
func _dog_walk(here: Vector3, delta: float) -> float:
	var goal := DOG_LOOP[dog_target]
	var to := goal - here
	var dist := to.length()
	var stride := DOG_SPEED * delta
	if dist <= stride:
		if not _dog_can_step(goal):
			return 0.0
		dog.global_position = goal
		dog_state = &"walk"
		if DOG_PAUSE_POINTS.has(dog_target):
			dog_state = &"pause"
			_dog_wait = DOG_PAUSE
		else:
			dog_target = (dog_target + 1) % DOG_LOOP.size()
		return dist
	var next := here + to / dist * stride
	_face(to)
	if not _dog_can_step(next):
		return 0.0
	dog.global_position = next
	return stride

## Отход от угрозы: прочь от неё, в пределах DOG_AREA; зажата в углу — скользит вдоль длинной стороны или стоит.
func _dog_flee(here: Vector3, from: Vector3, delta: float) -> float:
	var away := here - from
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(0, 0, 1)
	away = away.normalized()
	var stride := DOG_FLEE_SPEED * delta
	for dir in [away, Vector3(0, 0, signf(away.z) if absf(away.z) > 0.05 else 1.0), Vector3(0, 0, -signf(away.z) if absf(away.z) > 0.05 else -1.0)]:
		var next := _clamp_area(here + dir * stride)
		if next.distance_to(here) < stride * 0.3:
			continue
		if next.distance_to(from) < here.distance_to(from) - 0.001:
			continue
		if not _dog_can_step(next):
			continue
		_face(next - here)
		dog.global_position = next
		return next.distance_to(here)
	return 0.0

func _clamp_area(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, DOG_AREA.position.x, DOG_AREA.end.x), 0.0, clampf(p.z, DOG_AREA.position.y, DOG_AREA.end.y))

## Не ближе DOG_KEEP к Илюше и только внутри DOG_AREA.
func _dog_can_step(p: Vector3) -> bool:
	if not DOG_AREA.grow(0.001).has_point(Vector2(p.x, p.z)):
		return false
	if _player and is_instance_valid(_player) and (_world == null or _world.get("control_mode") != &"in_car"):
		var keep := _flat(p).distance_to(_flat(_player.global_position))
		if keep < DOG_KEEP and keep < _flat(dog.global_position).distance_to(_flat(_player.global_position)):
			return false
	return true

func _nearest_loop_point(p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in DOG_LOOP.size():
		var d := p.distance_to(DOG_LOOP[i])
		if d < best_d:
			best_d = d
			best = i
	return best

func _animate_dog(moved: float, delta: float) -> void:
	_dog_walk_phase += moved * 7.0
	var swing := sin(_dog_walk_phase) * (0.5 if moved > 0.0 else 0.0)
	for i in _dog_legs.size():
		var leg := _dog_legs[i]
		var sign := 1.0 if i == 0 or i == 3 else -1.0
		leg.rotation.x = move_toward(leg.rotation.x, swing * sign, delta * 8.0)
	var happy := dog_state in [&"pet", &"greet"]
	_dog_tail.rotation.y = sin(clock * (15.0 if happy else (9.0 if dog_state == &"walk" else 4.0))) * (0.9 if happy else 0.45)

# --- кошка ---

func _build_cat() -> void:
	var sill_mat := Materials.plain(Color(0.55, 0.55, 0.56), 0.9)
	var snow := Materials.plain(Color(0.86, 0.88, 0.92), 0.85)
	var sill := Node3D.new()
	sill.name = "CatSill"
	sill.position = CAT_SILL
	add_child(sill)
	_part(sill, _box(Vector3(1.5, 0.05, 0.22)), Vector3(0, -0.025, -0.05), sill_mat, false)
	_part(sill, _box(Vector3(0.5, 0.03, 0.18)), Vector3(0.45, 0.012, -0.05), snow, false)
	cat = Node3D.new()
	cat.name = "Cat"
	cat.position = CAT_SILL + Vector3(-0.15, 0.0, -0.1)
	cat.rotation.y = 0.0   # мордой во двор (−Z)
	add_child(cat)
	var fur := Materials.plain(Color(0.86, 0.50, 0.20), 0.9)
	var stripe := Materials.plain(Color(0.62, 0.30, 0.10), 0.9)
	var white := Materials.plain(Color(0.92, 0.90, 0.86), 0.9)
	var eye := Materials.plain(Color(0.55, 0.75, 0.25), 0.3, Color(0.55, 0.75, 0.25), 0.6)
	var body := SphereMesh.new()
	body.radius = 0.1
	body.height = 0.2
	body.radial_segments = 10
	body.rings = 6
	var torso := _part(cat, body, Vector3(0, 0.11, 0.02), fur, false)
	torso.scale = Vector3(0.95, 1.15, 1.0)
	var chest := _part(cat, _ball(0.04), Vector3(0, 0.13, -0.065), white, false)   # грудка
	chest.scale = Vector3(0.9, 1.2, 0.5)
	_cat_head = Node3D.new()
	_cat_head.position = Vector3(0, 0.25, -0.02)
	cat.add_child(_cat_head)
	var head := SphereMesh.new()
	head.radius = 0.065
	head.height = 0.12
	head.radial_segments = 10
	head.rings = 6
	_part(_cat_head, head, Vector3.ZERO, fur, false)
	var muzzle := _part(_cat_head, _ball(0.026), Vector3(0, -0.022, -0.052), white, false)
	muzzle.scale = Vector3(1.2, 0.8, 0.7)
	for x: float in [-1.0, 1.0]:
		var ear := PrismMesh.new()
		ear.size = Vector3(0.045, 0.05, 0.02)
		_part(_cat_head, ear, Vector3(x * 0.035, 0.065, 0.0), fur, false)
		_part(_cat_head, _box(Vector3(0.016, 0.012, 0.01)), Vector3(x * 0.025, 0.01, -0.06), eye, false)
	_part(cat, _box(Vector3(0.12, 0.012, 0.02)), Vector3(0, 0.2, 0.06), stripe, false)
	_cat_tail = Node3D.new()
	_cat_tail.position = Vector3(0.06, 0.02, 0.08)
	cat.add_child(_cat_tail)
	var tail := _part(_cat_tail, _box(Vector3(0.03, 0.03, 0.2)), Vector3(0.0, 0.0, -0.08), fur, false)
	tail.rotation.y = -0.6

func _update_cat() -> void:
	_cat_tail.rotation.y = 0.35 * sin(clock * 1.6)
	var look := 0.0
	if _player and is_instance_valid(_player):
		var to := _player.global_position - cat.global_position
		if Vector2(to.x, to.z).length() < 7.0:
			look = clampf(atan2(-to.x, -to.z) - cat.rotation.y, -1.0, 1.0)
	_cat_head.rotation.y = lerpf(_cat_head.rotation.y, look, 0.05)

# --- мусор ---

func _build_litter() -> void:
	var papers := [Materials.plain(Color(0.86, 0.84, 0.76), 0.95), Materials.plain(Color(0.60, 0.43, 0.25), 0.95)]   # газета, картон
	var sack_dark := Materials.plain(Color(0.07, 0.07, 0.08), 0.3)
	var ink := Materials.plain(Color(0.35, 0.35, 0.36), 0.95)
	var sack_white := Materials.plain(Color(0.84, 0.84, 0.80), 0.4)
	for i in LITTER.size():
		var spec: Array = LITTER[i]
		var item := Node3D.new()
		item.position = Vector3(spec[0], 0.0, spec[1])
		item.rotation.y = spec[2]
		add_child(item)
		if spec[3] == &"paper":
			item.name = "Litter%d_Paper" % i
			var newspaper := (i >> 1) % 2 == 0
			var sheet := _part(item, _box(Vector3(0.22, 0.006, 0.3)), Vector3(0, 0.03, 0), papers[0 if newspaper else 1], false)
			sheet.rotation = Vector3(0.12, 0, 0.08)
			var fold := _part(item, _box(Vector3(0.22, 0.006, 0.1)), Vector3(0, 0.06, 0.17), papers[0 if newspaper else 1], false)
			fold.rotation.x = -0.6
			if newspaper:   # колонки текста — чтобы читалась газета, а не снег
				for k in 3:
					var line := _part(sheet, _box(Vector3(0.05, 0.002, 0.22)), Vector3(-0.065 + k * 0.065, 0.004, 0.0), ink, false)
					line.scale.z = 1.0 - 0.2 * float(k == 1)
		else:
			item.name = "Litter%d_Sack" % i
			var sack := SphereMesh.new()
			sack.radius = 0.17
			sack.height = 0.34
			sack.radial_segments = 10
			sack.rings = 6
			var material: Material = sack_dark if i % 3 != 2 else sack_white
			var lump := _part(item, sack, Vector3(0, 0.08, 0), material)
			lump.scale = Vector3(1.0, 0.5, 0.8)
			var knot := SphereMesh.new()
			knot.radius = 0.04
			knot.height = 0.08
			_part(item, knot, Vector3(0.06, 0.17, -0.1), material, false)
		litter.append(item)
