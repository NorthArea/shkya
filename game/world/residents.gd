extends Node3D
## Жители города Н. (PEOPLE-01, часть B; CITY-01, часть P): 14 прохожих на тротуарах кольца, во дворе, у подъезда,
## магазинов и остановок. Маршруты, паузы, старты и силуэты — Layout.RESIDENT_* (C1); поведение — Resident.
## Роли (CITY-01): PAIRS — второй идёт за первым; SMOKERS — курят у подъезда; RIDER — ездит троллейбусом (сигналы
## doors_opened / doors_closed троллейбуса из соседнего узла Traffic). Гудок машины (SoundDirector.horn_sounded) —
## все жители ближе Resident.HORN_RADIUS оглядываются на неё.
## Узел создаёт LevelGeometry (ребёнок DemoWorld/LevelGeometry/Residents, после Traffic); мир ищется вверх по дереву.
## Тела жителей исключены из луча камеры, как тела NPC в Patrols (их слой Car камера и так не видит — на всякий
## случай, если слой поменяют). В группу detection_sensors жители не входят: стелс (C7) их не замечает.

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
	&"ushanka": ["vendor", 2.0],
	&"tourist": ["vendor", 2.0],
	&"kid": ["vendor", 2.0],
	&"kid2": ["vendor", 2.0],
}

## Пары: второй → первый. Маршрут второго — маршрут первого со сдвигом (Layout, жители 8 и 9).
const PAIRS := {8: 6, 9: 7}
const FOLLOW_GAP := 1.2   # м: второй — на столько позади по ходу со старта (проверяет RESIDENTS по маршрутам)
## Курящие у подъезда: курящий → напарник. Курит на точке 0 своего маршрута.
const SMOKERS := {10: 11, 11: 10}
## Пассажир троллейбуса и точка его маршрута, где он ждёт (у павильона A).
const RIDER := 2
const RIDER_WAIT_POINT := 1

var residents: Array = []
var trolley: Node3D
var horn_glances := 0
var _sound: Node

func _init() -> void:
	name = "Residents"

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
		resident.tint = Color(1.0, 1.0, 1.0)
		resident.player = player
		resident.lada = lada
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
	for line in QuestLines.RESIDENT_LINES:
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

## Для тестов и перезапуска: все на старт.
func reset_positions() -> void:
	for resident in residents:
		resident.reset_to_start()
	for f in PAIRS:
		residents[f]._mirror(residents[PAIRS[f]])

func _physics_process(_delta: float) -> void:
	if _sound == null:
		_connect_sound()

## SoundDirector — сосед LevelGeometry в DemoWorld; если ещё нет — подключимся позже.
func _connect_sound() -> void:
	var world := _world()
	_sound = world.get_node_or_null("SoundDirector") if world else null
	if _sound and _sound.has_signal(&"horn_sounded") and not _sound.horn_sounded.is_connected(_on_horn):
		_sound.horn_sounded.connect(_on_horn)
	elif _sound and not _sound.has_signal(&"horn_sounded"):
		_sound = self   # гудков нет — больше не искать

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
