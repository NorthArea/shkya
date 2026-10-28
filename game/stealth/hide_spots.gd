extends Node3D
## EXT-02: узел укрытий у киоска (ребёнок LevelGeometry/HideSpots). Создаёт коробку «БАТОНЫ», сугроб и бочку
## из скриптов частей C/D/E; отсутствующий скрипт пропускается (части собираются параллельно).
## Точки — только Layout (C1): BREAD_BOX, HIDE_SNOWDRIFT (+ANCHOR, EXIT), BARREL.

const Layout = preload("res://game/world/layout.gd")

const PARTS := [
	["BreadBox", "res://game/stealth/box_hide_spot.gd", Layout.BREAD_BOX],
	["Snowdrift", "res://game/stealth/snow_hide_spot.gd", Layout.HIDE_SNOWDRIFT],
	["Barrel", "res://game/stealth/barrel_hide_spot.gd", Layout.BARREL],
]

const HideTuning = preload("res://game/stealth/hide_tuning.gd")

var spots: Array = []
## Гэги C02–C06 этой попытки (принятые к показу); сброс — reset_gags() из HideSpot.reset() (респавн, reset_car).
var gags_this_attempt := 0
## Для тестов: id принятых гэгов за всё время и сколько отказано по лимиту.
var gag_log: Array[StringName] = []
var gags_refused := 0

func _init() -> void:
	name = "HideSpots"

func _ready() -> void:
	for part in PARTS:
		if not ResourceLoader.exists(part[1]):
			continue
		var script: GDScript = load(part[1])
		var spot: Node3D = script.new()
		spot.name = part[0]
		spot.home = part[2]
		spot.position = spot.home
		add_child(spot)
		spots.append(spot)

func reset_positions() -> void:
	for spot in spots:
		if spot.has_method("reset"):
			spot.reset()

## EXT-02 P2-1: общий лимит гэгов укрытий за попытку. true — гэг ушёл в SoundDirector.show_gag (сразу или в очередь).
func request_gag(id: StringName, lines: Array, seconds := HideTuning.GAG_PAGE_SECONDS) -> bool:
	if gags_this_attempt >= HideTuning.GAG_LIMIT or lines.is_empty():
		gags_refused += 1
		return false
	gags_this_attempt += 1
	gag_log.append(id)
	var sound := _sound()
	if sound and sound.has_method(&"show_gag"):
		sound.show_gag(lines, seconds)
	return true

## Новая попытка: счётчик заново, очередь непоказанных гэгов прошлой попытки сброшена (идущий дочитывается).
func reset_gags() -> void:
	gags_this_attempt = 0
	var sound := _sound()
	if sound and sound.has_method(&"clear_gag_queue"):
		sound.clear_gag_queue()

func _sound() -> Node:
	var node := get_parent()
	while node:
		if node is DemoWorld:
			return node.get_node_or_null("SoundDirector")
		node = node.get_parent()
	return null
