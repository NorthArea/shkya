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
const AUTO_FOLLOW_IDLE := 1.0   # с без мыши и правого стика — ручная камера в приоритете, доводка ждёт паузы
const AUTO_FOLLOW_RATE := 2.2   # 1/с
## POLISH-03 C (критик 30.10, p0105/v05): доводка начинается через AUTO_FOLLOW_DELAY с ходьбы; при ходьбе на камеру
## (разворот больше AUTO_FOLLOW_MAX) камера тоже заводится за спину — позже (TURN_AROUND_DELAY) и в одну сторону,
## выбранную в начале облёта. Угловая скорость не больше AUTO_FOLLOW_SPEED и набирается за AUTO_FOLLOW_RAMP — без рывка.
const AUTO_FOLLOW_DELAY := 0.5  # с ходьбы до начала доводки
const AUTO_FOLLOW_MAX := 2.2    # рад: больше — «идёт на камеру», облёт за спину после TURN_AROUND_DELAY
const TURN_AROUND_DELAY := 0.8  # с ходьбы на камеру до облёта
const AUTO_FOLLOW_SPEED := 2.6  # рад/с: облёт на 180° ≈ 1,4 с
const AUTO_FOLLOW_RAMP := 0.35  # с: разгон угловой скорости доводки от нуля
## Тонкие столбы (фонари в валах, опоры, деревья, таблички) пружина камеры не замечает: за фонарём в валу камера
## впрыгивала к затылку и лицо Илюши занимало пол-экрана (критик 30.10, v05). Порог — по ширине коробки в плане.
const THIN_SOLID := 0.6         # м
## Пружина сжата стеной — камера приподнимается, а не садится в затылок (доля сжатия × значение).
const WALL_LIFT := 0.5          # м
const WALL_TILT := 0.0          # рад: наклон с native collision feedback давал рывки у стены
## Тонкий столб между головой и камерой (пружина его не замечает) — камера объезжает его вбок, не приближаясь:
## сдвиг вдоль «вправо» до DODGE_MAX так, чтобы линия взгляда прошла не ближе DODGE_CLEAR от оси столба.
const DODGE_CLEAR := 0.95       # м (с листовками на столбе — они общей сеткой и не прозрачнеют)
const DODGE_MAX := 1.1          # м
const DODGE_SHARPNESS := 6.0
## Столб ближе POLE_FADE_NEAR к камере (по земле) — полупрозрачный (GeometryInstance3D.transparency), не чёрная полоса.
const POLE_FADE_NEAR := 3.6     # м
const POLE_FADE := 0.75
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
var _ground_y := 0.0   # опора пешей камеры: обновляется на полу, удерживается в прыжке
var _walk_time := 0.0
var _follow_ramp := 0.0
var _swing_sign := 0.0          # сторона облёта при ходьбе на камеру (0 — не облетает)
var _lift := 0.0                # 0…1: сжатие пружины пешком, сглаженное
var _thin := {}                 # RID тонких столбов (exclude_thin_solids) → тело
var _dodge := 0.0               # м: текущий объезд столба вбок
var _faded := {}                # тело столба → его сетки, сейчас полупрозрачные
var pitch := -0.30
var arm: SpringArm3D
var camera: Camera3D
var _arm_path_shape := CapsuleShape3D.new() # кеш сферы, протянутой вдоль фактического плеча
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
var _talk_arm := 0.0                 # фактическая безопасная длина пешей камеры, включая диалог
var _arm_requested := 0.0            # полная длина профиля/поворота до ограничения стеной
const ARM_MASK := 1                  # World — как у пружины вне диалога
const ARM_PULL_RATE := 18.0          # 1/с: к препятствию
const ARM_RELEASE_RATE := 4.0        # 1/с: от препятствия
const ARM_COLLISION_CLEARANCE := 0.05 # м: физический отступ камеры вдоль проверяемого плеча
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
	call_deferred(&"exclude_thin_solids", get_parent())

## instant = false: камера встаёт за новой целью сразу, а дистанция плавно меняется до профиля.
func follow(new_target: Node3D, new_profile: StringName = &"on_foot", instant := true) -> void:
	var requested_before := _arm_requested if profile == &"in_car" else arm.spring_length
	talk_focus = Vector3.INF
	_return_active = false
	target = new_target
	profile = new_profile
	_walk_time = 0.0
	_follow_ramp = 0.0
	_swing_sign = 0.0
	_dodge = 0.0
	_lift = 0.0
	pitch = PROFILES[profile]["pitch"]
	arm.clear_excluded_objects()
	for rid in permanent_exclusions:
		arm.add_excluded_object(rid)
	if target is CollisionObject3D:
		arm.add_excluded_object(target.get_rid())
	snap(instant)
	if not instant:
		_arm_requested = requested_before
	_fade_near_poles()

## Тела, которые не должны притягивать камеру (NPC рядом с героем).
func exclude_permanently(rid: RID) -> void:
	permanent_exclusions.append(rid)
	arm.add_excluded_object(rid)

## Статичные тонкие тела мира (слой World, все формы в плане не шире THIN_SOLID) — в исключения пружины.
func exclude_thin_solids(root: Node) -> void:
	if root == null:
		return
	for body in root.find_children("*", "StaticBody3D", true, false):
		if body is AnimatableBody3D or (body as StaticBody3D).collision_layer & arm.collision_mask == 0:
			continue
		if _is_thin(body):
			exclude_permanently((body as StaticBody3D).get_rid())
			_thin[(body as StaticBody3D).get_rid()] = body

static func _is_thin(body: Node) -> bool:
	var shapes := 0
	for child in body.get_children():
		if not (child is CollisionShape3D):
			continue
		var shape: Shape3D = (child as CollisionShape3D).shape
		shapes += 1
		if shape is BoxShape3D:
			var size: Vector3 = (shape as BoxShape3D).size
			if maxf(size.x, size.z) > THIN_SOLID:
				return false
		elif shape is CylinderShape3D:
			if (shape as CylinderShape3D).radius * 2.0 > THIN_SOLID:
				return false
		elif shape is CapsuleShape3D:
			if (shape as CapsuleShape3D).radius * 2.0 > THIN_SOLID:
				return false
		else:
			return false
	return shapes > 0

## Мгновенно поставить камеру за целью, без сглаживания.
func snap(with_distance := true) -> void:
	if target:
		_ground_y = target.global_position.y
		global_position = _goal()
		if with_distance:
			arm.spring_length = PROFILES[profile]["distance"]
			camera.fov = PROFILES[profile]["fov"]
		_arm_requested = arm.spring_length
		_talk_arm = arm.get_hit_length() if not with_distance and arm.get_hit_length() > 0.0 else arm.spring_length
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
	if profile == &"on_foot" and target is CharacterBody3D and (target as CharacterBody3D).is_on_floor():
		_ground_y = target.global_position.y
	var dodge := _dodge_target() if profile == &"on_foot" and not is_talk_framing() else 0.0
	_dodge = lerpf(_dodge, dodge, 1.0 - exp(-DODGE_SHARPNESS * delta))
	var previous_pivot := global_position
	global_position = global_position.lerp(_goal(), 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	var pivot_offsets_retreated := _resolve_pivot_overlap(previous_pivot)
	var talk_frame := _update_talk(delta)
	if talk_frame:
		# POLISH-03 A ведёт yaw; после диалога отсчёт ходьбы для доводки начинается заново.
		_walk_time = 0.0
		_follow_ramp = 0.0
		_swing_sign = 0.0
	elif profile == &"in_car":
		# Камера преследования: плавно встаёт за машиной по её курсу.
		yaw = lerp_angle(yaw, target.global_rotation.y, 1.0 - exp(-CHASE_SHARPNESS * delta))
	else:
		_mouse_idle += delta
		_auto_follow(delta)
	var fov: float = PROFILES[profile]["fov"]
	if profile == &"in_car" and target is Lada:
		fov += minf(FOV_PER_SPEED * (target as Lada).speed_kmh() / 3.6, FOV_SPEED_MAX)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-FOV_SHARPNESS * delta))
	var distance: float = PROFILES[profile]["distance"]
	if shoulder > 0.0 and profile == &"on_foot":
		distance = TALK_DISTANCE
	var squeeze := 0.0
	if profile == &"on_foot":
		if talk_frame and _talk_planned:
			var k := smoothstep(0.0, 1.0, _talk_t)
			_shoulder_now = lerpf(_talk_from_arm.x, shoulder * talk_side, k)
			_arm_requested = lerpf(_talk_from_arm.y, distance, k)
		else:
			_arm_requested = lerpf(_arm_requested, distance, 1.0 - exp(-4.0 * delta))
			_shoulder_now = lerpf(_shoulder_now, shoulder * talk_side, 1.0 - exp(-SHOULDER_SHARPNESS * delta))
		# Один владелец длины до, во время и после диалога; native World остаётся страховкой.
		var free := _safe_arm_distance(_arm_requested)
		var rate := ARM_PULL_RATE if free < _talk_arm else ARM_RELEASE_RATE
		var smooth := lerpf(_talk_arm, free, 1.0 - exp(-rate * delta))
		_talk_arm = minf(smooth, free) # внутрь стены не сглаживать; выход из сжатия плавный
		arm.collision_mask = ARM_MASK
		arm.spring_length = _talk_arm
		if not talk_frame and _arm_requested > 0.5:
			squeeze = clampf((_arm_requested - free) / _arm_requested, 0.0, 1.0)
	else:
		# Запрос профиля меняется прежним темпом; фактическую длину ограничивает общая проверка.
		_arm_requested = lerpf(_arm_requested, distance, 1.0 - exp(-4.0 * delta))
		arm.collision_mask = ARM_MASK
		arm.spring_length = _safe_arm_distance(_arm_requested)
		_shoulder_now = lerpf(_shoulder_now, shoulder * talk_side, 1.0 - exp(-SHOULDER_SHARPNESS * delta))
		_talk_arm = arm.spring_length
	if pivot_offsets_retreated:
		# _update_talk мог обновить плечо после восстановления pivot; в этом кадре оно уже отступило.
		_shoulder_now = 0.0
		_dodge = 0.0
	_lift = lerpf(_lift, squeeze, 1.0 - exp(-6.0 * delta))
	rotation = Vector3(pitch - _lift * WALL_TILT, yaw, 0.0)
	_fade_near_poles()

## Доводка пешком (PLAY-02, POLISH-03 C): только после паузы ручной камеры и AUTO_FOLLOW_DELAY ходьбы; при ходьбе на
## камеру — облёт за спину после TURN_AROUND_DELAY. Меняет только yaw: курс ходьбы (input_yaw) прежний, пока те же клавиши.
func _auto_follow(delta: float) -> void:
	if follow_speed <= 0.2:
		_walk_time = 0.0
		_follow_ramp = 0.0
		_swing_sign = 0.0
		return
	_walk_time += delta
	var diff := wrapf(follow_heading - yaw, -PI, PI)
	var facing_camera := absf(diff) >= AUTO_FOLLOW_MAX
	if facing_camera and _swing_sign == 0.0:
		_swing_sign = 1.0 if diff >= 0.0 else -1.0
	elif not facing_camera and absf(diff) < AUTO_FOLLOW_MAX - 0.3:
		_swing_sign = 0.0
	if _swing_sign != 0.0 and signf(diff) != _swing_sign:
		diff += TAU * _swing_sign   # у ±π не перекидываться на другую сторону
	var wait := TURN_AROUND_DELAY if _swing_sign != 0.0 else AUTO_FOLLOW_DELAY
	if _mouse_idle < AUTO_FOLLOW_IDLE or _walk_time < wait:
		_follow_ramp = 0.0
		return
	_follow_ramp = minf(_follow_ramp + delta / AUTO_FOLLOW_RAMP, 1.0)
	var ease := _follow_ramp * _follow_ramp * (3.0 - 2.0 * _follow_ramp)
	var step := diff * (1.0 - exp(-AUTO_FOLLOW_RATE * delta))
	step = clampf(step, -AUTO_FOLLOW_SPEED * delta, AUTO_FOLLOW_SPEED * delta) * ease
	var keep := input_yaw
	yaw = wrapf(yaw + step, -PI, PI)
	input_yaw = keep

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
	_arm_requested = _talk_from_arm.y
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

## Lerp после перестановки цели или у угла может завести pivot в World: одной длиной плеча это не исправить.
## Пока сфера свободна, позиция и состояние следования остаются прежними.
func _resolve_pivot_overlap(previous: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = arm.shape
	query.margin = 0.0
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = ARM_MASK
	var excluded: Array[RID] = permanent_exclusions.duplicate()
	if target is CollisionObject3D:
		excluded.append((target as CollisionObject3D).get_rid())
	query.exclude = excluded
	if space.intersect_shape(query, 1).is_empty():
		return false
	var head := target.global_position
	if profile == &"on_foot" and target is CharacterBody3D:
		head.y = _ground_y
	head += Vector3.UP * (float(PROFILES[profile]["height"]) + _lift * WALL_LIFT)
	var anchors: Array[Vector3] = [_goal(), head, previous]
	for index in anchors.size():
		query.transform.origin = anchors[index]
		if not space.intersect_shape(query, 1).is_empty():
			continue
		global_position = anchors[index]
		var retreat_offsets := index > 0
		if retreat_offsets:
			_shoulder_now = 0.0
			_dodge = 0.0
		# После native Arm фиксируем итоговую позу камеры, чтобы не рисовать перелёт через стену.
		call_deferred(&"reset_physics_interpolation")
		return retreat_offsets
	push_error("CameraRig: proposed pivot, goal, unoffset head and previous pivot intersect World")
	return false

## Длинный sweep локализует стену, короткий уточняет границу без сантиметровых скачков GJK.
## Даже при coarse no-hit проверяем конец: длинный запрос у Бабки иногда пропускал близкую стену.
func _safe_arm_distance(requested: float) -> float:
	var space := get_world_3d().direct_space_state
	var pivot := global_position
	var direction := Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.BACK
	var length := requested + ARM_COLLISION_CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = arm.shape
	query.margin = arm.margin + ARM_COLLISION_CLEARANCE
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	query.motion = direction * length
	query.collision_mask = ARM_MASK
	var excluded: Array[RID] = permanent_exclusions.duplicate()
	if target is CollisionObject3D:
		excluded.append((target as CollisionObject3D).get_rid())
	query.exclude = excluded
	var coarse := space.cast_motion(query)
	if coarse.size() != 2:
		return _arm_pivot_fallback(space, query, pivot)
	var start := maxf(0.0, length - 2.0 * ARM_COLLISION_CLEARANCE)
	var end := length
	if coarse[0] < 1.0:
		start = maxf(0.0, length * coarse[0] - ARM_COLLISION_CLEARANCE)
		end = minf(length, length * coarse[1] + ARM_COLLISION_CLEARANCE)
	query.margin = 0.0
	query.transform.origin = pivot + direction * start
	query.motion = Vector3.ZERO
	if not space.intersect_shape(query, 1).is_empty():
		return _arm_pivot_fallback(space, query, pivot)
	query.margin = arm.margin + ARM_COLLISION_CLEARANCE
	query.motion = direction * (end - start)
	var fine := space.cast_motion(query)
	if fine.size() != 2:
		return _arm_pivot_fallback(space, query, pivot)
	var free := requested
	if fine[0] < 1.0:
		free = clampf(start + (end - start) * fine[0] - ARM_COLLISION_CLEARANCE, 0.0, requested)
	elif coarse[0] < 1.0:
		free = minf(start, requested) # противоречие запросов: оставить проверенную начальную точку
	query.margin = 0.0
	query.transform.origin = pivot + direction * free
	query.motion = Vector3.ZERO
	if not space.intersect_shape(query, 1).is_empty():
		return _arm_pivot_fallback(space, query, pivot)
	# Капсула содержит весь путь сферы, включая более короткое плечо после сглаживания или native collision.
	var radius: float = (arm.shape as SphereShape3D).radius
	_arm_path_shape.radius = radius
	_arm_path_shape.height = free + 2.0 * radius
	query.shape = _arm_path_shape
	query.transform = Transform3D(Basis(Quaternion(Vector3.UP, direction)), pivot + direction * (free * 0.5))
	if not space.intersect_shape(query, 1).is_empty():
		return _arm_pivot_fallback(space, query, pivot)
	return free

## Нулевая длина безопасна только при свободной сфере pivot; иначе нарушен контракт положения rig.
func _arm_pivot_fallback(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, pivot: Vector3) -> float:
	query.shape = arm.shape
	query.margin = 0.0
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	query.motion = Vector3.ZERO
	if not space.intersect_shape(query, 1).is_empty():
		push_error("CameraRig: pivot sphere intersects World; arm length cannot restore a clear pivot")
	return 0.0

## Доля свободного хода сферы пружины от from до to по слоям пружины (без Илюши и постоянных исключений).
func _free_fraction(from: Vector3, to: Vector3) -> float:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = arm.shape
	# GodotPhysics3D использует margin только в broadphase; физический отступ задаётся длиной плеча.
	query.margin = arm.margin + ARM_COLLISION_CLEARANCE
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
	_follow_ramp = 0.0
	talk_focus = Vector3.INF
	_return_active = false
	yaw = wrapf(yaw - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * mouse_sensitivity, PITCH_MIN, PITCH_MAX)

## Опора ходьбы догоняет камеру: вызывается при смене нажатых клавиш.
func sync_input_yaw() -> void:
	input_yaw = yaw

## Сдвиг вбок, чтобы тонкий столб не закрывал Илюшу: столбы ближе DODGE_CLEAR (в плане) к отрезку «голова — несдвинутая
## камера» на отрезке до стены (длина пружины). Считается по несдвинутой линии — без качелей «объехал → вернулся».
func _dodge_target() -> float:
	if _thin.is_empty() or target == null:
		return 0.0
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var origin := target.global_position + right * _shoulder_now
	var reach := minf(arm.spring_length, arm.get_hit_length() + 0.3)
	var want := 0.0
	for body in _thin.values():
		var node := body as Node3D
		if not is_instance_valid(node) or (node as CollisionObject3D).collision_layer & ARM_MASK == 0:
			continue
		var rel := node.global_position - origin
		var along := rel.x * back.x + rel.z * back.z
		if along < 0.4 or along > reach:
			continue
		var off := rel.x * right.x + rel.z * right.z
		if absf(off) >= DODGE_CLEAR:
			continue
		var need := (-1.0 if off >= 0.0 else 1.0) * (DODGE_CLEAR - absf(off))
		if absf(need) > absf(want):
			want = need
	return clampf(want, -DODGE_MAX, DODGE_MAX)

## Тонкие столбы у самой камеры — полупрозрачные; отошли — снова сплошные.
func _fade_near_poles() -> void:
	if _thin.is_empty() or camera == null:
		return
	var on_foot := profile == &"on_foot"   # в машине камера проносится мимо столбов — без смены прозрачности
	var at := camera.global_position
	for body in _thin.values():
		var node := body as Node3D
		if not is_instance_valid(node):
			continue
		var near := on_foot and (node as CollisionObject3D).collision_layer & ARM_MASK != 0 and Vector2(node.global_position.x - at.x, node.global_position.z - at.z).length() < POLE_FADE_NEAR
		if near == _faded.has(node):
			continue
		if near:
			var meshes := _pole_meshes(node)
			_faded[node] = meshes
			for m in meshes:
				(m as GeometryInstance3D).transparency = POLE_FADE
		else:
			for m in _faded[node]:
				if is_instance_valid(m):
					(m as GeometryInstance3D).transparency = 0.0
			_faded.erase(node)

## BREAK-03: физический столб — ребёнок Breakable, облик сохранён в его env_nodes.
## Общие EnvDress MultiMesh не трогаем: прозрачность пакета скрыла бы и чужие столбы.
func _pole_meshes(body: Node3D) -> Array:
	var roots: Array = [body]
	var owner_node := body.get_parent()
	if owner_node and owner_node.has_method("env_hidden"):
		roots.append_array(owner_node.env_nodes)
	var meshes: Array = []
	for source: Node in roots:
		meshes.append_array(source.find_children("*", "GeometryInstance3D", true, false))
	return meshes

## Столбы, полупрозрачные сейчас (для проверок).
func faded_poles() -> Array:
	return _faded.keys()

func _goal() -> Vector3:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var point := target.global_position
	if profile == &"on_foot" and target is CharacterBody3D:
		point.y = _ground_y
	return point + Vector3.UP * (float(PROFILES[profile]["height"]) + _lift * WALL_LIFT) + right * (_shoulder_now + _dodge)
