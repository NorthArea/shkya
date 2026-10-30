extends Node
## POLISH-03 B — финал «За хлебом» (критик 30.10: «карточка закрывает героев, +50 опыта ничего не значит»).
## 1) Протокол: счётчики прохода для панели финала HUD (C6, get_hud_state()["protocol"]) — время в пути (с конца заставки до
##    сдачи), монеты собрано / потрачено / осталось, сбито прохожих, сбито дронов, сломано, сколько раз заметили патрули.
##    Источники: Coins.collected_count, MissionDirector.money и BREAD_PRICE, Residents.knocks(), Drones.breaks,
##    Breakables.breaks, StealthDirector.detections.
## 2) После протокола — сцена этапа 10 расширения: пауза, Бабка смотрит на улицу — на микроавтобус ГСУМ у соседнего подъезда
##    (RoadClosure.park_finale), камера плавно отъезжает и разворачивается так, что в кадре Илюша, Бабка и автобус, над
##    Бабкой — «Или не сходишь» (QuestLines.FINALE_LOOK). Потом QuestFlow открывает карточку «Конец демо» (внизу экрана,
##    героев не закрывает). E / Enter / A геймпада — пропустить сцену (PAD-01).
## Состояние миссии не трогает; ввод на время сцены заблокирован QuestFlow. Узел создаёт QuestFlow.

const Layout = preload("res://game/world/layout.gd")

const CAMERA_SECONDS := 2.2        # отъезд камеры
const CAMERA_BACK := 1.5           # м: точка, за которой идёт камера, — назад от героев (вместе с плечом камеры ≈ 5,5 м)
const CAMERA_SIDE := 1.2           # м вбок: герои слева от середины кадра, автобус правее
const CAMERA_PITCH := -0.24
const SKIP_AFTER := 0.4            # с: раньше нажатие не пропускает (то же E, что закрыло протокол)
const VAN_RANGE := 60.0            # м от Бабки: дальше автобус не ищем — взгляд просто на улицу (к выезду со двора)

var world: Node
var flow: Node
## Секунды игры: с конца заставки до сдачи, без паузы (физический кадр на паузе не идёт).
var play_seconds := 0.0
var playing := false
## Для проверок: сцена показана / пропущена, куда смотрели.
var shown := 0
var skipped := 0
var look_target: Node3D
var bubble_back: Sprite3D
var bubble: Label3D

var _done := Callable()
var _t := 0.0
var _focus: Node3D
var _from_pos := Vector3.ZERO
var _to_pos := Vector3.ZERO
var _from_yaw := 0.0
var _to_yaw := 0.0
var _from_pitch := 0.0
var _bubble_on := false
var _street_point: Node3D

func _ready() -> void:
	flow = get_parent()
	world = flow.get_parent()

func _physics_process(delta: float) -> void:
	var mission: MissionDirector = world.get("mission")
	if mission and mission.state != MissionDirector.COMPLETE and not _intro_running():
		play_seconds += delta
	if playing:
		_tick(delta)

func _intro_running() -> bool:
	var intro: Node = world.get_node_or_null("Intro")
	return intro != null and intro.has_method("is_running") and intro.is_running()

# --- протокол ---

## Счётчики прохода (числа) — для HUD и проверок.
func stats() -> Dictionary:
	var mission: MissionDirector = world.get("mission")
	var coins: Node = world.get_node_or_null("LevelGeometry/Coins")
	var residents: Node = world.get_node_or_null("LevelGeometry/Residents")
	var drones: Node = world.get_node_or_null("LevelGeometry/Drones")
	var breakables: Node = world.get_node_or_null("LevelGeometry/Breakables")
	var stealth: Node = world.get("stealth")
	var collected: int = coins.collected_count if coins else 0
	var left: int = mission.money if mission else 0
	var bought := mission != null and (mission.state == MissionDirector.RETURN_HOME or mission.state == MissionDirector.COMPLETE)
	return {
		"seconds": play_seconds,
		"coins": collected,
		"spent": MissionDirector.BREAD_PRICE if bought else 0,
		"left": left,
		"knocks": residents.knocks() if residents and residents.has_method("knocks") else 0,
		"drones": drones.breaks if drones else 0,
		"broken": breakables.breaks if breakables else 0,
		"detections": stealth.detections if stealth else 0,
	}

## Строки протокола для панели финала: id строки → текст значения (QuestLines.PROTOCOL_ROWS задаёт порядок и подписи).
func protocol() -> Dictionary:
	var s := stats()
	var secs := int(round(float(s["seconds"])))
	var knocks: int = s["knocks"]
	return {
		&"time": "%d:%02d" % [secs / 60, secs % 60],
		&"coins": "%d ₽" % s["coins"],
		&"spent": "%d ₽" % s["spent"],
		&"left": "%d ₽" % s["left"],
		&"knocks": ("%d — %s" % [knocks, QuestLines.PROTOCOL_KNOCKS_OK]) if knocks > 0 else "0",
		&"drones": str(s["drones"]),
		&"broken": str(s["broken"]),
		&"detections": "%d %s" % [s["detections"], _times(s["detections"])],
	}

static func _times(n: int) -> String:
	var tail := n % 100
	if tail >= 11 and tail <= 14:
		return "раз"
	match n % 10:
		2, 3, 4:
			return "раза"
	return "раз"

# --- сцена этапа 10 ---

func play(done: Callable) -> void:
	_done = done
	_t = 0.0
	playing = true
	shown += 1
	_bubble_on = false
	var babka: Node3D = world.babka
	var player: Node3D = world.player
	look_target = _van_in_yard()
	if look_target == null:
		look_target = _street()
	if babka.has_method("look_at_target"):
		babka.look_at_target(look_target)
	var visual: Node3D = player.get_node_or_null("Visual")
	var to_target := look_target.global_position - player.global_position
	if visual:
		visual.global_rotation.y = atan2(-to_target.x, -to_target.z)
	# Камера: за точкой, которая отъезжает назад-вбок от героев; взгляд — вдоль взгляда Бабки на автобус.
	var rig: CameraRig = world.camera_rig
	var mid := (player.global_position + babka.global_position) * 0.5
	var dir := look_target.global_position - mid
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)   # вправо от взгляда
	_focus = Node3D.new()
	_focus.name = "FinaleFocus"
	world.add_child(_focus)
	_focus.global_position = player.global_position
	_from_pos = player.global_position
	_to_pos = Vector3(mid.x, player.global_position.y, mid.z) - dir * CAMERA_BACK - side * CAMERA_SIDE
	_from_yaw = rig.yaw
	_to_yaw = atan2(-dir.x, -dir.z)
	_from_pitch = rig.pitch
	rig.shoulder = 0.0
	rig.follow(_focus, &"on_foot", false)
	rig.yaw = _from_yaw
	rig.pitch = _from_pitch

func _tick(delta: float) -> void:
	_t += delta
	if _t > SKIP_AFTER and (Input.is_action_just_pressed(&"interact") or Input.is_action_just_pressed(&"ui_accept")):
		skipped += 1
		_t = maxf(_t, QuestLines.FINALE_LOOK_PAUSE + QuestLines.FINALE_LOOK_SECONDS)
	var k := clampf(_t / CAMERA_SECONDS, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var rig: CameraRig = world.camera_rig
	if is_instance_valid(_focus):
		_focus.global_position = _from_pos.lerp(_to_pos, k)
	rig.yaw = lerp_angle(_from_yaw, _to_yaw, k)
	rig.pitch = lerpf(_from_pitch, CAMERA_PITCH, k)
	if not _bubble_on and _t >= QuestLines.FINALE_LOOK_PAUSE:
		_show_bubble()
	if _t >= QuestLines.FINALE_LOOK_PAUSE + QuestLines.FINALE_LOOK_SECONDS:
		playing = false
		if is_instance_valid(_focus):
			_focus.global_position = _to_pos
		rig.yaw = _to_yaw
		rig.pitch = CAMERA_PITCH
		if _done.is_valid():
			_done.call()

## «ПОГУЛЯТЬ» или сброс: камера — снова за Илюшей, реплика гаснет, Бабка смотрит как обычно.
func finish() -> void:
	playing = false
	if bubble_back:
		bubble_back.visible = false
		bubble.visible = false
	var babka: Node = world.babka
	if babka and babka.has_method("stop_looking"):
		babka.stop_looking()
	var rig: CameraRig = world.camera_rig
	if rig.target == _focus:
		rig.follow(world.player, &"on_foot", false)
	if is_instance_valid(_focus):
		_focus.queue_free()
	_focus = null

func is_bubble_visible() -> bool:
	return bubble_back != null and bubble_back.visible

func _show_bubble() -> void:
	_bubble_on = true
	if bubble_back == null:
		var parts: Array = flow._build_bubble("FinaleBubble", QuestLines.FINALE_LOOK, true)
		bubble_back = parts[0]
		bubble = parts[1]
		bubble_back.position = Vector3(0, flow.BUBBLE_Y + bubble_back.texture.get_height() * bubble_back.pixel_size * 0.5, 0)
	bubble_back.visible = true
	bubble.visible = true
	flow._pop_3d(bubble_back)
	var dialog: Node = flow.get("dialog")
	if dialog and dialog.has_method("play_voice"):
		dialog.play_voice(&"babka")

## Микроавтобус ГСУМ финала (RoadClosure.park_finale), если виден и рядом с Бабкой.
func _van_in_yard() -> Node3D:
	var closure: Node = world.get_node_or_null("LevelGeometry/Patrols/RoadClosure")
	if closure == null:
		return null
	var van: Node3D = closure.get("van")
	if van and van.visible and van.global_position.distance_to(world.babka.global_position) < VAN_RANGE:
		return van
	return null

## Точка «на улице»: выезд со двора к улице A (если автобуса нет).
func _street() -> Node3D:
	if _street_point == null:
		_street_point = Node3D.new()
		_street_point.name = "FinaleStreet"
		world.add_child(_street_point)
		_street_point.global_position = Layout.ROUTE_DRIVE[2]
	return _street_point
