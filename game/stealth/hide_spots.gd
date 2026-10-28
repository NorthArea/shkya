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

var spots: Array = []

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
