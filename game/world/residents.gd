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

const Layout = preload("res://game/world/layout.gd")
const ResidentScript = preload("res://game/npc/resident.gd")
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

## Бабки ролика ШКЯ (PEOPLE-02) — голос бабки.
const BABKA_LOOKS: Array[StringName] = [&"babka", &"shuba", &"beret", &"violet", &"dog", &"kolpak", &"bow", &"turban"]
## TEXT-01: голос реплик по облику (QuestLines.STREET_LINES); не названный облик — бабкин.
const VOICE_BY_LOOK := {&"man": &"man", &"ushanka": &"man", &"ushanka_walk": &"man", &"tourist": &"man",
	&"woman": &"woman", &"boy": &"kid", &"kid": &"kid", &"kid2": &"kid"}
const LineBagScript = preload("res://game/npc/line_bag.gd")
## TEXT-01: общий лимит «болтовни» (car, walk, idle) — не больше CHATTER_MAX таких пузырей на экране и не чаще
## CHATTER_GAP между их началами; hit, push и break — вне лимита (Resident.EVENT_KINDS).
const CHATTER_MAX := 2
const CHATTER_GAP := 1.0

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
var bag: RefCounted = LineBagScript.new(ResidentScript.SEED)   # общий «мешок» реплик улицы
var push_bubbles := 0
var horn_bubbles := 0
var _chatter_at := -INF
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
	for i in Layout.RESIDENT_ROUTES.size():
		var resident: Resident = ResidentScript.new()
		var look: StringName = Layout.RESIDENT_LOOKS[i]
		resident.name = "Resident%d_%s" % [i, look]
		resident.setup(i, Layout.RESIDENT_ROUTES[i], Layout.RESIDENT_PAUSES[i], Layout.RESIDENT_STARTS[i])
		resident.character = character_for(look)
		resident.height_m = SILHOUETTES[look][1]
		resident.voice = voice_for(look)
		resident.bag = bag
		resident.chatter = self
		resident.tint = Color(1.0, 1.0, 1.0)
		resident.player = player
		resident.lada = lada
		resident.knock_launched.connect(func(r: Resident): resident_knocked.emit(r))
		resident.knock_landed.connect(func(r: Resident): resident_landed.emit(r))
		residents.append(resident)
	# Роли — до add_child: _ready курящего начинает с перекура.
	for f in PAIRS:
		var second: Resident = residents[f]
		var first: Resident = residents[PAIRS[f]]
		second.leader = first
		first.follower = second
		second.follow_offset = Resident._flat(Layout.RESIDENT_ROUTES[f][0]) - Resident._flat(Layout.RESIDENT_ROUTES[PAIRS[f]][0])
	for i in SMOKERS:
		residents[i].smoke_point = 0
		residents[i].smoke_partner = residents[SMOKERS[i]]
	residents[RIDER].rider = true
	residents[RIDER].wait_point = RIDER_WAIT_POINT
	residents[RIDER].trolley = trolley
	for resident in residents:
		add_child(resident)
	if trolley:
		trolley.doors_opened.connect(_on_doors_opened)
		trolley.doors_closed.connect(_on_doors_closed)
	for line in QuestLines.all_street_lines():
		Resident.bubble_texture(line)   # подложки пузырей — при загрузке, не в момент первой реплики
	_connect_sound()
	if player and player.has_signal(&"punch_landed"):
		player.punch_landed.connect(_on_punch_landed)
	var rig: Node = world.get_node_or_null("CameraRig") if world else null
	if rig and rig.has_method("exclude_permanently"):
		for resident in residents:
			rig.call_deferred("exclude_permanently", resident.body.get_rid())   # CameraRig готовится позже LevelGeometry

## Голос реплик облика look.
static func voice_for(look: StringName) -> StringName:
	return VOICE_BY_LOOK.get(look, QuestLines.VOICE_BABKA)

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
	for resident in residents:
		resident.reset_to_start()
	for f in PAIRS:
		residents[f]._mirror(residents[PAIRS[f]])
	_break_ready_at = -INF   # BREAK-01
	break_glances = 0
	break_bubbles = 0
	bag.reset()
	push_bubbles = 0
	horn_bubbles = 0
	_chatter_at = -INF

# --- TEXT-01: общий лимит пузырей и события ---

## Можно ли жителю who начать пузырь car/walk/idle: не чаще CHATTER_GAP и не больше CHATTER_MAX таких на экране.
func allow_chatter(who: Node) -> bool:
	if _break_clock < _chatter_at + CHATTER_GAP:
		return false
	var shown := 0
	for resident in residents:
		if resident != who and resident.bubble_visible() and not resident.bubble_kind in ResidentScript.EVENT_KINDS:
			shown += 1
	return shown < CHATTER_MAX

func note_bubble(_who: Node, kind: StringName) -> void:
	if not kind in ResidentScript.EVENT_KINDS:
		_chatter_at = _break_clock

## Удар Илюши пешком задел жителя — тот оборачивается и говорит реплику push (Resident.on_pushed).
func _on_punch_landed(targets: Array) -> void:
	for target in targets:
		if target is Resident and target in residents and target.on_pushed():
			push_bubbles += 1

func _physics_process(delta: float) -> void:
	if _sound == null:
		_connect_sound()
	_break_clock += delta
	if _breakables == null:
		_connect_breakables()

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
## своего голоса (QuestLines.street_lines(voice, &"break")), не чаще BREAK_BUBBLE_COOLDOWN на всех. Свой HIT при наезде это не блокирует.
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
	if nearest != null and _break_clock >= _break_ready_at and nearest.speak_event(&"break"):
		break_bubbles += 1
		_break_ready_at = _break_clock + BREAK_BUBBLE_COOLDOWN

## Гудок: все ближе HORN_RADIUS оглядываются; ближайший из оглянувшихся говорит реплику car (если его очередь).
func _on_horn(vehicle: Node3D) -> void:
	var nearest: Resident = null
	var best := INF
	for resident in residents:
		if resident.hidden:
			continue
		var to: Vector3 = vehicle.global_position - resident.global_position
		var d := Vector2(to.x, to.z).length()
		if d <= Resident.HORN_RADIUS and resident.glance_at(vehicle):
			horn_glances += 1
			if d < best:
				best = d
				nearest = resident
	if nearest != null and nearest.speak_event(&"car"):
		horn_bubbles += 1

func _on_doors_opened(stop: int) -> void:
	for resident in residents:
		resident.on_doors_opened(stop)

func _on_doors_closed(stop: int) -> void:
	for resident in residents:
		resident.on_doors_closed(stop)
