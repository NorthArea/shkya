extends Node3D
## Наблюдатели и автобус расширения «Ничего необычного» (EXT-01 N): полицейский у киоска (PatrolNpc, пост
## Layout.OFFICER_POST → OFFICER_POST_AFTER), «военком» у микроавтобуса (статичный NPC, Layout.ACCOUNT_OFFICER)
## и микроавтобус ГСУМ (CityVan: Layout.VAN_PARK → по VAN_PATH к остановке улицы B). Точки — только Layout (C1).
## После mission.bread_received (C5) — этап 7: патруль сдвигается к выходу, автобус едет на площадку киоска.
## Полицейский смотрит дальше канона (STEALTH_DESIGN: 9 м, 75°): OFFICER_RANGE/OFFICER_FOV — при 9 м проход у гаражей
## (x ≈ 51, в 11 м от поста) не накрывался ни одним углом, а «в лоб» от парковки шкала не доходила до провала
## (приёмка 28.10, P1; расчёт экспозиции путей — отчёт EXT-01 fix). Держит угол OFFICER_HOLD с. Угол 100°, а не 80°
## (EXT-01 fix2, P2-1): при 80° «в лоб» от парковки к окну проходила в 2 фазах разворота из 4 — прямая идёт в 2,5 м от
## поста и пересекает узкий конус за ~1 с. Полицейский «предназначен для обнаружения машин» (STEALTH_DESIGN):
## «Лада» с Илюшей на площадке Layout.KIOSK_SQUARE для его сенсора — как Илюша (car_area, P1).
## Подсказка «E — ПОГОВОРИТЬ» у полицейского — только спереди и сбоку (PatrolNpc.can_talk_to, P3).
## Подсказки зон E — из MissionDirector.prompt_for (C3); реплики подключает QuestFlow по id зон
## (&"officer", &"account_officer"). EXT-01 fix3 (третья приёмка, P1): второй наблюдатель Officer2 (&"officer2", без
## диалога и подсказки E) — на Layout.OFFICER2_POST у северного угла площадки, углы OFFICER2_FACING, те же 12 м / 100° и
## 7–9 с, car_area — тот же KIOSK_SQUARE; после покупки не двигается. EXT-01 fix4: второй пост к северу от окна,
## OFFICER2_RANGE 14 м; первый после диалога отворачивается от Илюши и от парковки (PatrolNpc.away_point). Узел создаёт LevelGeometry (ребёнок DemoWorld/LevelGeometry/Patrols);
## мир ищется вверх по дереву, как в DetectionSensor.
## EXT-01 fix5 (пятая приёмка): у первого три угла Layout.OFFICER_FACING (+ восток), обзор по углу OFFICER_FOVS
## [100°, 150°, 100°], разворот не через окно (avoid_yaw); у второго восток-юго-восток держится OFFICER2_HOLD_EAST (5–6 с) —
## западный угол дольше держит глубокую часть коридора у киоска (P2: SNEAK_WEST без ожидания).
## EXT-01 fix6 (шестая приёмка): правило близости — в DetectionSensor (3 м / 6 м). Дальность первого — 14 м, как у второго
## (вдоль x ≈ 74 в 12,2 м от поста было чисто); после перехода на OFFICER_POST_AFTER — OFFICER_AFTER_RANGE 12 м: стоянка и
## место выхода из машины — в 13,0–13,4 м от этого поста, в секторе угла [1]. Второй держит угол [0] OFFICER2_HOLDS 10–12 с.
## EXT-01 fix7 (седьмая приёмка: подходы с востока чисты без ожидания в 58–88 % фаз): восточный угол первого — 150°
## (OFFICER_FOVS[2]; на посту после покупки — прежние 100°, OFFICER_AFTER_FOVS: при 150° окно оттуда в 1,7° от края),
## второй держит восток-юго-восток столько же, сколько запад, — OFFICER2_HOLD_EAST 10–12 с.

const Layout = preload("res://game/world/layout.gd")
const NpcScript = preload("res://game/npc/npc.gd")
const PatrolNpcScript = preload("res://game/npc/patrol_npc.gd")
const CityVanScript = preload("res://game/vehicles/city_van.gd")

const PROMPT_TALK := "E — ПОГОВОРИТЬ"
const OFFICER_RANGE := 14.0              # fix6: было 12 — путь вдоль x ≈ 74 в 12,2 м от поста не накрывался
const OFFICER_AFTER_RANGE := 12.0        # fix6: на посту после покупки — стоянка в 13 м остаётся вне сектора
const OFFICER_FOV := 100.0
## fix5: обзор первого по углам OFFICER_FACING; [1] (пеленг 150°) — 150°: сектор 75°…225° накрывает и среднюю часть прямой
## x = 59,5 («в лоб» — провал во всех фазах), и второе колено диагонали с дороги B (при 100° — 18 из 32 / 47 из 96, Layout).
## fix7: [2] (восток, пеленг 90°) — 150°: сектор 15°…165° — подход с дороги B на запад вдоль z −76…−81; окно (пеленг
## 337…341°) — 34° за его краем, 42° за краем [0].
const OFFICER_FOVS := [100.0, 150.0, 150.0]
## fix7: на OFFICER_POST_AFTER (57; −66) окно — пеленг 10…13°, 11,2 м: при 150° у [2] — 1,7…4,7° от края, поэтому 100°.
const OFFICER_AFTER_FOVS := [100.0, 150.0, 100.0]
const OFFICER2_FOV := 100.0
const OFFICER2_HOLD_EAST := Vector2(10.0, 12.0)  # fix7: угол [1] второго, как запад (fix5 — 5–6 с: дорога B севернее окна в секторе ~29 % цикла)
const OFFICER2_HOLD_WEST := Vector2(10.0, 12.0)  # fix6: угол [0] — глубокая часть коридора в секторе ~61 % цикла (было 7–9 с, ~54 %)
const OFFICER2_RANGE := 14.0             # fix4: с (59, −87) до входа с улицы C и до обхода по дороге z = −84
const OFFICER_HOLD := Vector2(7.0, 9.0)   # с на угол: при 3–4 с осторожный честный проход занимал 14–15 с (норма участка 45–90 с)

var officer: Node3D
var officer2: Node3D
var account_officer: Node3D
var van: CityVan
var _mission: Node
var _world_node: Node
var _moved := false

func _init() -> void:
	name = "Patrols"

func _ready() -> void:
	officer = PatrolNpcScript.new()
	officer.name = "Officer"
	officer.interaction_id = &"officer"
	officer.character = "police"
	officer.height_m = 2.05   # фигура 0,861 холста = 1,77 м ≈ Илюша (1,80 м), как на e01 (LOOK-01)
	officer.tint = Color(1.0, 1.0, 1.0)
	officer.body_radius = 0.6
	officer.facings = Layout.OFFICER_FACING
	officer.sensor_range = OFFICER_RANGE
	officer.sensor_fov = OFFICER_FOV
	officer.facing_fovs = OFFICER_FOVS
	officer.turn_every = OFFICER_HOLD
	officer.position = Layout.OFFICER_POST
	officer.away_point = Layout.ROUTE_DRIVE[-1]   # fix4: после диалога не смотреть туда, куда уходят, — к парковке
	# fix5: разворот восток → запад-юго-запад и прочие — не через окно киоска (с поста на северо-северо-запад).
	var to_window1 := Layout.VENDOR_WINDOW - Layout.OFFICER_POST
	officer.avoid_yaw = atan2(-to_window1.x, -to_window1.z)
	add_child(officer)
	officer.sensor.show_cone = true
	officer.sensor.car_area = Layout.KIOSK_SQUARE
	officer2 = PatrolNpcScript.new()
	officer2.name = "Officer2"
	officer2.interaction_id = &"officer2"   # без диалога: prompt_for даёт "", зона выключена
	officer2.character = "guard"   # «росгвардеец» STEALTH_DESIGN: свой облик по e03 (ART-08), без эмблем
	officer2.height_m = officer.height_m
	officer2.tint = officer.tint
	officer2.body_radius = officer.body_radius
	officer2.facings = Layout.OFFICER2_FACING
	officer2.sensor_range = OFFICER2_RANGE
	officer2.sensor_fov = OFFICER2_FOV
	officer2.facing_holds = [OFFICER2_HOLD_WEST, OFFICER2_HOLD_EAST]
	officer2.turn_every = OFFICER_HOLD
	officer2.position = Layout.OFFICER2_POST
	# fix4: разворот запад ↔ восток-юго-восток — через север, не через окно киоска на юге.
	var to_window := Layout.VENDOR_WINDOW - Layout.OFFICER2_POST
	officer2.avoid_yaw = atan2(-to_window.x, -to_window.z)
	add_child(officer2)
	officer2.sensor.show_cone = true
	officer2.sensor.car_area = Layout.KIOSK_SQUARE
	officer2.interactable.prompt = ""
	officer2.interactable.enabled = false
	account_officer = NpcScript.new()
	account_officer.name = "AccountOfficer"
	account_officer.interaction_id = &"account_officer"
	account_officer.character = "officer"
	account_officer.height_m = 2.2   # фигура 0,948 холста = 2,09 м: в 1,18 раза выше полицейского (1,77 м), как на e03 (LOOK-01)
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
	_world_node = world
	_mission = world.get_node_or_null("MissionDirector") if world else null
	if _mission and _mission.has_signal("bread_received"):
		_mission.bread_received.connect(_on_bread_received)
	var rig: Node = world.get_node_or_null("CameraRig") if world else null
	if rig and rig.has_method("exclude_permanently"):
		for npc in [officer, officer2, account_officer]:
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
		zone.enabled = zone.prompt != "" and talkable(npc)

## Можно ли заговорить с наблюдателем сейчас: полицейский со спины не отвечает (угол от корпуса > 100°, P3).
func talkable(npc: Node) -> bool:
	if _world_node == null or not npc.has_method("can_talk_to"):
		return true
	return npc.can_talk_to(_world_node.get("player"))

## Этап 7 (MISSION_EXTENSION): патруль ближе к выходу с площадки, автобус встаёт на площадке и ждёт.
func _on_bread_received() -> void:
	if _moved:
		return
	_moved = true
	officer.facing_fovs = OFFICER_AFTER_FOVS   # ставится по прибытии (_start_turn), на переходе сенсор выключен
	officer.move_post(Layout.OFFICER_POST_AFTER)
	officer.sensor.range_m = OFFICER_AFTER_RANGE
	van.drive(Layout.VAN_PATH, Layout.VAN_STOP_YAW)

## Для тестов и перезапуска: вернуть всех на исходные места.
func reset_positions() -> void:
	_moved = false
	officer.facing_fovs = OFFICER_FOVS
	officer.place_at(Layout.OFFICER_POST)
	officer.sensor.range_m = OFFICER_RANGE
	officer2.place_at(Layout.OFFICER2_POST)
	van.park(Layout.VAN_PARK, Layout.VAN_PARK_YAW)
