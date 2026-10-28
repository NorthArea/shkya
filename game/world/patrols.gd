extends Node3D
## Наблюдатели и автобус расширения «Ничего необычного» (EXT-01 N): полицейский у киоска (PatrolNpc, пост
## Layout.OFFICER_POST → OFFICER_POST_AFTER), «военком» у микроавтобуса (статичный NPC, Layout.ACCOUNT_OFFICER)
## и микроавтобус ГСУМ (CityVan: Layout.VAN_PARK → по VAN_PATH к остановке улицы B). Точки — только Layout (C1).
## После mission.bread_received (C5) — этап 7: патруль сдвигается к выходу, автобус уезжает к остановке.
## Подсказки зон E — из MissionDirector.prompt_for (C3); реплики подключает QuestFlow по id зон
## (&"officer", &"account_officer"). Узел создаёт LevelGeometry (ребёнок DemoWorld/LevelGeometry/Patrols);
## мир ищется вверх по дереву, как в DetectionSensor.

const Layout = preload("res://game/world/layout.gd")
const NpcScript = preload("res://game/npc/npc.gd")
const PatrolNpcScript = preload("res://game/npc/patrol_npc.gd")
const CityVanScript = preload("res://game/vehicles/city_van.gd")

const PROMPT_TALK := "E — ПОГОВОРИТЬ"

var officer: Node3D
var account_officer: Node3D
var van: CityVan
var _mission: Node
var _moved := false

func _init() -> void:
	name = "Patrols"

func _ready() -> void:
	officer = PatrolNpcScript.new()
	officer.name = "Officer"
	officer.interaction_id = &"officer"
	officer.character = "police"
	officer.height_m = 2.05
	officer.tint = Color(1.0, 1.0, 1.0)
	officer.body_radius = 0.6
	officer.facings = Layout.OFFICER_FACING
	officer.position = Layout.OFFICER_POST
	add_child(officer)
	account_officer = NpcScript.new()
	account_officer.name = "AccountOfficer"
	account_officer.interaction_id = &"account_officer"
	account_officer.character = "officer"
	account_officer.height_m = 2.1
	account_officer.tint = Color(1.0, 1.0, 1.0)
	account_officer.body_radius = 0.45
	account_officer.facing_yaw = Layout.ACCOUNT_OFFICER_YAW
	account_officer.position = Layout.ACCOUNT_OFFICER
	add_child(account_officer)
	van = CityVanScript.new()
	van.name = "CityVan"
	add_child(van)
	van.park(Layout.VAN_PARK, Layout.VAN_PARK_YAW)
	for npc in [officer, account_officer]:
		npc.interactable.prompt = PROMPT_TALK
	var world := _world()
	_mission = world.get_node_or_null("MissionDirector") if world else null
	if _mission and _mission.has_signal("bread_received"):
		_mission.bread_received.connect(_on_bread_received)
	var rig: Node = world.get_node_or_null("CameraRig") if world else null
	if rig and rig.has_method("exclude_permanently"):
		for npc in [officer, account_officer]:
			var body: CollisionObject3D = npc.get_node_or_null("Body")
			if body:
				rig.call_deferred("exclude_permanently", body.get_rid())   # CameraRig готовится позже LevelGeometry

func _world() -> Node:
	var node := get_parent()
	while node:
		if node is DemoWorld:   # @onready-поля мира ещё не готовы (дети раньше родителя), поэтому по классу
			return node
		node = node.get_parent()
	return null

func _physics_process(_delta: float) -> void:
	if _mission == null or not _mission.has_method("prompt_for"):
		return
	for npc in [officer, account_officer]:
		var zone: Interactable = npc.interactable
		zone.prompt = _mission.prompt_for(zone.interaction_id)
		zone.enabled = zone.prompt != ""

## Этап 7 (MISSION_EXTENSION): патруль ближе к выходу с площадки, автобус едет к остановке улицы B и ждёт.
func _on_bread_received() -> void:
	if _moved:
		return
	_moved = true
	officer.move_post(Layout.OFFICER_POST_AFTER)
	van.drive(Layout.VAN_PATH, Layout.VAN_STOP_YAW)

## Для тестов и перезапуска: вернуть всех на исходные места.
func reset_positions() -> void:
	_moved = false
	officer.position = Layout.OFFICER_POST
	van.park(Layout.VAN_PARK, Layout.VAN_PARK_YAW)
