class_name Resident
extends "res://game/npc/npc.gd"
## Житель города Н. (PEOPLE-01, часть B): ходит по замкнутому маршруту из точек (Layout.RESIDENT_*, C1)
## со скоростью SPEEDS[index], на отмеченных точках стоит PAUSES[index] с. Илюша ближе NOTICE_DISTANCE — житель
## останавливается на STARE_SECONDS и смотрит на него (look_at_target из npc.gd), потом идёт дальше; пока Илюша
## не отошёл дальше RELEASE_DISTANCE, второй раз не останавливается. Илюша прямо по ходу ближе BLOCK_DISTANCE — ждёт.
## Тело — AnimatableBody3D на слое Car (3-й, значение 4), маска 0: Илюша (маска World|Car) упирается в него и
## обходит, не толкает; транспорт кольца (датчик World|Player|Car) тормозит; луч наблюдателей (DetectionSensor,
## WORLD_MASK = 1) и пружина камеры (маска 1) его не видят — житель не укрытие (C7). «Лада» (маска World) сквозь
## тело проходит: при касании житель встаёт на ближайшую свободную точку маршрута (place), без рэгдолла; «Лада»
## стоит поперёк пути — житель разворачивается. Без случайностей: всё задаётся индексом и маршрутом.
##
## CITY-01 (часть P) — город живее. Роли задаёт Residents: пара (follower ходит «жёстко» за leader со сдвигом
## follow_offset — маршрут первого, сдвинутый на постоянный вектор; на разворотах впереди оказывается второй; всё, что
## касается пары — «Лада», Илюша, остановки, — решает первый), курящий (smoke_point: стоит SMOKE_SECONDS, время от
## времени поворачивается, потом уходит по маршруту и возвращается), пассажир (rider: ждёт троллейбус у wait_point, по
## doors_opened идёт к двери и исчезает, на другой остановке выходит из двери — Layout.RESIDENT_RIDER_B_PATH).
## Реакции: гудок (Residents → glance_at) — остановиться и посмотреть GLANCE_SECONDS; «Лада» с водителем ближе
## LADA_REACT_DISTANCE — пузырь-реплика QuestLines.RESIDENT_LINES на BUBBLE_SECONDS над головой (как пузыри квеста),
## не чаще BUBBLE_COOLDOWN, и взгляд на неё. Случайности — только свой RandomNumberGenerator с seed SEED + индекс.

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const Layout = preload("res://game/world/layout.gd")

const SPEEDS: Array[float] = [1.2, 1.45, 1.35, 1.6, 1.3, 1.25, 1.5, 1.4, 1.5, 1.4, 1.3, 1.35, 1.25, 1.45]   # м/с, 1,2–1,6; у второго в паре — как у первого
const PAUSES: Array[float] = [4.0, 2.5, 3.5, 2.0, 3.0, 4.5, 2.5, 5.0, 2.5, 5.0, 3.0, 4.0, 5.0, 3.5]          # с, 2–5
const NOTICE_DISTANCE := 3.0
const RELEASE_DISTANCE := 4.0
const STARE_SECONDS := 2.0
const BLOCK_DISTANCE := 1.5
const BODY_LAYER := 4          # Car
const BODY_RADIUS := 0.35
const BODY_HEIGHT := 1.7
const LADA_MARGIN := 0.1       # м сверх габарита «Лады» и радиуса тела — касание
const LADA_CLEAR := 1.0        # м от габарита «Лады» до точки, куда встаёт житель
const LADA_LOOKAHEAD := 0.9    # м впереди по ходу: «Лада» там — разворот
const REVERSE_COOLDOWN := 2.0
# CITY-01 (часть P)
const SEED := 2910
const SMOKE_SECONDS := Vector2(40.0, 60.0)       # перекур у подъезда
const SMOKE_TURN_SECONDS := Vector2(3.0, 7.0)    # раз в столько курящий поворачивается
const GLANCE_SECONDS := 2.0                      # оглянуться на гудок или «Ладу»
const HORN_RADIUS := 20.0
const LADA_REACT_DISTANCE := 5.0
const BUBBLE_SECONDS := 2.0
const BUBBLE_COOLDOWN := 20.0
const BUBBLE_TIP_Y := 2.1                        # кончик хвостика — над шапкой (рост жителей 1,35–1,83 м)
const STOP_CATCH_DISTANCE := 8.0                 # пассажир ближе к месту ожидания — успевает на троллейбус
const BOARD_SPEED_FACTOR := 1.3                  # к двери — быстрым шагом
const DOOR_OUT := 0.45                           # м от борта: где пассажир исчезает и появляется
const CURB_BACK := 3.0                           # м от двери к тротуару: первая точка пути к двери
const BUS_CLEAR_DISTANCE := 14.0                 # троллейбус отъехал на столько — можно переходить улицу за ним
const CROSS_CLEAR := 12.0                        # м от середины перехода до ближайшей машины кольца — можно идти
## Двери троллейбуса в осях Trolleybus (перед −Z, двери +X): z передней, средней и задней (trolleybus.gd, _build_visual).
const DOOR_Z: Array[float] = [-4.1, -0.2, 4.05]
# Пузыри — как у QuestFlow (_build_bubble/_bubble_texture): бумага, чернильная кайма, хвостик вниз-влево, шрифт интерфейса.
const PAPER := Color(0.93, 0.87, 0.72)
const INK := Color(0.12, 0.10, 0.08)
const BUBBLE_FONT := 80
const BUBBLE_PIXEL := 0.0035
const BUBBLE_PAD := 34.0
const BUBBLE_TAIL := 56.0
const BUBBLE_DOWNSCALE := 2.0

@export var index := 0
var route: Array = []          # Vector3, замкнутая ломаная
var pause_points: Array = []   # индексы точек с паузой
var start_point := 0
var speed := 1.3
var pause_seconds := 3.0
## Илюша и «Лада» — задаёт Residents (в отдельном тесте могут быть null).
var player: Node3D
var lada: Node3D

var body: AnimatableBody3D
var state: StringName = &"walk"    # walk, pause, stare
var target_point := 0
var direction := 1
var distance_walked := 0.0
var stare_count := 0
var lada_bumps := 0
var turnarounds := 0
var _wait := 0.0
var _resume_state: StringName = &"walk"
var _resume_wait := 0.0
var _met := false
var _reverse_cooldown := 0.0

# CITY-01 (часть P): роли (задаёт Residents до add_child) и состояние.
var leader: Resident               # второй в паре: его двигает leader
var follower: Resident             # первый в паре: двигает второго
var follow_offset := Vector3.ZERO  # второй = первый + сдвиг (XZ)
var smoke_point := -1              # точка маршрута, где курит
var smoke_partner: Resident
var rider := false
var wait_point := -1               # точка маршрута, где пассажир ждёт троллейбус
var trolley: Node3D                # Trolleybus (может не быть — тогда ожидание = обычная пауза)
var rng := RandomNumberGenerator.new()
var hidden := false                # в троллейбусе или в магазине
var glance_count := 0
var bubble_times: Array[float] = []
var bubble_text := ""
var events: Array = []             # пассажир: [время, &"board" / &"alight", остановка]
var clock := 0.0
var _bubble_left := 0.0
var _bubble_ready_at := 0.0
var _bubble_back: Sprite3D
var _bubble_label: Label3D
var _last_line := -1
var _turn_left := 0.0
var _transit: Array = []
var _transit_i := 0
var _transit_end: StringName = &""
var _transit_body_from := 0
var _transit_speed := 1.3
var _transit_yield_leg := -1
static var _bubble_cache := {}     # текст → ImageTexture

func setup(resident_index: int, points: Array, pauses: Array, start: int) -> void:
	index = resident_index
	route = points
	pause_points = pauses
	start_point = start
	speed = SPEEDS[index % SPEEDS.size()]
	pause_seconds = PAUSES[index % PAUSES.size()]
	interaction_id = StringName("resident_%d" % index)   # только для фазы дыхания npc.gd; зона E выключена
	rng.seed = SEED + index * 7919

func _ready() -> void:
	solid = false   # своё тело ниже: не StaticBody на слое World, как у npc.gd
	body_radius = BODY_RADIUS
	if not route.is_empty():
		position = _flat(route[start_point])
		target_point = _wrap(start_point + 1)
		facing_yaw = _yaw_to(route[target_point])
	super()
	interactable.enabled = false
	interactable.prompt = ""
	interactable.monitorable = false
	body = AnimatableBody3D.new()
	body.name = "Body"
	body.collision_layer = BODY_LAYER
	body.collision_mask = 0
	body.sync_to_physics = false
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = BODY_HEIGHT * 0.5
	body.add_child(collider)
	add_child(body)
	if smoke_point == start_point and not route.is_empty():
		_start_smoke()

func _physics_process(delta: float) -> void:
	if route.size() < 2 or delta <= 0.0:
		return
	clock += delta
	_tick_bubble(delta)
	if hidden:
		return   # в троллейбусе или в магазине: ждёт doors_opened
	_react_to_lada()
	if leader != null:
		return   # второй в паре: его ставит первый (_mirror)
	_tick(delta)
	if follower != null:
		follower._mirror(self)

func _tick(delta: float) -> void:
	_reverse_cooldown = maxf(_reverse_cooldown - delta, 0.0)
	if state == &"alight":
		_tick_alight()
		return
	if state == &"board" or state == &"transit":
		_tick_transit(delta)
		return
	if _lada_touches_pair(global_position, LADA_MARGIN):
		_dodge_lada()
		return
	var to_player := _player_distance()
	if to_player > RELEASE_DISTANCE:
		_met = false
	if state == &"stare":
		_wait -= delta
		if _wait <= 0.0:
			_met = true
			stop_looking()
			state = _resume_state
			_wait = _resume_wait
		return
	if to_player < NOTICE_DISTANCE and not _met:
		if state != &"glance":   # из оглядки — вернуться туда, откуда оглядывался
			_resume_state = state
			_resume_wait = _wait
		state = &"stare"
		_wait = STARE_SECONDS
		stare_count += 1
		look_at_target(player)
		return
	if state == &"glance":
		_wait -= delta
		if _wait <= 0.0:
			stop_looking()
			state = _resume_state
			_wait = _resume_wait
		return
	if state == &"pause":
		_wait -= delta
		if _wait <= 0.0:
			state = &"walk"
			target_point = _wrap(target_point + direction)
		return
	if state == &"smoke":
		_wait -= delta
		_turn_left -= delta
		if _turn_left <= 0.0:
			_turn_left = rng.randf_range(SMOKE_TURN_SECONDS.x, SMOKE_TURN_SECONDS.y)
			facing_yaw = _smoke_yaw()
		if _wait <= 0.0:
			state = &"walk"
			target_point = _wrap(target_point + direction)
		return
	if state == &"wait_trolley":
		return   # уходит только по doors_opened (on_doors_opened)
	_walk(delta, to_player)

func _walk(delta: float, to_player: float) -> void:
	var here := _flat(global_position)
	var goal := _flat(route[target_point])
	var to := goal - here
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else Vector3.ZERO
	if dir != Vector3.ZERO:
		facing_yaw = atan2(-dir.x, -dir.z)
	# Илюша прямо по ходу: стоим и смотрим, пока не отойдёт (он обходит, житель в него не входит).
	if to_player < BLOCK_DISTANCE and dir != Vector3.ZERO and _player_in_way(dir):
		look_at_target(player)
		return
	if _look_target == player and to_player >= BLOCK_DISTANCE:
		stop_looking()
	# «Лада» стоит поперёк пути: разворот к предыдущей точке.
	if dir != Vector3.ZERO and _lada_touches_pair(here + dir * LADA_LOOKAHEAD, LADA_MARGIN):
		if _reverse_cooldown <= 0.0:
			direction = -direction
			target_point = _wrap(target_point + direction)
			_reverse_cooldown = REVERSE_COOLDOWN
			turnarounds += 1
		return
	var step := speed * delta
	if dist <= step:
		global_position = goal
		distance_walked += dist
		if target_point == smoke_point:
			_start_smoke()
		elif target_point == wait_point and rider and is_instance_valid(trolley):
			state = &"wait_trolley"
			facing_yaw = _yaw_to(trolley_from())
		elif pause_points.has(target_point):
			state = &"pause"
			_wait = pause_seconds
		else:
			target_point = _wrap(target_point + direction)
		return
	global_position = here + dir * step
	distance_walked += step

## Поставить на точку маршрута (касание «Лады», перезапуск): без скорости и без интерполяции рывка.
func place(point: Vector3) -> void:
	global_position = _flat(point)
	reset_physics_interpolation()

## Перезапуск: на старт, к следующей точке, счётчики — с нуля.
func reset_to_start() -> void:
	state = &"walk"
	direction = 1
	_met = false
	_wait = 0.0
	_reverse_cooldown = 0.0
	stop_looking()
	target_point = _wrap(start_point + 1)
	place(route[start_point])
	facing_yaw = _yaw_to(route[target_point])
	distance_walked = 0.0
	rng.seed = SEED + index * 7919
	_show()
	_transit.clear()
	events.clear()
	glance_count = 0
	bubble_times.clear()
	bubble_text = ""
	_bubble_left = 0.0
	_bubble_ready_at = clock
	_last_line = -1
	if _bubble_back:
		_bubble_back.visible = false
	if smoke_point == start_point:
		_start_smoke()
	if follower != null:
		follower._mirror(self)

## Длина замкнутого маршрута, м.
func loop_length() -> float:
	var total := 0.0
	for i in route.size():
		total += _flat(route[i]).distance_to(_flat(route[_wrap(i + 1)]))
	return total

## «Лада» задела: на ближайшую точку маршрута (шаг 0,5 м), свободную от её габарита на LADA_CLEAR, и дальше — от неё.
func _dodge_lada() -> void:
	var here := _flat(global_position)
	var best := Vector3.INF
	var best_d := INF
	var best_seg := -1
	for k in route.size():
		var a := _flat(route[k])
		var b := _flat(route[_wrap(k + 1)])
		var n := maxi(1, ceili(a.distance_to(b) / 0.5))
		for j in n + 1:
			var p := a.lerp(b, float(j) / n)
			if _lada_touches_pair(p, LADA_CLEAR):
				continue
			var d := p.distance_to(here)
			if d < best_d:
				best_d = d
				best = p
				best_seg = k
	lada_bumps += 1
	stop_looking()
	state = &"walk"
	if best_seg < 0:
		direction = 1
		target_point = _wrap(start_point + 1)
		place(route[start_point])
		return
	place(best)
	var away := best - _flat(lada.global_position)
	if (_flat(route[_wrap(best_seg + 1)]) - best).dot(away) >= 0.0:
		direction = 1
		target_point = _wrap(best_seg + 1)
	else:
		direction = -1
		target_point = best_seg

## Точка p (XZ) ближе margin + BODY_RADIUS к габариту «Лады».
func _lada_touches(p: Vector3, margin: float) -> bool:
	if not is_instance_valid(lada):
		return false
	var local := lada.global_transform.affine_inverse() * Vector3(p.x, lada.global_position.y, p.z)
	var half := Lada.SIZE * 0.5
	return absf(local.x) < half.x + BODY_RADIUS + margin and absf(local.z) < half.z + BODY_RADIUS + margin

## До Илюши; у первого в паре — до ближнего из двоих.
func _player_distance() -> float:
	if not is_instance_valid(player) or not player.is_visible_in_tree():
		return INF
	var p := player.global_position
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	if follower != null:
		var f := global_position + follow_offset
		d = minf(d, Vector2(p.x - f.x, p.z - f.z).length())
	return d

## Илюша прямо по ходу (dir) у жителя или у второго в паре — ближе BLOCK_DISTANCE.
func _player_in_way(dir: Vector3) -> bool:
	var spots: Array[Vector3] = [_flat(global_position)]
	if follower != null:
		spots.append(_flat(global_position + follow_offset))
	for here in spots:
		var to_him := _flat(player.global_position) - here
		if to_him.length() < BLOCK_DISTANCE and (to_him.length() < 0.01 or dir.dot(to_him.normalized()) > 0.3):
			return true
	return false

## Точка p (XZ) или место второго в паре при первом в p — касается «Лады».
func _lada_touches_pair(p: Vector3, margin: float) -> bool:
	return _lada_touches(p, margin) or (follower != null and _lada_touches(p + follow_offset, margin))

func _wrap(i: int) -> int:
	return posmod(i, route.size())

func _yaw_to(point: Vector3) -> float:
	var to := _flat(point) - _flat(position)
	return atan2(-to.x, -to.z) if to.length() > 0.001 else facing_yaw

static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)

# =====================================================================================
# CITY-01 (часть P): пары, перекур, троллейбус, реакции, пузыри
# =====================================================================================

## Второй в паре: место первого + сдвиг, то же состояние, тот же взгляд.
func _mirror(lead: Resident) -> void:
	global_position = _flat(lead.global_position) + Vector3(follow_offset.x, 0.0, follow_offset.z)
	state = lead.state
	direction = lead.direction
	target_point = lead.target_point
	facing_yaw = lead.facing_yaw
	_look_target = lead._look_target
	distance_walked = lead.distance_walked
	stare_count = lead.stare_count
	lada_bumps = lead.lada_bumps
	turnarounds = lead.turnarounds

func _start_smoke() -> void:
	state = &"smoke"
	target_point = smoke_point   # стоит на ней; после перекура — к следующей (и со старта тоже)
	_wait = rng.randf_range(SMOKE_SECONDS.x, SMOKE_SECONDS.y)
	_turn_left = rng.randf_range(SMOKE_TURN_SECONDS.x, SMOKE_TURN_SECONDS.y)
	facing_yaw = _smoke_yaw()

## Куда смотрит курящий: на напарника, если тот тоже курит (чаще), во двор, на дверь, вдоль дома; не туда же, где был.
func _smoke_yaw() -> float:
	var options: Array[float] = [PI, PI * 0.5, -PI * 0.5]
	if is_instance_valid(smoke_partner) and smoke_partner.state == &"smoke" and not smoke_partner.hidden:
		var to := _flat(smoke_partner.global_position) - _flat(global_position)
		if to.length() > 0.1:
			options.append(atan2(-to.x, -to.z))
			options.append(atan2(-to.x, -to.z))
	var yaw := facing_yaw
	for attempt in 4:
		yaw = options[rng.randi_range(0, options.size() - 1)] + rng.randf_range(-0.25, 0.25)
		if absf(angle_difference(yaw, facing_yaw)) > 0.5:
			break
	return yaw

## Оглянуться на target (гудок, «Лада») на seconds: остановиться и смотреть, потом дальше. Второй в паре — через первого.
func glance_at(target: Node3D, seconds := GLANCE_SECONDS) -> bool:
	if leader != null:
		return leader.glance_at(target, seconds)
	if hidden or not state in [&"walk", &"pause", &"smoke", &"wait_trolley", &"glance"]:
		return false
	if state != &"glance":
		_resume_state = state
		_resume_wait = _wait
	state = &"glance"
	_wait = seconds
	look_at_target(target)
	glance_count += 1
	if follower != null:
		follower._mirror(self)
	return true

## «Лада» с водителем ближе LADA_REACT_DISTANCE: пузырь-реплика и взгляд на неё; не чаще BUBBLE_COOLDOWN.
func _react_to_lada() -> void:
	if not is_instance_valid(lada) or lada.get("driver") == null or clock < _bubble_ready_at:
		return
	var to := lada.global_position - global_position
	if Vector2(to.x, to.z).length() > LADA_REACT_DISTANCE:
		return
	_bubble_ready_at = clock + BUBBLE_COOLDOWN
	var lines: Array = QuestLines.RESIDENT_LINES
	var i := rng.randi_range(0, lines.size() - 1)
	if i == _last_line:
		i = (i + 1) % lines.size()
	_last_line = i
	say(lines[i])
	glance_at(lada)

## Пузырь над головой на BUBBLE_SECONDS.
func say(text: String) -> void:
	if _bubble_back == null:
		_bubble_back = Sprite3D.new()
		_bubble_back.name = "BubbleBack"
		_bubble_back.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble_back.no_depth_test = true
		_bubble_back.shaded = false
		_bubble_back.pixel_size = BUBBLE_PIXEL * BUBBLE_DOWNSCALE
		_bubble_back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		_bubble_back.render_priority = 1
		add_child(_bubble_back)
		_bubble_label = Label3D.new()
		_bubble_label.name = "Bubble"
		_bubble_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble_label.no_depth_test = true
		_bubble_label.pixel_size = BUBBLE_PIXEL
		_bubble_label.font = DialogPanelScript.ui_font()
		_bubble_label.font_size = BUBBLE_FONT
		_bubble_label.outline_size = 0
		_bubble_label.modulate = INK
		_bubble_label.render_priority = 2
		_bubble_label.position = Vector3(0, BUBBLE_TAIL * 0.5 * BUBBLE_PIXEL, 0)   # в середине тела пузыря, над хвостиком
		_bubble_back.add_child(_bubble_label)
	_bubble_back.texture = bubble_texture(text)
	_bubble_back.position = Vector3(0, BUBBLE_TIP_Y + _bubble_back.texture.get_height() * _bubble_back.pixel_size * 0.5, 0)
	_bubble_label.text = text
	_bubble_back.visible = true
	_bubble_left = BUBBLE_SECONDS
	bubble_text = text
	bubble_times.append(clock)

func bubble_visible() -> bool:
	return _bubble_back != null and _bubble_back.visible and is_visible_in_tree()

func _tick_bubble(delta: float) -> void:
	if _bubble_left <= 0.0:
		return
	_bubble_left -= delta
	if _bubble_left <= 0.0 and _bubble_back:
		_bubble_back.visible = false

## Подложка пузыря с хвостиком — один раз на текст (рисуется по пикселям, как QuestFlow._bubble_texture).
static func bubble_texture(text: String) -> ImageTexture:
	if _bubble_cache.has(text):
		return _bubble_cache[text]
	var font := DialogPanelScript.ui_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT)
	var k := 1.0 / BUBBLE_DOWNSCALE
	var body_size := Vector2(text_size.x + 2.0 * BUBBLE_PAD, text_size.y + 2.0 * BUBBLE_PAD) * k
	var tail := BUBBLE_TAIL * k
	var w := int(ceil(body_size.x)) + 4
	var h := int(ceil(body_size.y + tail)) + 4
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var radius := 14.0 * k
	var border := 7.0 * k
	var half := body_size * 0.5
	var center := Vector2(w * 0.5, 2.0 + half.y)
	var t0 := Vector2(center.x - body_size.x * 0.16, center.y + half.y - border)
	var t1 := Vector2(center.x - body_size.x * 0.02, center.y + half.y - border)
	var t2 := Vector2(center.x - body_size.x * 0.22, center.y + half.y + tail - 1.0)
	var tri := PackedVector2Array([t0, t1, t2])
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - center).abs() - half + Vector2(radius, radius)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var in_tail := Geometry2D.is_point_in_polygon(p, tri)
			if d <= -border or (in_tail and d > -border and _tail_inner(p, tri, border)):
				image.set_pixel(x, y, PAPER)
			elif d <= 0.0 or in_tail:
				image.set_pixel(x, y, INK)
	var texture := ImageTexture.create_from_image(image)
	_bubble_cache[text] = texture
	return texture

static func _tail_inner(p: Vector2, tri: PackedVector2Array, border: float) -> bool:
	for edge in [[tri[1], tri[2]], [tri[2], tri[0]]]:
		if Geometry2D.get_closest_point_to_segment(p, edge[0], edge[1]).distance_to(p) < border:
			return false
	return true

# --- троллейбус (пассажир) ---

## Откуда приходит троллейбус к месту ожидания — туда смотрит ждущий (на 20 м назад по ходу от остановки A — восток).
func trolley_from() -> Vector3:
	return _flat(route[wait_point]) + Vector3(20.0, 0.0, 0.0)

## Точка у двери door (0 — передняя, 1 — средняя, 2 — задняя) снаружи борта, на земле.
static func door_point(bus: Node3D, door: int) -> Vector3:
	var local := Vector3(Trolleybus.BODY.z * 0.5 + DOOR_OUT, 0.0, DOOR_Z[door])
	return _flat(bus.global_transform * local)

func on_doors_opened(stop: int) -> void:
	if not rider or not is_instance_valid(trolley):
		return
	if stop == 0 and state == &"shop":
		_alight(0)
	elif stop == 0 and _wants_bus():
		_board()
	elif stop == 1 and state == &"ride":
		_alight(1)

func on_doors_closed(stop: int) -> void:
	if rider and stop == 0 and state == &"board":
		_hide(&"ride")   # не дошёл пару шагов — запрыгнул
		events.append([clock, &"board", 0])

func _wants_bus() -> bool:
	if hidden or wait_point < 0:
		return false
	if state == &"wait_trolley":
		return true
	return state in [&"walk", &"pause", &"glance", &"stare"] \
		and _flat(global_position).distance_to(_flat(route[wait_point])) <= STOP_CATCH_DISTANCE

## К ближайшей двери: с тротуара напротив неё — в дверь, там исчезает.
func _board() -> void:
	var best := 0
	for door in DOOR_Z.size():
		if door_point(trolley, door).distance_to(_flat(global_position)) < door_point(trolley, best).distance_to(_flat(global_position)):
			best = door
	var door_at := door_point(trolley, best)
	var out := _flat(trolley.global_transform.basis.x).normalized()
	stop_looking()
	_start_transit([door_at + out * CURB_BACK, door_at], &"ride", 0, speed * BOARD_SPEED_FACTOR)
	state = &"board"

## Выйти на остановке stop: B — из передней двери, ждать, пока троллейбус отъедет, перейти улицу и уйти в «ГАСТРОНОМ»;
## A — из задней двери на тротуар и обратно на маршрут.
func _alight(stop: int) -> void:
	var door_at := door_point(trolley, 0 if stop == 1 else 2)
	var out := _flat(trolley.global_transform.basis.x).normalized()
	_show()
	place(door_at)
	facing_yaw = atan2(-out.x, -out.z)
	events.append([clock, &"alight", stop])
	if stop == 1:
		body.collision_layer = 0   # у края парковки KIOSK_ZONE: тело выключено, пока не перешёл к первой точке пути
		state = &"alight"
		return
	_start_transit([door_at + out * CURB_BACK, _flat(route[0])], &"route", 0, speed)
	state = &"transit"

func _tick_alight() -> void:
	if trolley.get("doors_open") or _flat(trolley.global_position).distance_to(_flat(global_position)) < BUS_CLEAR_DISTANCE:
		return
	var path: Array = []
	for p in Layout.RESIDENT_RIDER_B_PATH:
		path.append(_flat(p))
	_start_transit(path, &"shop", 1, speed, 1)
	body.collision_layer = 0
	state = &"transit"

## yield_leg — отрезок через проезжую часть: перед ним на бордюре ждать, пока машины кольца не дальше CROSS_CLEAR от его
## середины; начав переход, не останавливаться (машины тормозят перед телом на слое Car — иначе оба ждали бы друг друга).
func _start_transit(points: Array, end: StringName, body_from: int, walk_speed: float, yield_leg := -1) -> void:
	_transit_yield_leg = yield_leg
	_transit = points
	_transit_i = 0
	_transit_end = end
	_transit_body_from = body_from
	_transit_speed = walk_speed
	body.collision_layer = BODY_LAYER if body_from <= 0 else 0

func _tick_transit(delta: float) -> void:
	var here := _flat(global_position)
	var goal: Vector3 = _transit[_transit_i]
	var to := goal - here
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else Vector3.ZERO
	if dir != Vector3.ZERO:
		facing_yaw = atan2(-dir.x, -dir.z)
	if is_instance_valid(player) and _player_distance() < BLOCK_DISTANCE and dir != Vector3.ZERO and _player_in_way(dir):
		look_at_target(player)
		return
	if _look_target == player:
		stop_looking()
	if _transit_i == _transit_yield_leg and here.distance_to(_flat(_transit[_transit_i - 1])) < 0.01:
		var middle := here.lerp(goal, 0.5)
		for vehicle in get_tree().get_nodes_in_group(PathVehicle.GROUP):
			if _flat(vehicle.global_position).distance_to(middle) < CROSS_CLEAR:
				return
	var step := _transit_speed * delta
	if dist > step:
		global_position = here + dir * step
		return
	global_position = goal
	_transit_i += 1
	if _transit_i >= _transit_body_from:
		body.collision_layer = BODY_LAYER
	if _transit_i < _transit.size():
		return
	match _transit_end:
		&"ride":
			_hide(&"ride")
			events.append([clock, &"board", 0])
		&"shop":
			_hide(&"shop")
		_:
			state = &"walk"
			direction = 1
			target_point = _wrap(1)

func _hide(next_state: StringName) -> void:
	hidden = true
	visible = false
	body.collision_layer = 0
	stop_looking()
	state = next_state
	_bubble_left = 0.0
	if _bubble_back:
		_bubble_back.visible = false

func _show() -> void:
	hidden = false
	visible = true
	if body:
		body.collision_layer = BODY_LAYER
