class_name CameraRig
extends Node3D
## C4 — камера от третьего лица на SpringArm3D. Мышь крутит yaw/pitch, когда курсор захвачен.
## Профиль in_car использует DRIVE-01.

## Кадр по замеру эталона PLAY-01 (G02) и концептам 01, 04, 05: камера ближе и ниже, FOV 55°,
## в машине FOV растёт со скоростью (до +6°), пешком камера сама доворачивает за Илюшей (PLAY-02).
const PROFILES := {
	&"on_foot": {"distance": 4.3, "height": 1.9, "pitch": -0.17, "fov": 55.0},
	&"in_car": {"distance": 5.2, "height": 1.5, "pitch": -0.18, "fov": 55.0},   # «Лада» крупнее, к концепту 05 (итоговая сверка PLAY-02)
}
const FOV_PER_SPEED := 0.16     # градусов на м/с в машине
const FOV_SPEED_MAX := 6.0
const FOV_SHARPNESS := 4.0
const AUTO_FOLLOW_IDLE := 1.0   # с без мыши — камера начинает доворачивать за Илюшей
const AUTO_FOLLOW_RATE := 2.2   # 1/с
const AUTO_FOLLOW_MAX := 2.2    # рад: при ходьбе на камеру (разворот больше) не доворачивать
const PITCH_MIN := -1.1
const PITCH_MAX := 0.35
const FOLLOW_SHARPNESS := 14.0
const CHASE_SHARPNESS := 3.0

@export var mouse_sensitivity := 0.0025

var target: Node3D
var profile: StringName = &"on_foot"
## Любое присваивание yaw снаружи (мышь, сцена, тесты) переносит и input_yaw — опору ходьбы.
## Автодоводка меняет только yaw: пока нажаты те же клавиши, Илюша идёт прежним курсом и не закручивается
## по спирали; при смене клавиш он берёт новый yaw (sync_input_yaw).
var yaw := 0.0:
	set(value):
		yaw = value
		input_yaw = value
var input_yaw := 0.0
## Курс, за которым доворачивает камера пешком (Ilyusha задаёт его по взгляду), и скорость цели.
var follow_heading := 0.0
var follow_speed := 0.0
var _mouse_idle := 0.0
var pitch := -0.30
var arm: SpringArm3D
var camera: Camera3D
var permanent_exclusions: Array[RID] = []
## Плечевое смещение вправо, м: на время диалога камера уходит вбок, чтобы собеседник
## за спиной Илюши был виден (кадр 07). Меняется плавно.
var shoulder := 0.0
var _shoulder_now := 0.0
const SHOULDER_SHARPNESS := 5.0
## Пешком на время диалога (shoulder > 0) камера ближе: собеседник с 25–27 % высоты кадра становится ≈30 %,
## как Бабка на концепте 03 (LOOK-01: кадры диалога builds/screenshots/LOOK-01/).
const TALK_DISTANCE := 3.4
## POLISH-03 A: на время диалога пешком камера поворачивается к говорящему (кадр 07: окно киоска и продавщица в кадре,
## Илюша слева со спины), после — возвращается к прежнему взгляду. Поворот — один, за фиксированное время с плавным
## разгоном и торможением (smoothstep), цель считается один раз при открытии: так нет рывка на старте и «дотягивания».
## План проверяет обзор сферой пружины (как SpringArm3D): плечо, угол и путь поворота без стен; если справа тесно —
## плечо слева, затем сдвиг угла, затем камера выше. Любая запись yaw снаружи (мышь, стик, сцена, тесты) снимает и
## поворот, и возврат; первый шаг после диалога снимает возврат.
const TALK_PITCH := -0.10        # почти горизонтально: окно и собеседник над панелью диалога
const TALK_PITCH_HIGH := -0.38   # запасной: камера выше, над низкими преградами
const TALK_SPEAKER_ANGLE := 0.2  # рад: собеседник правее оси кадра (Илюша — левее, на atan(плечо / дистанция))
const TALK_AIM_HEIGHT := 1.3     # м над землёй собеседника
const TALK_TURN_MIN := 0.55      # с на поворот: от TALK_TURN_MIN до TALK_TURN_MAX по величине угла
const TALK_TURN_MAX := 1.1
const TALK_CLEAR := 0.95         # доля свободного хода сферы пружины, которой довольно
var talk_focus := Vector3.INF    # INF — нет собеседника
var _return_active := false
var _saved_yaw := 0.0
var _saved_pitch := 0.0
var _focus_written := NAN        # последнее значение yaw, записанное поворотом/возвратом
var _talk_from := Vector2.ZERO   # (yaw, pitch) в начале поворота или возврата
var _talk_goal := Vector2.ZERO   # (yaw, pitch) цели
var _talk_t := 0.0
var _talk_time := TALK_TURN_MIN
var _talk_planned := false
var talk_side := 1.0             # 1 — плечо справа, −1 — слева (справа тесно)
var _talk_from_arm := Vector2.ZERO   # (плечо, длина пружины) в начале поворота
var _talk_arm := 0.0                 # сглаженная длина пружины на время поворота
const ARM_MASK := 1                  # World — как у пружины вне диалога
const ARM_PULL_RATE := 18.0          # 1/с: к препятствию
const ARM_RELEASE_RATE := 4.0        # 1/с: от препятствия
func _ready() -> void:
	arm = SpringArm3D.new()
	arm.name = "Arm"
	arm.collision_mask = ARM_MASK  # только World
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	arm.shape = sphere
	add_child(arm)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = PROFILES[&"on_foot"]["fov"]
	camera.current = true
	arm.add_child(camera)

## instant = false: камера встаёт за новой целью сразу, а дистанция плавно меняется до профиля.
func follow(new_target: Node3D, new_profile: StringName = &"on_foot", instant := true) -> void:
	talk_focus = Vector3.INF
	_return_active = false
	target = new_target
	profile = new_profile
	pitch = PROFILES[profile]["pitch"]
	arm.clear_excluded_objects()
	for rid in permanent_exclusions:
		arm.add_excluded_object(rid)
	if target is CollisionObject3D:
		arm.add_excluded_object(target.get_rid())
	snap(instant)

## Тела, которые не должны притягивать камеру (NPC рядом с героем).
func exclude_permanently(rid: RID) -> void:
	permanent_exclusions.append(rid)
	arm.add_excluded_object(rid)

## Мгновенно поставить камеру за целью, без сглаживания.
func snap(with_distance := true) -> void:
	if target:
		global_position = _goal()
		if with_distance:
			arm.spring_length = PROFILES[profile]["distance"]
			camera.fov = PROFILES[profile]["fov"]
		rotation = Vector3(pitch, yaw, 0.0)
		reset_physics_interpolation()

## Камера движется в физическом кадре вместе с целью; плавность между кадрами даёт интерполяция физики.
const STICK_LOOK_SPEED := 2.6   # рад/с при полном отклонении правого стика

func _physics_process(delta: float) -> void:
	if not target:
		return
	# Правый стик геймпада — как мышь (решение владельца 28.10.2026, вечер).
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick.length_squared() > 0.04 and profile != &"in_car":
		apply_mouse(stick * STICK_LOOK_SPEED * delta / mouse_sensitivity)
	global_position = global_position.lerp(_goal(), 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	if _update_talk(delta):
		pass   # POLISH-03 A: поворот к собеседнику или возврат ведёт yaw сам
	elif profile == &"in_car":
		# Камера преследования: плавно встаёт за машиной по её курсу.
		yaw = lerp_angle(yaw, target.global_rotation.y, 1.0 - exp(-CHASE_SHARPNESS * delta))
	elif follow_speed > 0.2:
		_mouse_idle += delta
		var diff := wrapf(follow_heading - yaw, -PI, PI)
		if _mouse_idle >= AUTO_FOLLOW_IDLE and absf(diff) < AUTO_FOLLOW_MAX:
			var keep := input_yaw
			yaw = yaw + diff * (1.0 - exp(-AUTO_FOLLOW_RATE * delta))
			input_yaw = keep
	else:
		_mouse_idle += delta
	var fov: float = PROFILES[profile]["fov"]
	if profile == &"in_car" and target is Lada:
		fov += minf(FOV_PER_SPEED * (target as Lada).speed_kmh() / 3.6, FOV_SPEED_MAX)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-FOV_SHARPNESS * delta))
	var distance: float = PROFILES[profile]["distance"]
	if shoulder > 0.0 and profile == &"on_foot":
		distance = TALK_DISTANCE
	if is_talk_framing() and _talk_planned:
		# Плечо и дистанция — тем же плавным ходом, что и угол: экспонента стартует рывком (POLISH-03 A). Столкновение
		# пружины — своё и сглаженное: SpringArm3D ставит камеру на точку удара мгновенно, и у стены подъезда или киоска
		# камера на повороте прыгала туда-сюда. Подтягивается к препятствию быстро, отходит медленно.
		var k := smoothstep(0.0, 1.0, _talk_t)
		_shoulder_now = lerpf(_talk_from_arm.x, shoulder * talk_side, k)
		var want := lerpf(_talk_from_arm.y, distance, k)
		var pivot := global_position
		var back := Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0.0, 0.0, want)
		var free := want * _free_fraction(pivot, pivot + back)
		var rate := ARM_PULL_RATE if free < _talk_arm else ARM_RELEASE_RATE
		_talk_arm = lerpf(_talk_arm, free, 1.0 - exp(-rate * delta))
		arm.collision_mask = 0
		arm.spring_length = _talk_arm
	else:
		arm.collision_mask = ARM_MASK
		arm.spring_length = lerpf(arm.spring_length, distance, 1.0 - exp(-4.0 * delta))
		_shoulder_now = lerpf(_shoulder_now, shoulder * talk_side, 1.0 - exp(-SHOULDER_SHARPNESS * delta))
	rotation = Vector3(pitch, yaw, 0.0)

## POLISH-03 A (владелец: камера у Бабки и продавщицы дёргается): при захвате мыши после диалога ОС переносит курсор
## в центр и присылает движение на сотни пикселей — оно рвало камеру и снимало плавный возврат. Первые MOUSE_SETTLE с
## после смены режима мыши и одиночные скачки больше MOUSE_JUMP_PX не считаются движением.
const MOUSE_SETTLE := 0.12
const MOUSE_JUMP_PX := 250.0
var _mouse_mode_seen := -1
var _mouse_settle_until := 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_watch_mouse_mode()
		if Time.get_ticks_msec() < _mouse_settle_until or event.relative.length() > MOUSE_JUMP_PX:
			return
		apply_mouse(event.relative)

func _process(_delta: float) -> void:
	_watch_mouse_mode()

func _watch_mouse_mode() -> void:
	if Input.mouse_mode != _mouse_mode_seen:
		_mouse_mode_seen = Input.mouse_mode
		_mouse_settle_until = Time.get_ticks_msec() + int(MOUSE_SETTLE * 1000.0)

## POLISH-03 A: повернуться к собеседнику в точке point (пешком; прежний взгляд запоминается для возврата).
## План (угол, наклон, сторона плеча) — в первом физкадре: там доступен запрос к пространству физики.
func focus_talk(point: Vector3) -> void:
	if profile != &"on_foot" or target == null:
		return
	if talk_focus == Vector3.INF and not _return_active:
		_saved_yaw = yaw
		_saved_pitch = pitch
	talk_focus = point
	_return_active = false
	_talk_planned = false
	_focus_written = yaw

## Диалог закрыт: вернуть прежний взгляд тем же плавным поворотом (если его не перехватили).
func release_talk() -> void:
	if talk_focus == Vector3.INF:
		return
	talk_focus = Vector3.INF
	_return_active = true
	talk_side = 1.0
	_talk_planned = true
	_start_turn(Vector2(_saved_yaw, _saved_pitch))

## Идёт поворот к собеседнику или возврат после диалога.
func is_talk_framing() -> bool:
	return talk_focus != Vector3.INF or _return_active

## Угол yaw, при котором собеседник в point виден на TALK_SPEAKER_ANGLE · side от оси кадра, а Илюша — по другую
## сторону (плечо shoulder · side, дистанция TALK_DISTANCE).
func talk_yaw(point: Vector3, side := 1.0) -> float:
	var p := target.global_position
	var to := point - p
	var y := atan2(-to.x, -to.z)
	for i in 6:
		var fwd := Vector3(-sin(y), 0.0, -cos(y))
		var right := Vector3(cos(y), 0.0, -sin(y))
		var cam := p + right * shoulder * side - fwd * TALK_DISTANCE
		var rel := point - cam
		var angle := atan2(rel.dot(right), rel.dot(fwd))
		y += side * TALK_SPEAKER_ANGLE - angle
	return y

## goal.x — угол без свёртки: поворот идёт ровно на goal.x − yaw (короткой или длинной дугой, как выбрал план).
func _start_turn(goal: Vector2) -> void:
	_talk_from = Vector2(yaw, pitch)
	_talk_from_arm = Vector2(_shoulder_now, arm.get_hit_length())
	_talk_arm = _talk_from_arm.y
	_talk_goal = goal
	_talk_t = 0.0
	_talk_time = lerpf(TALK_TURN_MIN, TALK_TURN_MAX, clampf(absf(goal.x - yaw) / PI, 0.0, 1.0))
	_focus_written = yaw

## Выбрать сторону плеча, угол, наклон и направление дуги, при которых сфера пружины свободно проходит от головы к
## плечу и от плеча к камере в цели и на второй половине пути (начало пути — там, где камера уже стоит). Порядок
## предпочтений: низкий наклон, плечо справа, точный угол, короткая дуга; первый свободный; иначе — самый свободный.
func _plan_talk() -> void:
	var best := Vector3(yaw + angle_difference(yaw, talk_yaw(talk_focus, 1.0)), TALK_PITCH, 1.0)
	var best_score := -1.0
	for pitch_try in [TALK_PITCH, TALK_PITCH_HIGH]:
		for side in [1.0, -1.0]:
			var base := talk_yaw(talk_focus, side)
			for extra in [0.0, 0.2 * side, 0.4 * side]:
				var short_turn := angle_difference(yaw, base + extra)
				for turn in [short_turn, short_turn - signf(short_turn) * TAU]:
					var y: float = yaw + turn
					var score := _talk_clearance(y, pitch_try, side)
					if score > best_score + 0.001:
						best_score = score
						best = Vector3(y, pitch_try, side)
					if score >= TALK_CLEAR:
						_apply_plan(best)
						return
	_apply_plan(best)

func _apply_plan(plan: Vector3) -> void:
	talk_side = plan.z
	_talk_planned = true
	_start_turn(Vector2(plan.x, plan.y))

## Свободный ход 0…1 (минимум по участкам) сферы радиуса пружины: голова → плечо и плечо → камера на конечном угле
## и на половине и трёх четвертях поворота от текущего (goal_yaw без свёртки).
func _talk_clearance(goal_yaw: float, goal_pitch: float, side: float) -> float:
	var head: Vector3 = target.global_position + Vector3.UP * float(PROFILES[profile]["height"])
	var worst := 1.0
	for k in [1.0, 0.75, 0.5]:
		var y := lerpf(yaw, goal_yaw, k)
		var pt := lerpf(pitch, goal_pitch, k)
		var right := Vector3(cos(y), 0.0, -sin(y))
		var pivot: Vector3 = head + right * shoulder * side
		var back := Basis.from_euler(Vector3(pt, y, 0.0)) * Vector3(0.0, 0.0, TALK_DISTANCE)
		worst = minf(worst, minf(_free_fraction(head, pivot), _free_fraction(pivot, pivot + back)))
	return worst

## Доля свободного хода сферы пружины от from до to по слоям пружины (без Илюши и постоянных исключений).
func _free_fraction(from: Vector3, to: Vector3) -> float:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = arm.shape
	query.transform = Transform3D(Basis(), from)
	query.motion = to - from
	query.collision_mask = ARM_MASK
	var exclude: Array[RID] = permanent_exclusions.duplicate()
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	query.exclude = exclude
	var result := get_world_3d().direct_space_state.cast_motion(query)
	return result[0] if result.size() > 0 else 1.0

func _update_talk(delta: float) -> bool:
	if not is_talk_framing():
		return false
	var walking_off := _return_active and follow_speed > 0.2   # пошёл сразу после диалога — курс не крутить
	if walking_off or profile != &"on_foot" or (not is_nan(_focus_written) and yaw != _focus_written):
		talk_focus = Vector3.INF   # yaw перехвачен (мышь, сцена, тест) или сели в машину — не спорить
		_return_active = false
		talk_side = 1.0
		arm.collision_mask = ARM_MASK
		return false
	if talk_focus != Vector3.INF and not _talk_planned:
		_plan_talk()
	_talk_t = minf(_talk_t + delta / _talk_time, 1.0)
	var k := smoothstep(0.0, 1.0, _talk_t)
	yaw = lerpf(_talk_from.x, _talk_goal.x, k)
	pitch = lerpf(_talk_from.y, _talk_goal.y, k)
	_focus_written = yaw
	if _return_active and _talk_t >= 1.0:
		_return_active = false
		yaw = wrapf(yaw, -PI, PI)
		_focus_written = yaw
	_mouse_idle = 0.0
	return true

## Мышь вправо — камера вправо, мышь вверх — взгляд вверх.
func apply_mouse(relative: Vector2) -> void:
	_mouse_idle = 0.0
	talk_focus = Vector3.INF
	_return_active = false
	yaw = wrapf(yaw - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * mouse_sensitivity, PITCH_MIN, PITCH_MAX)

## Опора ходьбы догоняет камеру: вызывается при смене нажатых клавиш.
func sync_input_yaw() -> void:
	input_yaw = yaw

func _goal() -> Vector3:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return target.global_position + Vector3.UP * PROFILES[profile]["height"] + right * _shoulder_now
