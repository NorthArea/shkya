class_name DemoWorld
extends Node3D
## DemoWorld: собирает квартал, ставит участников по Layout (C1), переключает «пешком / в машине» (C4)
## и отдаёт снимок HUD (C6). Состояние миссии хранит только MissionDirector; диалоги и маркеры — QuestFlow.

const Layout = preload("res://game/world/layout.gd")
const SnowTracks = preload("res://game/world/snow_tracks.gd")
const StealthDirectorScript = preload("res://game/stealth/stealth_director.gd")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")

const EXIT_OFFSETS: Array[Vector3] = [   # куда встаёт Илюша при выходе, в осях машины (−x — сторона водителя)
	Vector3(-1.7, 0, 0), Vector3(1.7, 0, 0), Vector3(0, 0, 3.4), Vector3(0, 0, -3.4),
	Vector3(-2.8, 0, 1.5), Vector3(2.8, 0, 1.5), Vector3(-2.8, 0, -1.5), Vector3(2.8, 0, -1.5),
	Vector3(-1.7, 0, 3.0), Vector3(1.7, 0, 3.0), Vector3(-1.7, 0, -3.0), Vector3(1.7, 0, -3.0),
	Vector3(0, 0, 4.8), Vector3(0, 0, -4.8), Vector3(-3.8, 0, 0), Vector3(3.8, 0, 0),
]
const RESET_CLEARANCE := 3.0
const RESET_SHIFTS: Array[float] = [0.0, 4.5, -4.5, 9.0, -9.0, 13.5, -13.5]
const HINT_NO_EXIT := "НЕТ МЕСТА, ЧТОБЫ ВЫЙТИ"
const HINT_SECONDS := 2.0
## Стелс (C7, EXT-01): экран «ВАШ МАРШРУТ УТОЧНЁН» держится FAIL_SECONDS, затем респавн на чекпоинт и тост.
const FAIL_SECONDS := 2.0
const STEALTH_TOAST := "ПРОНЕСЛО. ХЛЕБ ПРИ ВАС"            # после покупки (has_bread); TEXT-01 — короче
const STEALTH_TOAST_NO_BREAD := "ВЫ СНОВА ЗА ХЛЕБОМ"       # до покупки (канон расширения, приёмка P2 6; TEXT-01 — короче)
const STEALTH_TOAST_CAR := "МАШИНУ ОТОГНАЛИ НА ПАРКОВКУ"                 # провал в машине на площадке (EXT-01 fix2, P1)
const STEALTH_TOAST_SECONDS := 2.0

var control_mode: StringName = &"on_foot"
## true, пока открыт диалог или панель: мышь видна и не захватывается по клику (выставляет QuestFlow).
var ui_blocking := false
var _hint := ""
var _hint_left := 0.0
## Владелец шкалы подозрения (C7); создаётся в _ready, узел «StealthDirector».
var stealth: StealthDirector
var _fail_left := 0.0
## Текущий провал — «Лада» с Илюшей на площадке киоска (P1): после экрана машина встаёт на парковку, Илюша — пешком.
var _fail_in_car := false
## Машину после экрана отгоняют на парковку: провал в машине или она стоит на Layout.KIOSK_SQUARE (fix3: вышел у окна).
var _fail_tow := false
var _stealth_toast_left := 0.0
var _stealth_toast_car := false
## STORY-01: карточка «В ГОРОДЕ Н. НИЧЕГО НЕ ПРОИЗОШЛО» (CaughtPanel) — пока она есть, провал не кончается сам по
## FAIL_SECONDS, а ждёт finish_stealth_fail() по кнопке «ЕЩЁ РАЗ»; экран HUD «ВАШ МАРШРУТ УТОЧНЁН» при ней не нужен.
## Без неё (тесты на мире без карточки) провал прежний.
var fail_presenter: Node = null
## EXT-02: подсказка-отказ в укрытии («СНИМИ КОРОБКУ», «ВЫХОД ЗАНЯТ»), HUD — get_hud_state()["hide_hint"].
var _hide_hint := ""
var _hide_hint_left := 0.0

@onready var player: Ilyusha = $Ilyusha
@onready var camera_rig: CameraRig = $CameraRig
@onready var mission: MissionDirector = $MissionDirector
@onready var babka: Node3D = $Babka
@onready var vendor: Node3D = $Vendor
@onready var car: Lada = $Car
@onready var kiosk_zone: Area3D = $KioskZone
@onready var quest_flow: Node = $QuestFlow

## DRIVE-03, прототип D: флаг запуска --raycar — «Лада» на raycast-подвеске (наследник Lada). Скрипт меняется до _ready
## машины, поэтому её узлы, зона входа и сигналы создаются уже новым скриптом; без флага — прежняя «Лада».
func _enter_tree() -> void:
	if "--raycar" in OS.get_cmdline_args() + OS.get_cmdline_user_args() and not $Car.is_node_ready():
		$Car.set_script(load("res://game/vehicles/lada_raycast.gd"))

func _ready() -> void:
	babka.position = Layout.BABKA
	babka.rotation.y = 0.0  # лицом на север, к двору
	vendor.position = Layout.VENDOR
	vendor.interactable.position = Layout.VENDOR_WINDOW - Layout.VENDOR
	car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	car.enter_zone.interacted.connect(func(_actor): enter_car())
	player.camera_rig = camera_rig
	player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	camera_rig.yaw = Layout.SPAWN_YAW
	camera_rig.follow(player, &"on_foot")
	camera_rig.exclude_permanently(babka.get_node("Body").get_rid())
	var tracks := SnowTracks.new()   # следы колёс и шагов на снегу — PLAY-03
	tracks.name = "SnowTracks"
	add_child(tracks)
	stealth = StealthDirectorScript.new()
	stealth.name = "StealthDirector"
	add_child(stealth)
	stealth.player_detected.connect(_on_player_detected)
	_sync_prompts()

func _physics_process(delta: float) -> void:
	_sync_prompts()
	_hint_left = maxf(_hint_left - delta, 0.0)
	_stealth_toast_left = maxf(_stealth_toast_left - delta, 0.0)
	_hide_hint_left = maxf(_hide_hint_left - delta, 0.0)
	# Заморозка шкалы на время диалога (C7); пауза — через process_mode, директор на ней не тикает.
	stealth.set_frozen(quest_flow.is_dialog_open(), &"dialog")
	if _fail_left > 0.0 and not _has_fail_presenter():
		_fail_left -= delta
		if _fail_left <= 0.0:
			_finish_fail()

## Тексты и доступность зон E — только из MissionDirector (C3).
func _sync_prompts() -> void:
	for zone: Interactable in [babka.interactable, vendor.interactable, car.enter_zone]:
		zone.prompt = mission.prompt_for(zone.interaction_id)
		zone.enabled = zone.prompt != ""

# --- C4: пешком / в машине ---

func enter_car() -> void:
	if control_mode == &"in_car":
		return
	if refuse_in_hide(&"car"):
		return  # EXT-02: в укрытии в машину не садятся — подсказка вместо посадки
	control_mode = &"in_car"
	_set_player_active(false)
	car.enter(player)
	camera_rig.yaw = car.global_rotation.y
	camera_rig.follow(car, &"in_car", false)
	mission.notify_entered_car()

## Выйти рядом с машиной на свободное место. Если места нет — остаться в машине и сказать об этом.
func exit_car() -> bool:
	if control_mode != &"in_car":
		return false
	var spot := _free_exit_spot()
	if spot == Vector3.INF:
		_hint = HINT_NO_EXIT
		_hint_left = HINT_SECONDS
		return false
	control_mode = &"on_foot"
	car.exit()
	player.place(spot, car.global_rotation.y)
	_set_player_active(true)
	camera_rig.yaw = car.global_rotation.y
	camera_rig.follow(player, &"on_foot", false)
	# fix3 (третья приёмка, P1): вышел из «Лады» на площадке киоска или на проезжей части B у окна на глазах у
	# полицейского — обнаружен сразу (иначе успевал дойти до окна и открыть покупку, пока шкала растёт: диалог её
	# замораживает); после экрана машину отгоняют на парковку.
	if _car_on_square() and stealth.car_seen_now():
		stealth.alert_now()
	return true

func _set_player_active(active: bool) -> void:
	player.visible = active
	player.input_enabled = active
	player.velocity = Vector3.ZERO
	player.set_physics_process(active)
	player.get_node("CollisionShape3D").set_deferred("disabled", not active)
	player.probe.monitoring = active

func _free_exit_spot() -> Vector3:
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1 | 4 | 32 | 64   # + Breakable (BREAK-01), SnowBank (DRIVE-02): не выходить внутрь объекта или вала
	var origin := car.global_position + Vector3.UP * 0.8
	for offset in EXIT_OFFSETS:
		var spot := car.global_transform * offset
		spot.y = 0.0
		if not Layout.BOUNDS.has_point(Vector2(spot.x, spot.z)):
			continue
		query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.8)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		# Не выходить сквозь стену: от машины до точки должно быть видно.
		var ray := PhysicsRayQueryParameters3D.create(origin, spot + Vector3.UP * 0.8, 1, [car.get_rid()])
		if space.intersect_ray(ray).is_empty():
			return spot
	return Vector3.INF

## «Сбросить автомобиль»: ближайшая к машине свободная точка маршрута, носом по ходу маршрута,
## без скорости и не ближе RESET_CLEARANCE к Илюше (приёмка 5).
func reset_car() -> void:
	reset_hide()
	var position_now := Vector3(car.global_position.x, 0.0, car.global_position.z)
	var candidates := []
	for i in range(1, Layout.ROUTE_DRIVE.size()):
		var a := Layout.ROUTE_DRIVE[i - 1]
		var b := Layout.ROUTE_DRIVE[i]
		var direction := (b - a).normalized()
		var closest := Geometry3D.get_closest_point_to_segment(position_now, a, b)
		for shift in RESET_SHIFTS:
			var point := closest + direction * shift
			if (point - a).dot(direction) < 0.0 or (point - a).length() > a.distance_to(b):
				continue
			candidates.append([point.distance_to(position_now), point, atan2(-direction.x, -direction.z)])
	candidates.sort_custom(func(x, y): return x[0] < y[0])
	var placed := false
	for candidate in candidates:
		if _car_spot_free(candidate[1], candidate[2]):
			car.reset_to(candidate[1], candidate[2])
			placed = true
			break
	if not placed:
		car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)  # маршрут занят целиком — на стоянку во дворе
	if control_mode == &"in_car":
		camera_rig.yaw = car.global_rotation.y
		camera_rig.snap()

func _car_spot_free(point: Vector3, yaw: float) -> bool:
	if control_mode == &"on_foot" and point.distance_to(player.global_position) < RESET_CLEARANCE:
		return false
	var box := BoxShape3D.new()
	box.size = Lada.SIZE + Vector3(0.4, -0.2, 0.4)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 1 | 2 | 32   # + Breakable (BREAK-01)
	query.exclude = [car.get_rid()]
	query.transform = Transform3D(Basis(Vector3.UP, yaw), point + Vector3.UP * (Lada.SIZE.y * 0.5 + 0.1))
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

# --- C7: обнаружение и чекпоинт ---

## Обнаружили: экран провала, ввод Илюши остановлен, шкала заморожена до респавна. В машине видит только сенсор с
## car_area (полицейские, «Лада» почти стоит на площадке киоска — P1, stealth.detected_in_car): водитель «выходит» — машина
## тормозит сама, после экрана она на парковке. Иначе в машине ничего не делаем.
func _on_player_detected() -> void:
	if _fail_left > 0.0:
		return
	if control_mode == &"in_car" and not stealth.detected_in_car:
		return
	_fail_left = FAIL_SECONDS
	_fail_in_car = control_mode == &"in_car"
	_fail_tow = _fail_in_car or _car_on_square()
	stealth.set_frozen(true, &"fail")
	if _fail_in_car:
		car.exit()   # без водителя «Лада» тормозит до остановки (lada.gd), E в машине больше не работает
	player.input_enabled = false
	player.velocity = Vector3.ZERO

## STORY-01: игрок выбрал «ЕЩЁ РАЗ» на карточке провала — респавн на чекпоинте, как по окончании FAIL_SECONDS.
func finish_stealth_fail() -> bool:
	if _fail_left <= 0.0:
		return false
	_finish_fail()
	return true

func _has_fail_presenter() -> bool:
	return fail_presenter != null and is_instance_valid(fail_presenter)

func _finish_fail() -> void:
	_fail_left = 0.0
	_stealth_toast_car = _fail_tow
	if _fail_tow:
		_tow_car_to_parking()
	_fail_in_car = false
	_fail_tow = false
	respawn_at_checkpoint()
	stealth.notify_respawned()
	stealth.set_frozen(false, &"fail")
	if control_mode == &"on_foot" and not ui_blocking:
		player.input_enabled = true
	_stealth_toast_left = STEALTH_TOAST_SECONDS

## P1: «машину отогнали на парковку» — Илюша пешком (дальше respawn_at_checkpoint), «Лада» на конце ROUTE_DRIVE носом
## по последнему отрезку маршрута, как после reset_car(). Миссия и has_bread не трогаются; до прибытия парковка
## засчитывает прибытие (KioskZone), как обычный заезд.
func _tow_car_to_parking() -> void:
	var park := Layout.ROUTE_DRIVE[-1]
	var d := park - Layout.ROUTE_DRIVE[-2]
	car.exit()
	car.reset_to(park, atan2(-d.x, -d.z))
	control_mode = &"on_foot"
	_set_player_active(true)
	camera_rig.follow(player, &"on_foot", false)

## «Лада» стоит на площадке киоска или на проезжей части B у окна (Layout.KIOSK_SQUARE, fix3).
func _car_on_square() -> bool:
	return Layout.KIOSK_SQUARE.has_point(Vector2(car.global_position.x, car.global_position.z))

## Илюша на Layout.STEALTH_CHECKPOINT; машина и миссия не трогаются (C7). В машине не применяется.
func respawn_at_checkpoint() -> bool:
	if control_mode != &"on_foot":
		return false
	reset_hide()
	player.place(Layout.STEALTH_CHECKPOINT, Layout.STEALTH_CHECKPOINT_YAW)
	camera_rig.yaw = Layout.STEALTH_CHECKPOINT_YAW
	camera_rig.snap()
	return true

## EXT-02: Илюша вне укрытия, укрытия на своих местах (группа `hide_spots`, метод reset()). Без запретов.
func reset_hide() -> void:
	player.force_hide_mode(HideTuning.NONE)
	for spot in get_tree().get_nodes_in_group(&"hide_spots"):
		if spot.has_method(&"reset"):
			spot.reset()

## EXT-02: в укрытии действие зоны interaction_id (машина, диалог, покупка) не выполняется — подсказка-отказ.
## true — отказано, вызывающий ничего не делает.
func refuse_in_hide(interaction_id: StringName) -> bool:
	if player.hide_mode == HideTuning.NONE:
		return false
	HideSpot.leave_refused(self, player, interaction_id)   # P2-2: укрытие снято, отказ в строке подсказки
	return true

## EXT-02: показать подсказку-отказ в строке подсказки HUD на seconds (укрытия: «ВЫХОД ЗАНЯТ» и т. п.).
func show_hide_hint(text: String, seconds := HideTuning.HINT_SECONDS) -> void:
	_hide_hint = text
	_hide_hint_left = seconds if text != "" else 0.0

## Экран провала открыт (для HUD и тестов).
func is_stealth_failing() -> bool:
	return _fail_left > 0.0

func anchor_position(id: StringName) -> Vector3:
	match id:
		&"babka": return babka.global_position
		&"vendor": return Layout.VENDOR_WINDOW
		&"kiosk": return Layout.KIOSK
		&"car": return car.global_position
	return Vector3.INF

## C6 — снимок для HUD. HUD только читает его каждый кадр.
func get_hud_state() -> Dictionary:
	var objective := mission.objective()
	var prompt := ""
	if control_mode == &"on_foot":
		var zone := player.current_interactable()
		if zone:
			prompt = zone.prompt
			# EXT-02: в укрытии чужие зоны (Бабка, продавщица, «Лада», наблюдатели) подсказывают отказ.
			if player.hide_mode != HideTuning.NONE and not zone.is_in_group(&"hide_spots"):
				prompt = HideTuning.refusal_for(player.hide_mode, zone.interaction_id)
	elif _hint_left > 0.0:
		prompt = _hint
	var target_id: StringName = objective.get("target_id", &"")
	return {
		"title": objective.get("title", ""),
		"task": objective.get("task", ""),
		"prompt": prompt,
		"target_position": null if target_id == &"" else anchor_position(target_id),
		"babka_marker": mission.babka_marker(),
		"speed_kmh": car.speed_kmh() if control_mode == &"in_car" else -1.0,
		"toast": $QuestFlow.toast_text(),
		"complete": mission.state == MissionDirector.COMPLETE,
		# C7: шкала подозрения, состояние, экран провала и тост после респавна.
		"suspicion": stealth.suspicion,
		"stealth_state": stealth.state,
		"stealth_fail": _fail_left > 0.0 and not _has_fail_presenter(),
		"stealth_toast": _stealth_toast_text() if _stealth_toast_left > 0.0 else "",
		# EXT-02: режим укрытия и подсказка-отказ (HUD показывает её вместо prompt, пока не пуста).
		"hide_mode": player.hide_mode,
		"hide_hint": _hide_hint if _hide_hint_left > 0.0 else "",
		# COINS-01: деньги и вторая строка карточки («Собери монеты: N/35»); money_goal 0 — батон уже куплен.
		"money": mission.money,
		"money_goal": 0 if mission.has_bread or mission.state in [MissionDirector.RETURN_HOME, MissionDirector.COMPLETE] else MissionDirector.BREAD_PRICE,
		"coins_task": objective.get("coins_task", ""),
	}

## Тост после респавна: провал в машине (P1) — про машину, иначе — по has_bread.
func _stealth_toast_text() -> String:
	if _stealth_toast_car:
		return STEALTH_TOAST_CAR
	return STEALTH_TOAST if mission.has_bread else STEALTH_TOAST_NO_BREAD
