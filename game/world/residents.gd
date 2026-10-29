extends Node3D
## Жители города Н. (PEOPLE-01, часть B; CITY-01, часть P): 14 прохожих на тротуарах кольца, во дворе, у подъезда,
## магазинов и остановок. Маршруты, паузы, старты и силуэты — Layout.RESIDENT_* (C1); поведение — Resident.
## Роли (CITY-01): PAIRS — второй идёт за первым; SMOKERS — курят у подъезда; RIDER — ездит троллейбусом (сигналы
## doors_opened / doors_closed троллейбуса из соседнего узла Traffic). Гудок машины (SoundDirector.horn_sounded) —
## все жители ближе Resident.HORN_RADIUS оглядываются на неё.
## Узел создаёт LevelGeometry (ребёнок DemoWorld/LevelGeometry/Residents, после Traffic); мир ищется вверх по дереву.
## Тела жителей исключены из луча камеры, как тела NPC в Patrols (их слой Car камера и так не видит — на всякий
## случай, если слой поменяют). В группу detection_sensors жители не входят: стелс (C7) их не замечает.
## KNOCK-01: сбитый «Ладой» житель (Resident.knock) — сигналы resident_knocked (взлёт) и resident_landed (упал в снег)
## для SoundDirector, который находит узел по группе GROUP; knocks — сколько раз сбивали всех за мир.
## LIFE-01: LIFE = true — все жители живут по цепочкам целей (планировщик life, game/world/life.gd; персоны — Life.PERSONAS):
## 20 жителей (14 прежних и шесть занятий PEOPLE-03: горка, раскопка, дворник, домино, капот). Пары — второй по следу
## первого; курящие — первая цель «курилка у подъезда»; троллейбусом ездит любой, чья цепочка ведёт на остановку.
## Каждый шаг физики узел обновляет для life камеру, Илюшу и машины (переходы, края карты, LOD). Своя простая геометрия
## занятий (LifeProps): ковёр на выбивалке (виден, пока выбивают), поднятый капот «Жигулей»; столик доминошников и лавки
## у площадки Z15 — пока их нет среди разрушаемых (PROPS_BREAKABLES не подключены к BREAKABLES), без коллизии.

const Layout = preload("res://game/world/layout.gd")
const ResidentScript = preload("res://game/npc/resident.gd")
const LifeScript = preload("res://game/world/life.gd")
const LIFE := true   # LIFE-01: цепочки целей; false — прежние петли PEOPLE-01/CITY-01
const ART_DIR := "res://assets/art/characters/"

## Рисунки части A готовы — true: облик resident_<силуэт>. Пока false — заглушки PLACEHOLDER (рисунки ART-01).
const USE_RESIDENT_ART := true   # интегратор 28.10: рисунки части A приняты в сборку
## Силуэт → [заглушка, высота холста CharacterSprite, м].
const SILHOUETTES := {
	&"babka": ["babka", 2.0],   # PEOPLE-01 (резерв): холст в масштабе Илюши, при 2,0 м рост 1,55 (бабка),
	&"man": ["vendor", 2.0],    # 1,83 (мужик), 1,71 (женщина), 1,35 (пацан)
	&"woman": ["babka", 2.0],
	&"boy": ["vendor", 2.0],
	# PEOPLE-02: персонажи ШКЯ (рост при 2,0 м: шуба 1,60, берет 1,70, фиолетовая 1,63, ушанка 1,80, турист 1,78, пацан 1,55)
	&"shuba": ["babka", 2.0],
	&"beret": ["babka", 2.0],
	&"violet": ["babka", 2.0],
	&"ushanka": ["vendor", 2.0],        # поза с сигаретой — курящему у подъезда (житель 10)
	&"ushanka_walk": ["vendor", 2.0],   # руки опущены — пассажиру остановки A (житель 2)
	&"tourist": ["vendor", 2.0],
	&"kid": ["vendor", 2.0],
	&"kid2": ["vendor", 2.0],
	# PEOPLE-02 c2: остальные бабки ролика «…не наорала бабка» (рост при 2,0 м: собачка 1,65, колпак 1,70, бант 1,58,
	# тюрбан 1,72)
	&"dog": ["babka", 2.0],      # собачка на поводке — часть облика (на земле у ноги)
	&"kolpak": ["babka", 2.0],
	&"bow": ["babka", 2.0],
	&"turban": ["babka", 2.0],
}

## Бабки ролика ШКЯ (PEOPLE-02) — голос бабки: все реплики Resident; остальные — только QuestLines.RESIDENT_LINES_ANYONE.
const BABKA_LOOKS: Array[StringName] = [&"babka", &"woman", &"shuba", &"beret", &"violet", &"dog", &"kolpak", &"bow", &"turban"]

## Пары: второй → первый. Маршрут второго — маршрут первого со сдвигом (Layout, жители 8 и 9).
const PAIRS := {8: 6, 9: 7}
const FOLLOW_GAP := 1.2   # м: второй — на столько позади по ходу со старта (проверяет RESIDENTS по маршрутам)
## Курящие у подъезда: курящий → напарник. Курит на точке 0 своего маршрута.
const SMOKERS := {10: 11, 11: 10}
## Пассажир троллейбуса и точка его маршрута, где он ждёт (у павильона A).
const RIDER := 2
const RIDER_WAIT_POINT := 1

const GROUP := &"residents"

signal resident_knocked(resident: Resident)
signal resident_landed(resident: Resident)

var residents: Array = []
var life   # LIFE-01: планировщик (game/world/life.gd)
var trolley: Node3D
var horn_glances := 0
var _sound: Node

func _init() -> void:
	name = "Residents"
	add_to_group(GROUP)

func _ready() -> void:
	var world := _world()
	var player: Node3D = world.get_node_or_null("Ilyusha") if world else null
	var lada: Node3D = world.get_node_or_null("Car") if world else null
	var traffic: Node = get_parent().get_node_or_null("Traffic") if get_parent() else null
	trolley = traffic.get("trolleybus") if traffic else null
	if LIFE:
		life = LifeScript.new()
		life.player = player
	for i in Layout.RESIDENT_ROUTES.size():
		var resident: Resident = ResidentScript.new()
		var look: StringName = Layout.RESIDENT_LOOKS[i]
		resident.name = "Resident%d_%s" % [i, look]
		resident.setup(i, Layout.RESIDENT_ROUTES[i], Layout.RESIDENT_PAUSES[i], Layout.RESIDENT_STARTS[i])
		resident.character = character_for(look)
		resident.height_m = SILHOUETTES[look][1]
		resident.babka_voice = BABKA_LOOKS.has(look)
		resident.tint = Color(1.0, 1.0, 1.0)
		resident.player = player
		resident.lada = lada
		resident.knock_launched.connect(func(r: Resident): resident_knocked.emit(r))
		resident.knock_landed.connect(func(r: Resident): resident_landed.emit(r))
		if LIFE:
			var persona: Dictionary = LifeScript.PERSONAS[i] if i < LifeScript.PERSONAS.size() else {}
			resident.errand = true
			resident.life = life
			resident.home = persona.get("home", &"")
			resident.plan = persona.get("plan", [])
			resident.rider = true
			resident.trolley = trolley
		residents.append(resident)
	# Роли — до add_child: _ready курящего начинает с перекура.
	for f in PAIRS:
		var second: Resident = residents[f]
		var first: Resident = residents[PAIRS[f]]
		second.leader = first
		first.follower = second
		second.follow_offset = Resident._flat(Layout.RESIDENT_ROUTES[f][0]) - Resident._flat(Layout.RESIDENT_ROUTES[PAIRS[f]][0])
		# LIFE-01: след первого — сколько позади и сбоку стоит второй (по стартовому сдвигу и первому отрезку первого).
		var lead_route: Array = Layout.RESIDENT_ROUTES[PAIRS[f]]
		var s0: int = Layout.RESIDENT_STARTS[PAIRS[f]]
		var dir := (Resident._flat(lead_route[(s0 + 1) % lead_route.size()]) - Resident._flat(lead_route[s0])).normalized()
		second.follow_gap = -second.follow_offset.dot(dir)
		second.follow_side = second.follow_offset.dot(Vector3(-dir.z, 0.0, dir.x))
	for i in SMOKERS:
		if not LIFE:
			residents[i].smoke_point = 0
		residents[i].smoke_partner = residents[SMOKERS[i]]
	if not LIFE:
		residents[RIDER].rider = true
		residents[RIDER].wait_point = RIDER_WAIT_POINT
		residents[RIDER].trolley = trolley
	for resident in residents:
		add_child(resident)
	if trolley:
		trolley.doors_opened.connect(_on_doors_opened)
		trolley.doors_closed.connect(_on_doors_closed)
	for line in QuestLines.RESIDENT_LINES_HIT + QuestLines.RESIDENT_LINES_PASS + QuestLines.RESIDENT_LINES_IDLE:
		Resident.bubble_texture(line)   # подложки пузырей — при загрузке, не в момент первой реплики
	_connect_sound()
	var rig: Node = world.get_node_or_null("CameraRig") if world else null
	if rig and rig.has_method("exclude_permanently"):
		for resident in residents:
			rig.call_deferred("exclude_permanently", resident.body.get_rid())   # CameraRig готовится позже LevelGeometry

## Облик силуэта: рисунок части A, если включён и есть на диске, иначе заглушка.
static func character_for(look: StringName) -> String:
	var art := "resident_%s" % look
	if USE_RESIDENT_ART and ResourceLoader.exists("%s%s_front_idle.svg" % [ART_DIR, art]):
		return art
	return SILHOUETTES[look][0]

func _world() -> Node:
	var node := get_parent()
	while node:
		if node is DemoWorld:   # @onready-поля мира ещё не готовы (дети раньше родителя), поэтому по классу и имени узлов
			return node
		node = node.get_parent()
	return null

## Сколько раз сбивали жителей (с последнего reset_positions()).
func knocks() -> int:
	var total := 0
	for resident in residents:
		total += resident.knocks
	return total

## Для тестов и перезапуска: все на старт (сбитые — тоже: облик, тело и счётчики сбивания — как до удара).
func reset_positions() -> void:
	if life:
		life.reset()
		_update_life()
	for resident in residents:
		resident.reset_to_start()
	for f in PAIRS:
		residents[f]._mirror(residents[PAIRS[f]])
	_break_ready_at = -INF   # BREAK-01
	break_glances = 0
	break_bubbles = 0

func _physics_process(delta: float) -> void:
	if _sound == null:
		_connect_sound()
	_break_clock += delta
	if _breakables == null:
		_connect_breakables()
	if life:
		_update_life()

# --- LIFE-01 ---

var _van: Node3D
var _props_built := false

## Камера, Илюша, машины кольца и автобус ГСУМ — для переходов, краёв карты и LOD; разрушаемые — якоря точек.
func _update_life() -> void:
	if not is_inside_tree():
		return
	life.camera = get_viewport().get_camera_3d()
	if _van == null:
		var patrols := get_parent().get_node_or_null("Patrols") if get_parent() else null
		_van = patrols.get("van") if patrols else null
	life.vehicles = get_tree().get_nodes_in_group(PathVehicle.GROUP)
	if is_instance_valid(_van):
		life.vehicles.append(_van)
	if _breakables and life.breakables != _breakables:
		life.breakables = _breakables
	if not _props_built and _breakables:
		_props_built = true
		_build_life_props()

## Своя простая геометрия занятий: ковёр на выбивалке, поднятый капот; столик и лавки — если их нет среди разрушаемых.
func _build_life_props() -> void:
	var root := Node3D.new()
	root.name = "LifeProps"
	add_child(root)
	var carpet := _box(root, "Carpet", Layout.LIFE_CARPET[1], Layout.LIFE_CARPET[0], Color(0.55, 0.12, 0.12))
	var stripe := _box(carpet, "Stripe", Vector3(0.06, 1.2, 1.7), Vector3.ZERO, Color(0.85, 0.65, 0.25))
	stripe.position = Vector3(0.002, 0.0, 0.0)
	carpet.visible = false
	life.props[&"carpet"] = carpet
	# Капот «Жигулей» (PARKED у гаражей двора): поднят у северного торца, шарнир у лобового стекла.
	var car := Layout.LIFE_HOOD_CAR
	var hood := Node3D.new()
	hood.name = "Hood"
	hood.position = Vector3(car.x, 0.98, car.y - 0.95)
	hood.rotation.x = -1.0
	root.add_child(hood)
	_box(hood, "Panel", Vector3(1.45, 0.04, 1.05), Vector3(0.0, 0.0, -0.52), Color(0.42, 0.44, 0.40))
	_box(hood, "Rod", Vector3(0.03, 0.75, 0.03), Vector3(0.55, -0.35, -0.9), Color(0.2, 0.2, 0.2)).rotation.x = 1.0
	var have := func(id: StringName) -> bool: return _breakables.has_method(&"get_by_id") and _breakables.get_by_id(id) != null
	for spec in Layout.PROPS_BREAKABLES:
		if not spec[0] in [&"Z5_4", &"Z15_9a", &"Z15_9b"] or have.call(spec[0]):
			continue
		var c: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		if spec[1] == &"domino":
			# Столик (1,6 × 0,8 м по x, высота 0,8) и две лавки вдоль длинных сторон.
			_box(root, "DominoTop", Vector3(0.8, 0.06, 1.6), Vector3(c.x, 0.78, c.y), Color(0.42, 0.3, 0.2))
			_box(root, "DominoLeg", Vector3(0.12, 0.75, 0.12), Vector3(c.x, 0.375, c.y), Color(0.3, 0.3, 0.3))
			for side in [-1.0, 1.0]:
				_box(root, "DominoBench", Vector3(0.3, 0.45, 1.6), Vector3(c.x + side * 0.65, 0.225, c.y), Color(0.38, 0.27, 0.18))
		else:
			_box(root, "Bench", Vector3(size.x, 0.08, 0.4), Vector3(c.x, 0.45, c.y + 0.05), Color(0.38, 0.27, 0.18))
			_box(root, "BenchBack", Vector3(size.x, 0.4, 0.06), Vector3(c.x, 0.75, c.y - 0.2), Color(0.38, 0.27, 0.18))
			for x in [-0.75, 0.75]:
				_box(root, "BenchLeg", Vector3(0.08, 0.45, 0.4), Vector3(c.x + x * size.x * 0.5, 0.225, c.y + 0.05), Color(0.25, 0.25, 0.27))

func _box(parent: Node3D, box_name: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var m := MeshInstance3D.new()
	m.name = box_name
	m.mesh = mesh
	m.position = at
	parent.add_child(m)
	return m

## SoundDirector — сосед LevelGeometry в DemoWorld; если ещё нет — подключимся позже.
func _connect_sound() -> void:
	var world := _world()
	_sound = world.get_node_or_null("SoundDirector") if world else null
	if _sound and _sound.has_signal(&"horn_sounded") and not _sound.horn_sounded.is_connected(_on_horn):
		_sound.horn_sounded.connect(_on_horn)
	elif _sound and not _sound.has_signal(&"horn_sounded"):
		_sound = self   # гудков нет — больше не искать

# --- BREAK-01: поломка рядом ---
## Жители ближе BREAK_GLANCE_DISTANCE оглядываются на сломанный объект (glance_at); ближайший говорит реплику
## QuestLines.BREAK_LINES (жительская), не чаще BREAK_BUBBLE_COOLDOWN на всех. Свой HIT при наезде это не блокирует.
const BREAK_GLANCE_DISTANCE := 8.0
const BREAK_BUBBLE_COOLDOWN := 15.0
var break_glances := 0
var break_bubbles := 0
var _break_clock := 0.0
var _break_ready_at := -INF
var _breakables: Node

func _connect_breakables() -> void:
	_breakables = get_tree().get_first_node_in_group(&"breakables_root") if is_inside_tree() else null
	if _breakables and _breakables.has_signal(&"broken") and not _breakables.broken.is_connected(_on_broken):
		_breakables.broken.connect(_on_broken)

func _on_broken(b: Node3D, _by: StringName) -> void:
	var nearest: Resident = null
	var best := BREAK_GLANCE_DISTANCE
	for resident in residents:
		if resident.hidden or resident.state == &"knocked":
			continue
		var to: Vector3 = b.global_position - resident.global_position
		var d := Vector2(to.x, to.z).length()
		if d > BREAK_GLANCE_DISTANCE:
			continue
		if resident.glance_at(b):
			break_glances += 1
		if d <= best:
			best = d
			nearest = resident
	if nearest != null and _break_clock >= _break_ready_at:
		nearest.speak_break(QuestLines.break_line(&"resident", break_bubbles))
		break_bubbles += 1
		_break_ready_at = _break_clock + BREAK_BUBBLE_COOLDOWN

func _on_horn(vehicle: Node3D) -> void:
	for resident in residents:
		if resident.hidden:
			continue
		var to: Vector3 = vehicle.global_position - resident.global_position
		if Vector2(to.x, to.z).length() <= Resident.HORN_RADIUS and resident.glance_at(vehicle):
			horn_glances += 1

func _on_doors_opened(stop: int) -> void:
	for resident in residents:
		resident.on_doors_opened(stop)

func _on_doors_closed(stop: int) -> void:
	for resident in residents:
		resident.on_doors_closed(stop)
