extends Node3D
## Жители города Н. (PEOPLE-01, часть B): 8 прохожих на тротуарах кольца, во дворе и у остановок. Маршруты, паузы,
## старты и силуэты — Layout.RESIDENT_* (C1); поведение — Resident.
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
	&"babka": ["babka", 2.0],   # холст жителей нарисован в масштабе Илюши: при 2,0 м рост в игре 1,55 (бабка),
	&"man": ["vendor", 2.0],    # 1,83 (мужик), 1,71 (женщина), 1,35 (пацан) — рекомендация части A, толщина линий
	&"woman": ["babka", 2.0],   # у всех одинаковая
	&"boy": ["vendor", 2.0],
}

var residents: Array = []

func _init() -> void:
	name = "Residents"

func _ready() -> void:
	var world := _world()
	var player: Node3D = world.get_node_or_null("Ilyusha") if world else null
	var lada: Node3D = world.get_node_or_null("Car") if world else null
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
		add_child(resident)
		residents.append(resident)
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
